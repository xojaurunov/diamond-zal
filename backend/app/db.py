"""Baza ulanishlari. Har ma'lumot so'rovi foydalanuvchi NOMIDAN boradi: `app_user` roli va `app.uid` —
shunda ruxsatlarni (db/policies.sql, RLS) bazaning o'zi tekshiradi, servis kodida takrorlanmaydi.
`service()` — faqat kirish (kirish.accounts) uchun, RLS'siz."""

import os
from contextlib import contextmanager
from pathlib import Path

import psycopg
from fastapi import HTTPException
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

BACKEND = Path(__file__).resolve().parents[1]


def env(key, default=None):
    """Avval muhit o'zgaruvchisi, keyin backend/.env (git'ga tushmaydi)."""
    if key in os.environ:
        return os.environ[key]
    path = BACKEND / '.env'
    if path.exists():
        for line in path.read_text(encoding='utf-8').splitlines():
            if '=' in line and not line.lstrip().startswith('#'):
                k, v = line.split('=', 1)
                if k.strip() == key:
                    return v.strip()
    if default is None:
        raise RuntimeError(f'{key} sozlanmagan (backend/.env)')
    return default


def conninfo(dbname=None):
    return psycopg.conninfo.make_conninfo(
        host=env('BACKEND_DB_HOST', '127.0.0.1'), port=env('BACKEND_DB_PORT', '5433'),
        user=env('BACKEND_DB_USER', 'postgres'), password=env('BACKEND_DB_PASS'),
        dbname=dbname or env('BACKEND_DB_NAME', 'qobil'))


class Db:
    def __init__(self, info):
        self.pool = ConnectionPool(info, min_size=1, max_size=10, open=False,
                                   kwargs={'autocommit': True, 'row_factory': dict_row})

    def open(self):
        self.pool.open(wait=True)

    def close(self):
        self.pool.close()

    @contextmanager
    def as_user(self, uid):
        """Bitta tranzaksiya foydalanuvchi nomidan. Ruxsat xatosi -> 403."""
        with self.pool.connection() as conn:
            try:
                with conn.transaction():
                    conn.execute('set local role app_user')
                    conn.execute("select set_config('app.uid', %s, true)", (uid,))
                    yield conn
            except psycopg.errors.InsufficientPrivilege as e:
                raise HTTPException(403, "ruxsat yo'q") from e

    @contextmanager
    def service(self):
        """Kirish uchun (kirish.accounts) — RLS'siz. Ma'lumot so'rovlari uchun ishlatilmaydi."""
        with self.pool.connection() as conn:
            yield conn
