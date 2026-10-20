"""eksport.py fayli -> mahalliy Postgres (`qobil` bazasi, docker-compose.yml).

Har ishga tushirishda baza NOLDAN yaratiladi (schema.sql + policies.sql) va hamma qator bitta
tranzaksiyada yoziladi — qayta ishga tushirish xavfsiz, natija har safar bir xil.
Qoidalarsiz (postgres roli) yoziladi: Firestore ham eski ma'lumotni qayta tekshirmaydi.
Hisobotga faqat sonlar va maydon NOMLARI chiqadi, qiymatlar emas.
Jadvalda ustuni yo'q maydon bo'lsa — hech narsa yozilmaydi, kod 1 (ma'lumot jimgina yo'qolmasin).
Ikkinchi fayl (ixtiyoriy) — akkauntlar: `firebase auth:export backend/data/akkauntlar.json
--format=json --project kotta-qani-09111753`.

    python backend/kochirish/importer.py backend/data/eksport-<sana>.json [backend/data/akkauntlar.json]
"""

import base64
import json
import os
import re
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

import psycopg
from psycopg import sql
from psycopg.types.json import Jsonb

BACKEND = Path(__file__).resolve().parents[1]
DB = 'qobil'

# Firestore to'plami -> (jadval, hujjat yo'lidan olinadigan kalit ustunlari)
# Yo'l: users/{uid}/days/{sana} -> ota id 'user_id', hujjat id 'day'
TABLES = {
    'users': ('users', None, 'id'),
    'trainers': ('trainers', None, 'id'),
    'ratings': ('ratings', None, 'trainer_id'),
    'gyms': ('gyms', None, 'id'),
    'foods': ('foods', None, 'id'),
    'plans': ('plans', None, 'id'),
    'exercises': ('exercises', None, 'id'),
    'shop': ('shop', None, 'id'),
    'orders': ('orders', None, 'id'),
    'reminders': ('reminders', None, 'id'),
    'memberships': ('memberships', None, 'user_id'),
    'days': ('user_days', 'user_id', 'day'),
    'weights': ('weights', 'user_id', 'id'),
    'photos': ('photos', 'user_id', 'id'),
    'subscriptions': ('subscriptions', 'user_id', 'id'),
    'attendance': ('attendance', 'user_id', 'day'),
    'messages': ('chat_messages', 'chat_user_id', 'id'),
}

# "Osilib qolgan" ishoralar: (jadval, ustun) -> qaysi jadvalning id'siga
REFS = [
    ('users', 'trainer_id', 'users'), ('users', 'gym_id', 'gyms'), ('users', 'plan_id', 'plans'),
    ('trainers', 'id', 'users'), ('ratings', 'trainer_id', 'users'), ('memberships', 'user_id', 'users'),
    ('orders', 'client_id', 'users'), ('orders', 'trainer_id', 'users'), ('orders', 'gym_id', 'gyms'),
    ('orders', 'product_id', 'shop'), ('reminders', 'client_id', 'users'),
    ('reminders', 'trainer_id', 'users'),
]


def snake(name):
    return re.sub(r'(?<!^)(?=[A-Z])', '_', name).lower()


def value(v):
    """Firestore REST turlangan qiymati -> Python qiymati."""
    (kind, x), = v.items()
    if kind == 'nullValue':
        return None
    if kind == 'integerValue':
        return int(x)
    if kind in ('stringValue', 'booleanValue', 'doubleValue', 'referenceValue'):
        return x
    if kind == 'timestampValue':
        return datetime.fromisoformat(x.replace('Z', '+00:00'))
    if kind == 'bytesValue':
        return base64.b64decode(x)
    if kind == 'arrayValue':
        return [value(i) for i in x.get('values', [])]
    if kind == 'mapValue':
        return {k: value(i) for k, i in x.get('fields', {}).items()}
    if kind == 'geoPointValue':
        return x
    raise ValueError(f'noma\'lum Firestore turi: {kind}')


def jsonable(x):
    """jsonb ustuniga: sana -> ISO satr, bayt -> base64."""
    if isinstance(x, dict):
        return {k: jsonable(v) for k, v in x.items()}
    if isinstance(x, list):
        return [jsonable(v) for v in x]
    if isinstance(x, datetime):
        return x.isoformat()
    if isinstance(x, bytes):
        return base64.b64encode(x).decode()
    return x


def to_row(collection, doc):
    """Firestore hujjati -> (jadval, {ustun: qiymat})."""
    table, parent_col, id_col = TABLES[collection]
    parts = doc['name'].split('/documents/', 1)[1].split('/')
    row = {snake(k): value(v) for k, v in doc.get('fields', {}).items()}
    row[id_col] = parts[-1]
    if parent_col:
        row[parent_col] = parts[1]
    return table, row


def plan(export, types):
    """Yoziladigan qatorlar va topilgan muammolar (ustuni yo'q maydonlar)."""
    rows, unknown = defaultdict(list), defaultdict(Counter)
    for collection, docs in export['collections'].items():
        for doc in docs:
            table, row = to_row(collection, doc)
            for col in row:
                if col not in types[table]:
                    unknown[table][col] += 1
            rows[table].append(row)
    return rows, unknown


