"""Qoida testlari uchun mahalliy Postgres (docker-compose.yml) va so'rov yordamchilari.

Har ishga tushirishda `qobil_test` bazasi noldan yaratiladi: schema.sql + policies.sql.
Firestore semantikasiga moslik:
  * `pg.ok(uid).<amal>`  — amal o'tishi SHART (yozuvda kamida 1 qator o'zgaradi, o'qishda qator qaytadi);
  * `pg.no(uid).<amal>`  — amal rad etilishi SHART. Yozuv: ruxsat xatosi yoki 0 qator (qator
    haqiqatan bor-yo'qligi alohida tekshiriladi, aks holda test ma'nosiz bo'lib qoladi).
    O'qish: Postgres Firestore'dagidek butun so'rovni rad etmaydi — ko'rinmas qatorlarni
    yashiradi. Shuning uchun "ko'ra OLMAYDI" = foydalanuvchi bazada BOR qatorlarning hammasini
    ko'rmaydi (`get` — qator qaytmaydi, `list` — kamroq qator qaytadi);
  * `pg.no_extra(uid)` — Firestore'dagi "ortiqcha maydon" testlari: bunday ustun yo'qligi ham rad.
  * `pg.admin` — qoidalarsiz (Firestore'dagi `withSecurityRulesDisabled`).
`NOW` — Firestore `serverTimestamp()` (SQL `now()`).
"""

import os
from pathlib import Path

import psycopg
import pytest
from psycopg import sql
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

ROOT = Path(__file__).resolve().parents[1]
TEST_DB = 'qobil_test'
NOW = object()

# Hujjat kaliti: Firestore yo'li -> jadval ustunlari
KEYS = {
    'users': ['id'], 'user_days': ['user_id', 'day'], 'weights': ['user_id', 'id'],
    'photos': ['user_id', 'id'], 'subscriptions': ['user_id', 'id'], 'attendance': ['user_id', 'day'],
    'memberships': ['user_id'], 'trainers': ['id'], 'ratings': ['trainer_id'], 'foods': ['id'],
    'plans': ['id'], 'exercises': ['id'], 'gyms': ['id'], 'shop': ['id'], 'orders': ['id'],
    'reminders': ['id'], 'chat_messages': ['chat_user_id', 'id'], 'videos': ['id'],
}

# Rad etish deb hisoblanadigan xatolar: ruxsat (RLS / trigger), cheklov, noto'g'ri tur
DENIED = {'42501', '23514', '23502', '22P02', '22003'}
UNDEFINED_COLUMN = '42703'


def _env():
    vals = {}
    env_file = ROOT / '.env'
    if env_file.exists():
        for line in env_file.read_text(encoding='utf-8').splitlines():
            if '=' in line and not line.lstrip().startswith('#'):
                k, v = line.split('=', 1)
                vals[k.strip()] = v.strip()
    vals.update({k: v for k, v in os.environ.items() if k.startswith('BACKEND_DB_')})
    return vals


def _connect(dbname):
    e = _env()
    return psycopg.connect(
        host=e.get('BACKEND_DB_HOST', '127.0.0.1'), port=int(e.get('BACKEND_DB_PORT', '5433')),
        user='postgres', password=e['BACKEND_DB_PASS'], dbname=dbname, autocommit=True)


class Denied(Exception):
    pass


class Tx:
    """Bitta tranzaksiya ichidagi amallar (Firestore'dagi bitta yozuv yoki batch)."""

    def __init__(self, pg, cur):
        self.pg, self.cur = pg, cur

    def _value(self, table, col, v):
        if v is NOW:
            return sql.SQL('now()'), []
        if self.pg.types[table].get(col) == 'jsonb' and v is not None:
            v = Jsonb(v)
        return sql.Placeholder(), [v]

    @staticmethod
    def _where(key):
        parts = [sql.SQL('{} = %s').format(sql.Identifier(k)) for k in key]
        return sql.SQL(' and ').join(parts), list(key.values())

    def get(self, table, **key):
        w, args = self._where(key)
        self.cur.execute(sql.SQL('select * from {} where ').format(sql.Identifier(table)) + w, args)
        return self.cur.fetchone()

    def list(self, table, **where):
        parts, args = [], []
        for k, v in where.items():
            if isinstance(v, (list, tuple)):
                parts.append(sql.SQL('{} = any(%s)').format(sql.Identifier(k)))
                args.append(list(v))
            else:
                parts.append(sql.SQL('{} = %s').format(sql.Identifier(k)))
                args.append(v)
        q = sql.SQL('select * from {}').format(sql.Identifier(table))
        if parts:
            q += sql.SQL(' where ') + sql.SQL(' and ').join(parts)
        self.cur.execute(q, args)
        return self.cur.fetchall()

    def insert(self, table, data):
        cols, vals, args = [], [], []
        for k, v in data.items():
            ph, a = self._value(table, k, v)
            cols.append(sql.Identifier(k))
            vals.append(ph)
            args += a
        self.cur.execute(
            sql.SQL('insert into {} ({}) values ({})').format(
                sql.Identifier(table), sql.SQL(', ').join(cols), sql.SQL(', ').join(vals)), args)
        return self.cur.rowcount

    def update(self, table, data, replace=False, **key):
        """updateDoc: faqat berilgan maydonlar. `program.chest` — jsonb ichidagi kalit.
        replace=True — setDoc (berilmagan ustunlar standart qiymatga qaytadi)."""
        sets, args = [], []
        for k, v in data.items():
            if '.' in k:
                col, path = k.split('.', 1)
                sets.append(sql.SQL("{c} = jsonb_set(coalesce({c}, '{{}}'::jsonb), %s, %s)").format(
                    c=sql.Identifier(col)))
                args += [path.split('.'), Jsonb(v)]
                continue
            ph, a = self._value(table, k, v)
            sets.append(sql.SQL('{} = ').format(sql.Identifier(k)) + ph)
            args += a
        if replace:
            for col in self.pg.types[table]:
                if col not in data and col not in key:
                    sets.append(sql.SQL('{} = default').format(sql.Identifier(col)))
        w, wargs = self._where(key)
        self.cur.execute(
            sql.SQL('update {} set ').format(sql.Identifier(table)) + sql.SQL(', ').join(sets)
            + sql.SQL(' where ') + w, args + wargs)
        if self.cur.rowcount == 0:
            raise Denied(f'{table}: 0 qator')
        return self.cur.rowcount

    def set(self, table, data, **key):
        """setDoc: hujjat bo'lsa — to'liq almashtirish (update qoidasi), bo'lmasa — yaratish."""
        if self.pg.exists(table, **key):
            return self.update(table, data, replace=True, **key)
        return self.insert(table, {**key, **data})

    def add(self, table, data, **parent):
        """addDoc: yangi id bilan yaratish."""
        return self.insert(table, {**parent, **data})

    def delete(self, table, **key):
        w, args = self._where(key)
        self.cur.execute(sql.SQL('delete from {} where ').format(sql.Identifier(table)) + w, args)
        if self.cur.rowcount == 0:
            raise Denied(f'{table}: 0 qator')
        return self.cur.rowcount


