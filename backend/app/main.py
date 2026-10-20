"""Qobil servisi (FastAPI). Ishga tushirish (backend papkasidan):
    .venv/Scripts/python -m uvicorn app.main:app --port 8000
Sozlamalar: backend/.env — BACKEND_DB_PASS, JWT_SECRET (git'ga tushmaydi)."""

import time
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel

from kochirish import parol

from . import auth
from .db import Db, conninfo, env


class LoginIn(BaseModel):
    phone: str
    password: str


def create_app(db=None, secret=None, firebase_check=None, clock=time.time):
    db = db or Db(conninfo())
    secret = secret or env('JWT_SECRET')
    check = firebase_check or parol.firebase_check
    limiter = auth.RateLimit()
    bearer = HTTPBearer(auto_error=False)

    @asynccontextmanager
    async def lifespan(_):
        db.open()
        yield
        db.close()

    app = FastAPI(title='Qobil', lifespan=lifespan)

    def current_uid(cred: HTTPAuthorizationCredentials | None = Depends(bearer)):
        uid = cred and auth.read_token(cred.credentials, secret)
        if not uid:
            raise HTTPException(401, 'kirish kerak')
        return uid

    @app.get('/health')
    def health():
        return {'ok': True}

    @app.post('/auth/login')
    def login(body: LoginIn, request: Request):
        now = clock()
        email = auth.phone_email(body.phone)
        ip = request.client.host if request.client else '-'
        # urinishlar parol tekshirilishidan OLDIN sanaladi — tanlab topishning oldini oladi
        if not limiter.allow(f'ip:{ip}', now) or (email and not limiter.allow(f'tel:{email}', now)):
            raise HTTPException(429, "juda ko'p urinish — bir daqiqadan keyin qayta urining")
        uid = None
        if email and body.password:
            with db.service() as conn:
                uid = parol.login(conn, email, body.password, check)
        if not uid:
            raise HTTPException(401, "telefon raqam yoki parol noto'g'ri")
        return {'token': auth.make_token(uid, secret, now), 'uid': uid}

    @app.get('/me')
    def me(uid: str = Depends(current_uid)):
        with db.as_user(uid) as conn:
            row = conn.execute('select * from users where id = %s', (uid,)).fetchone()
        if row is None:
            raise HTTPException(404, 'profil topilmadi')
        return row

    app.state.db = db
    return app


# uvicorn uchun; JWT_SECRET sozlanmagan bo'lsa (masalan testlarda) — yaratilmaydi
app = create_app() if env('JWT_SECRET', '') else None
