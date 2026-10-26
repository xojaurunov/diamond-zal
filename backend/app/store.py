"""Firestore'ga o'xshash hujjat qatlami Postgres ustida.

Ilova o'sha yo'llar (`users/{uid}/days/{sana}`), o'sha maydon nomlari (camelCase) va o'sha amallar bilan
ishlaydi; bu yerda ular jadval/ustun/SQL ga o'giriladi. Ruxsatlarni bazaning o'zi (RLS + triggerlar)
tekshiradi — ulanish `app_user` + `app.uid` bilan (db.as_user). Identifikatorlar faqat ro'yxatdan va
`sql.Identifier` bilan, qiymatlar — parametr.

Qiymat turlari (JSON'da): vaqt `{"$t": "2026-10-20T10:00:00Z"}`, bayt `{"$b": "base64"}`;
maydon amallari `{"$op": "serverTimestamp" | "delete" | "arrayUnion" | "arrayRemove" | "increment", ...}`.
"""

import base64
import re
import secrets
from datetime import datetime

import psycopg
from fastapi import HTTPException
from psycopg import sql
from psycopg.types.json import Jsonb

# Firestore to'plami (yo'l andozasi) -> (jadval, ota id ustuni, hujjat id ustuni)
TOP = {
    'users': ('users', None, 'id'), 'trainers': ('trainers', None, 'id'),
    'ratings': ('ratings', None, 'trainer_id'), 'gyms': ('gyms', None, 'id'),
    'foods': ('foods', None, 'id'), 'plans': ('plans', None, 'id'),
    'exercises': ('exercises', None, 'id'), 'shop': ('shop', None, 'id'), 'videos': ('videos', None, 'id'),
    'orders': ('orders', None, 'id'), 'reminders': ('reminders', None, 'id'),
    'memberships': ('memberships', None, 'user_id'),
}
SUB = {
    ('users', 'days'): ('user_days', 'user_id', 'day'),
    ('users', 'weights'): ('weights', 'user_id', 'id'),
    ('users', 'photos'): ('photos', 'user_id', 'id'),
    ('users', 'subscriptions'): ('subscriptions', 'user_id', 'id'),
    ('users', 'attendance'): ('attendance', 'user_id', 'day'),
    ('chats', 'messages'): ('chat_messages', 'chat_user_id', 'id'),
}
GROUPS = {'subscriptions': ('subscriptions', 'users', 'user_id', 'id')}
SEGMENT = re.compile(r'^[A-Za-z0-9_.\-]{1,128}$')
OPS = {'==': '=', '!=': '<>', '<': '<', '<=': '<=', '>': '>', '>=': '>='}


def bad(msg):
    return HTTPException(400, msg)


def snake(name):
    return re.sub(r'(?<!^)(?=[A-Z])', '_', name).lower()


def camel(name):
    head, *rest = name.split('_')
    return head + ''.join(p[:1].upper() + p[1:] for p in rest)


class Ref:
    """Yo'l: to'plam yoki hujjat."""

    def __init__(self, path):
        parts = [p for p in path.strip('/').split('/') if p]
        if not parts or not all(SEGMENT.match(p) for p in parts):
            raise bad('yo\'l noto\'g\'ri')
        self.parts = parts
        if len(parts) in (1, 2):
            if parts[0] not in TOP:
                raise bad('noma\'lum to\'plam')
            self.table, self.parent_col, self.id_col = TOP[parts[0]]
            self.parent, self.top = None, parts[0]
            self.doc_id = parts[1] if len(parts) == 2 else None
        elif len(parts) in (3, 4):
            key = (parts[0], parts[2])
            if key not in SUB:
                raise bad('noma\'lum to\'plam')
            self.table, self.parent_col, self.id_col = SUB[key]
            self.parent, self.top = parts[1], parts[0]
            self.doc_id = parts[3] if len(parts) == 4 else None
        else:
            raise bad('yo\'l juda chuqur')
        self.collection_path = '/'.join(parts[:-1] if self.doc_id else parts)

    @property
    def is_doc(self):
        return self.doc_id is not None

    def key(self, doc_id=None):
        k = {self.id_col: doc_id or self.doc_id}
        if self.parent_col:
            k[self.parent_col] = self.parent
        return k