class Ctx:
    """Bitta foydalanuvchi nomidan amallar; har amal — alohida tranzaksiya."""

    def __init__(self, pg, uid, expect, privileged=False, extra=False):
        self.pg, self.uid, self.expect = pg, uid, expect
        self.privileged, self.extra = privileged, extra

    def _run(self, fn):
        conn = self.pg.conn
        with conn.transaction():
            with conn.cursor(row_factory=dict_row) as cur:
                if not self.privileged:
                    cur.execute('set local role app_user')
                    cur.execute("select set_config('app.uid', %s, true)", (self.uid or '',))
                return fn(Tx(self.pg, cur))

    def _write(self, op, table, key, fn):
        if self.expect == 'ok':
            return self._run(fn)
        if op in ('update', 'delete') or (op == 'set' and self.pg.exists(table, **key)):
            assert self.pg.exists(table, **key), f'sinov ma\'nosiz: {table} {key} bazada yo\'q'
        try:
            self._run(fn)
        except Denied:
            return
        except psycopg.Error as e:
            allowed = DENIED | ({UNDEFINED_COLUMN} if self.extra else set())
            assert e.sqlstate in allowed, f'kutilmagan xato {e.sqlstate}: {e}'
            return
        raise AssertionError('rad etilishi kerak edi, lekin o\'tdi')

    def get(self, table, **key):
        row = self._run(lambda t: t.get(table, **key))
        if self.expect == 'ok':
            assert row is not None, f'{table} {key} ko\'rinishi kerak edi'
        else:
            assert self.pg.exists(table, **key), f'sinov ma\'nosiz: {table} {key} bazada yo\'q'
            assert row is None, f'{table} {key} ko\'rinmasligi kerak edi'
        return row

    def list(self, table, **where):
        rows = self._run(lambda t: t.list(table, **where))
        if self.expect == 'no':
            everything = self.pg.admin.list(table, **where)
            assert len(rows) < len(everything), (
                f'{table} {where}: {len(rows)} ta ko\'rindi, bazada {len(everything)} ta — hammasi ko\'rinmasligi kerak')
        return rows

    def insert(self, table, data):
        return self._write('insert', table, {}, lambda t: t.insert(table, data))

    def add(self, table, data, **parent):
        return self._write('insert', table, {}, lambda t: t.add(table, data, **parent))

    def update(self, table, data, **key):
        return self._write('update', table, key, lambda t: t.update(table, data, **key))

    def set(self, table, data, **key):
        return self._write('set', table, key, lambda t: t.set(table, data, **key))

    def delete(self, table, **key):
        return self._write('delete', table, key, lambda t: t.delete(table, **key))

    def batch(self, fn):
        """Bir nechta amal bitta tranzaksiyada (Firestore writeBatch)."""
        return self._write('batch', None, {}, fn)


class Pg:
    def __init__(self, conn):
        self.conn = conn
        self.types = {}
        for table, col, typ in conn.execute(
                "select table_name, column_name, data_type from information_schema.columns "
                "where table_schema = 'public' order by ordinal_position"):
            self.types.setdefault(table, {})[col] = typ
        self.admin = Ctx(self, None, 'ok', privileged=True)

    def exists(self, table, **key):
        w, args = Tx._where(key)
        q = sql.SQL('select 1 from {} where ').format(sql.Identifier(table)) + w
        return self.conn.execute(q, args).fetchone() is not None

    def ok(self, uid):
        return Ctx(self, uid, 'ok')

    def no(self, uid):
        return Ctx(self, uid, 'no')

    def no_extra(self, uid):
        return Ctx(self, uid, 'no', extra=True)


@pytest.fixture(scope='session')
def pg():
    with _connect('postgres') as c:
        c.execute(sql.SQL('drop database if exists {} with (force)').format(sql.Identifier(TEST_DB)))
        c.execute(sql.SQL('create database {}').format(sql.Identifier(TEST_DB)))
    conn = _connect(TEST_DB)
    for name in ('schema.sql', 'policies.sql'):
        conn.execute((ROOT / 'db' / name).read_text(encoding='utf-8'))
    yield Pg(conn)
    conn.close()