def connect(dbname):
    env = {}
    for line in (BACKEND / '.env').read_text(encoding='utf-8').splitlines():
        if '=' in line and not line.lstrip().startswith('#'):
            k, v = line.split('=', 1)
            env[k.strip()] = v.strip()
    return psycopg.connect(
        host=os.environ.get('BACKEND_DB_HOST', '127.0.0.1'), port=int(os.environ.get('BACKEND_DB_PORT', '5433')),
        user='postgres', password=env['BACKEND_DB_PASS'], dbname=dbname, autocommit=True)


def column_types(conn):
    types = defaultdict(dict)
    for table, col, typ in conn.execute(
            "select table_name, column_name, data_type from information_schema.columns "
            "where table_schema = 'public'"):
        types[table][col] = typ
    return types


def recreate(dbname):
    with connect('postgres') as c:
        c.execute(sql.SQL('drop database if exists {} with (force)').format(sql.Identifier(dbname)))
        c.execute(sql.SQL('create database {}').format(sql.Identifier(dbname)))
    conn = connect(dbname)
    for name in ('schema.sql', 'policies.sql'):
        conn.execute((BACKEND / 'db' / name).read_text(encoding='utf-8'))
    return conn


def write(conn, rows, types):
    with conn.transaction():
        for table, items in rows.items():
            for row in items:
                vals = [Jsonb(jsonable(v)) if types[table][k] == 'jsonb' and v is not None else v
                        for k, v in row.items()]
                conn.execute(
                    sql.SQL('insert into {} ({}) values ({})').format(
                        sql.Identifier(table), sql.SQL(', ').join(map(sql.Identifier, row)),
                        sql.SQL(', ').join(sql.Placeholder() * len(row))), vals)


def dangling(conn):
    out = {}
    for table, col, target in REFS:
        n = conn.execute(sql.SQL(
            "select count(*) from {t} r where coalesce(r.{c}, '') <> '' "
            "and not exists (select 1 from {g} x where x.id = r.{c})").format(
            t=sql.Identifier(table), c=sql.Identifier(col), g=sql.Identifier(target))).fetchone()[0]
        if n:
            out[f'{table}.{col} -> {target}'] = n
    return out


def ms(x):
    return datetime.fromtimestamp(int(x) / 1000, timezone.utc) if x else None


def account_rows(auth_export):
    """`firebase auth:export --format=json` -> kirish.accounts qatorlari.
    Firebase xeshi saqlanmaydi: parol birinchi kirishda Firebase orqali tekshiriladi (parol.py)."""
    rows = []
    for u in auth_export.get('users', []):
        email = u.get('email')
        local = (email or '').split('@')[0]
        rows.append({
            'id': u['localId'], 'email': email, 'phone': local if local.isdigit() else None,
            'password_algo': 'firebase', 'created_at': ms(u.get('createdAt')),
            'last_sign_in': ms(u.get('lastSignedInAt')), 'disabled': bool(u.get('disabled', False)),
        })
    return rows


def write_accounts(conn, rows, out):
    with conn.transaction():
        for row in rows:
            conn.execute(
                sql.SQL('insert into kirish.accounts ({}) values ({})').format(
                    sql.SQL(', ').join(map(sql.Identifier, row)), sql.SQL(', ').join(sql.Placeholder() * len(row))),
                list(row.values()))
    n = conn.execute('select count(*) from kirish.accounts').fetchone()[0]
    no_doc = conn.execute('select count(*) from kirish.accounts a where not exists '
                          '(select 1 from users u where u.id = a.id)').fetchone()[0]
    no_acc = conn.execute('select count(*) from users u where not exists '
                          '(select 1 from kirish.accounts a where a.id = u.id)').fetchone()[0]
    out(f'akkauntlar: Firebase {len(rows)}, Postgres {n}; hujjatsiz akkaunt {no_doc}, akkauntsiz hujjat {no_acc}')
    return n == len(rows)


def run(export, dbname=DB, out=print, auth_export=None):
    """Bazani noldan yaratadi va eksportni yozadi. Muvaffaqiyat — True."""
    conn = recreate(dbname)
    try:
        types = column_types(conn)
        rows, unknown = plan(export, types)
        if unknown:
            out('XATO: jadvalda ustuni yo\'q maydonlar (hech narsa yozilmadi):')
            for table, cols in unknown.items():
                for col, n in cols.items():
                    out(f'  {table}.{col}: {n} ta hujjatda')
            return False
        write(conn, rows, types)
        ok = True
        out("to'plam".ljust(14) + ' Firestore'.rjust(10) + ' Postgres'.rjust(10))
        for collection, docs in export['collections'].items():
            table = TABLES[collection][0]
            n = conn.execute(sql.SQL('select count(*) from {}').format(sql.Identifier(table))).fetchone()[0]
            ok &= n == len(docs)
            out(f'{collection:14} {len(docs):>9} {n:>9}{"" if n == len(docs) else "  <- FARQ"}')
        refs = dangling(conn)
        out('Osilib qolgan ishoralar: ' + (', '.join(f'{k}: {v}' for k, v in refs.items()) or "yo'q"))
        if auth_export is not None:
            ok &= write_accounts(conn, account_rows(auth_export), out)
        return ok
    finally:
        conn.close()


if __name__ == '__main__':
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    data = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
    auth = json.loads(Path(sys.argv[2]).read_text(encoding='utf-8')) if len(sys.argv) == 3 else None
    sys.exit(0 if run(data, auth_export=auth) else 1)