class Store:
    """Bitta ulanish (tranzaksiya) ichidagi amallar."""

    _types = None

    def __init__(self, conn):
        self.conn = conn
        if Store._types is None:
            Store.load_types(conn)
        self.types = Store._types

    @classmethod
    def load_types(cls, conn):
        cls._types = {}
        with conn.cursor(row_factory=psycopg.rows.tuple_row) as cur:
            for t, c, typ, udt in cur.execute(
                    "select table_name, column_name, data_type, udt_name from information_schema.columns "
                    "where table_schema = 'public'").fetchall():
                cls._types.setdefault(t, {})[c] = (typ, udt)

    # ---------- qiymatlar ----------

    def _col(self, ref, field):
        col = snake(field)
        if col not in self.types[ref.table] or col in (ref.id_col, ref.parent_col):
            raise bad(f'noma\'lum maydon: {field}')
        return col

    def _in(self, ref, col, v):
        """JSON qiymat -> Postgres parametri."""
        if isinstance(v, dict) and '$t' in v:
            return datetime.fromisoformat(v['$t'].replace('Z', '+00:00'))
        if isinstance(v, dict) and '$b' in v:
            return base64.b64decode(v['$b'])
        if v is not None and self.types[ref.table][col][0] == 'jsonb':
            return Jsonb(v)
        return v

    @staticmethod
    def _out_value(v):
        if isinstance(v, datetime):
            return {'$t': v.isoformat().replace('+00:00', 'Z')}
        if isinstance(v, (bytes, memoryview)):
            return {'$b': base64.b64encode(bytes(v)).decode()}
        return v

    def _doc(self, ref, row):
        collection = ref.collection_path
        if ref.parent_col and not ref.parent:  # to'plam guruhi
            collection = f"{GROUPS[ref.table][1]}/{row[ref.parent_col]}/{ref.table}"
        doc_id = row[ref.id_col]
        data = {camel(k): self._out_value(v) for k, v in row.items()
                if v is not None and k not in (ref.id_col, ref.parent_col)}
        return {'id': doc_id, 'path': f'{collection}/{doc_id}', 'data': data}

    # ---------- o'qish ----------

    def get(self, ref):
        if not ref.is_doc:
            raise bad('hujjat yo\'li kerak')
        w, args = self._where_key(ref.key())
        row = self.conn.execute(
            sql.SQL('select * from {} where ').format(sql.Identifier(ref.table)) + w, args).fetchone()
        return self._doc(ref, row) if row else None

    def query(self, ref, q=None, group=False):
        q = q or {}
        parts, args = [], []
        if not group and ref.parent_col:
            parts.append(sql.SQL('{} = %s').format(sql.Identifier(ref.parent_col)))
            args.append(ref.parent)
        for f, op, v in q.get('where', []):
            col = self._col(ref, f) if f != '__name__' else ref.id_col
            if op in OPS:
                if v is None and op in ('==', '!='):
                    parts.append(sql.SQL('{} is ' + ('' if op == '==' else 'not ') + 'null').format(
                        sql.Identifier(col)))
                    continue
                parts.append(sql.SQL('{} ' + OPS[op] + ' %s').format(sql.Identifier(col)))
                args.append(self._in(ref, col, v))
            elif op == 'in':
                parts.append(sql.SQL('{} = any(%s)').format(sql.Identifier(col)))
                args.append(list(v))
            elif op == 'array-contains':
                parts.append(sql.SQL('%s = any({})').format(sql.Identifier(col)))
                args.append(v)
            else:
                raise bad(f'noma\'lum shart: {op}')
        query = sql.SQL('select * from {}').format(sql.Identifier(ref.table))
        if parts:
            query += sql.SQL(' where ') + sql.SQL(' and ').join(parts)
        order = [sql.SQL('{} {}').format(sql.Identifier(self._col(ref, f)),
                                         sql.SQL('desc' if d == 'desc' else 'asc'))
                 for f, d in q.get('orderBy', [])]
        if order:
            query += sql.SQL(' order by ') + sql.SQL(', ').join(order)
        if q.get('limit'):
            query += sql.SQL(' limit %s')
            args.append(int(q['limit']))
        return [self._doc(ref, r) for r in self.conn.execute(query, args).fetchall()]

    # ---------- yozish ----------

    @staticmethod
    def _where_key(key):
        return (sql.SQL(' and ').join(sql.SQL('{} = %s').format(sql.Identifier(k)) for k in key),
                list(key.values()))

    def _assign(self, ref, field, v, existing):
        """Bitta maydon -> (ustun, SQL ifoda, parametrlar). existing=False — yangi qator (INSERT)."""
        if '.' in field:  # program.chest, sizeStock.XL — jsonb ichidagi kalit
            head, path = field.split('.', 1)
            col = self._col(ref, head)
            if self.types[ref.table][col][0] != 'jsonb':
                raise bad(f'{head} — ichki kalitli maydon emas')
            keys = path.split('.')
            c = sql.Identifier(col)
            if isinstance(v, dict) and v.get('$op') == 'delete':
                return col, sql.SQL("coalesce({}, '{{}}'::jsonb) #- %s").format(c), [keys]
            return col, sql.SQL("jsonb_set(coalesce({}, '{{}}'::jsonb), %s, %s, true)").format(c), [keys, Jsonb(v)]
        col = self._col(ref, field)
        c = sql.Identifier(col)
        typ, udt = self.types[ref.table][col]
        op = v.get('$op') if isinstance(v, dict) else None
        if op is None:
            return col, sql.Placeholder(), [self._in(ref, col, v)]
        if op == 'serverTimestamp':
            return col, sql.SQL('now()'), []
        if op == 'delete':
            return col, sql.SQL('null'), []
        if op == 'increment':
            base = sql.SQL('coalesce({}, 0)').format(c) if existing else sql.SQL('0')
            return col, base + sql.SQL(' + %s'), [v['by']]
        if op in ('arrayUnion', 'arrayRemove'):
            vals = v.get('values', [])
            if typ == 'jsonb':
                cur = sql.SQL("coalesce({}, '[]'::jsonb)").format(c) if existing else sql.SQL("'[]'::jsonb")
                if op == 'arrayUnion':
                    expr = cur + sql.SQL(" || coalesce((select jsonb_agg(e) from jsonb_array_elements(%s::jsonb) e "
                                         "where not ") + cur + sql.SQL(" @> jsonb_build_array(e)), '[]'::jsonb)")
                else:
                    expr = sql.SQL("coalesce((select jsonb_agg(e) from jsonb_array_elements(") + cur + sql.SQL(
                        ") e where not %s::jsonb @> jsonb_build_array(e)), '[]'::jsonb)")
                return col, expr, [Jsonb(vals)]
            if typ != 'ARRAY':
                raise bad(f'{field} — ro\'yxat emas')
            elem = sql.SQL(udt.lstrip('_') + '[]')
            cur = sql.SQL("coalesce({}, '{{}}')").format(c) if existing else sql.SQL("'{}'::") + elem
            if op == 'arrayUnion':
                expr = cur + sql.SQL(' || array(select distinct x from unnest(%s::') + elem + sql.SQL(
                    ') x where x <> all(') + cur + sql.SQL('))')
            else:
                expr = sql.SQL('array(select x from unnest(') + cur + sql.SQL(') x where x <> all(%s::') + elem + \
                    sql.SQL('))')
            return col, expr, [vals]
        raise bad(f'noma\'lum amal: {op}')

    def _insert(self, ref, key, data):
        cols, exprs, args = list(key), [sql.Placeholder()] * len(key), list(key.values())
        for f, v in data.items():
            if '.' in f:
                raise bad('yangi hujjatda nuqtali maydon bo\'lmaydi')
            col, e, a = self._assign(ref, f, v, existing=False)
            cols.append(col)
            exprs.append(e)
            args += a
        self.conn.execute(
            sql.SQL('insert into {} ({}) values ({})').format(
                sql.Identifier(ref.table), sql.SQL(', ').join(map(sql.Identifier, cols)), sql.SQL(', ').join(exprs)),
            args)

    def _update(self, ref, key, data, replace=False):
        sets, args = [], []
        for f, v in data.items():
            col, e, a = self._assign(ref, f, v, existing=True)
            sets.append(sql.SQL('{} = ').format(sql.Identifier(col)) + e)
            args += a
        if replace:
            given = {snake(f.split('.')[0]) for f in data}
            for col in self.types[ref.table]:
                if col not in given and col not in key:
                    sets.append(sql.SQL('{} = default').format(sql.Identifier(col)))
        if not sets:
            return 1
        w, wargs = self._where_key(key)
        cur = self.conn.execute(
            sql.SQL('update {} set ').format(sql.Identifier(ref.table)) + sql.SQL(', ').join(sets)
            + sql.SQL(' where ') + w, args + wargs)
        return cur.rowcount

    def set(self, ref, data, merge=False):
        if not ref.is_doc:
            raise bad('hujjat yo\'li kerak')
        key = ref.key()
        if self.get(ref) is None:
            self._insert(ref, key, data)
        elif not self._update(ref, key, data, replace=not merge):
            raise HTTPException(403, "ruxsat yo'q")

    def update(self, ref, data):
        if not ref.is_doc:
            raise bad('hujjat yo\'li kerak')
        if not data:
            raise bad('maydon yo\'q')
        if not self._update(ref, ref.key(), data):
            raise HTTPException(404, 'hujjat topilmadi')

    def delete(self, ref):
        if not ref.is_doc:
            raise bad('hujjat yo\'li kerak')
        w, args = self._where_key(ref.key())
        self.conn.execute(sql.SQL('delete from {} where ').format(sql.Identifier(ref.table)) + w, args)

    def add(self, ref, data):
        if ref.is_doc:
            raise bad('to\'plam yo\'li kerak')
        doc_id = new_id()
        self._insert(ref, ref.key(doc_id), data)
        return doc_id


def new_id():
    """Firestore'dagidek 20 belgili tasodifiy id."""
    abc = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    return ''.join(secrets.choice(abc) for _ in range(20))


def db_error(e):
    """Postgres xatosi -> HTTP: ruxsat/qoida — 403, qiymat — 400."""
    state = getattr(e, 'sqlstate', None)
    if state in ('42501', '23505'):
        return HTTPException(403, "ruxsat yo'q")
    if state in ('23514', '23502', '22P02', '22003', '22007', '42804'):
        return HTTPException(400, "qiymat noto'g'ri")
    return None
