"""Qobil servisi (FastAPI). Ishga tushirish (backend papkasidan):
    .venv/Scripts/python -m uvicorn app.main:app --port 8000
Sozlamalar: backend/.env — BACKEND_DB_PASS, JWT_SECRET (git'ga tushmaydi)."""

import asyncio
import json
import secrets
import time
from contextlib import asynccontextmanager
from typing import Any

import psycopg
from fastapi import Depends, FastAPI, HTTPException, Request, WebSocket, WebSocketDisconnect
from fastapi.concurrency import run_in_threadpool
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from psycopg.rows import tuple_row
from pydantic import BaseModel

from kochirish import parol

from . import auth, live, store
from .db import Db, conninfo, env


class LoginIn(BaseModel):
    phone: str
    password: str


class RegisterIn(BaseModel):
    phone: str
    password: str
    name: str = ''


class PasswordIn(BaseModel):
    current: str
    next: str = ''


class DocIn(BaseModel):
    data: dict[str, Any] = {}
    merge: bool = False


class BatchOp(BaseModel):
    op: str  # set | update | delete | add
    path: str
    data: dict[str, Any] = {}
    merge: bool = False


class BatchIn(BaseModel):
    ops: list[BatchOp]


def new_uid():
    """Firebase uid'iga o'xshash 28 belgili id"""
    abc = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    return ''.join(secrets.choice(abc) for _ in range(28))


def create_app(db=None, secret=None, firebase_check=None, clock=time.time):
    db = db or Db(conninfo())
    secret = secret or env('JWT_SECRET')
    check = firebase_check or parol.firebase_check
    limiter = auth.RateLimit()
    bearer = HTTPBearer(auto_error=False)
    hub = live.Hub()

    @asynccontextmanager
    async def lifespan(_):
        db.open()
        listener = live.Listener(db.info, hub, asyncio.get_running_loop())
        listener.start()
        yield
        listener.stop()
        db.close()

    app = FastAPI(title='Qobil', lifespan=lifespan)

    def active(uid):
        """Akkaunt bor va bloklanmagan (o'chirilgan akkauntning tokeni ishlamaydi)"""
        with db.service() as conn, conn.cursor(row_factory=tuple_row) as cur:
            return cur.execute('select 1 from kirish.accounts where id = %s and not disabled', (uid,)).fetchone()

    def current_uid(cred: HTTPAuthorizationCredentials | None = Depends(bearer)):
        uid = cred and auth.read_token(cred.credentials, secret)
        if not uid or not active(uid):
            raise HTTPException(401, 'kirish kerak')
        return uid

    def client_ip(request):
        return request.client.host if request.client else '-'

    def too_many():
        return HTTPException(429, "juda ko'p urinish — bir daqiqadan keyin qayta urining")

    @app.get('/health')
    def health():
        return {'ok': True}

    # ---------- kirish va akkauntlar ----------

    @app.post('/auth/login')
    def login(body: LoginIn, request: Request):
        now = clock()
        email = auth.phone_email(body.phone)
        # urinishlar parol tekshirilishidan OLDIN sanaladi — tanlab topishning oldini oladi
        if not limiter.allow(f'ip:{client_ip(request)}', now) or (email and not limiter.allow(f'tel:{email}', now)):
            raise too_many()
        uid = None
        if email and body.password:
            with db.service() as conn:
                uid = parol.login(conn, email, body.password, check)
        if not uid:
            raise HTTPException(401, "telefon raqam yoki parol noto'g'ri")
        return {'token': auth.make_token(uid, secret, now), 'uid': uid}

    def create_account(conn, email, password):
        with conn.cursor(row_factory=tuple_row) as cur:
            if cur.execute('select 1 from kirish.accounts where email = %s', (email,)).fetchone():
                raise HTTPException(409, 'bu raqam bilan akkaunt bor')
            uid = new_uid()
            cur.execute("insert into kirish.accounts (id, email, phone, password_algo, password_hash, created_at) "
                        "values (%s, %s, %s, 'scrypt', %s, now())",
                        (uid, email, email.split('@')[0], parol.hash_password(password)))
        return uid

    def check_new_password(pw):
        if len(pw) < 6:
            raise HTTPException(400, 'parol kamida 6 belgi')

    @app.post('/auth/register')
    def register(body: RegisterIn, request: Request):
        """Yangi akkaunt (Firebase createUser kabi). Profilni (users) ilova o'zi yozadi."""
        if not limiter.allow(f'ip:{client_ip(request)}', clock()):
            raise too_many()
        email = auth.phone_email(body.phone)
        if not email:
            raise HTTPException(400, "telefon raqam noto'g'ri")
        check_new_password(body.password)
        with db.service() as conn, conn.transaction():
            uid = create_account(conn, email, body.password)
        return {'token': auth.make_token(uid, secret, clock()), 'uid': uid}

    @app.post('/auth/staff')
    def create_staff(body: RegisterIn, uid: str = Depends(current_uid)):
        """Bosh admin xodim akkaunti ochadi: akkaunt + profil (rol 'user'); rolni keyin bosh admin qo'yadi."""
        with db.as_user(uid) as conn:
            if not conn.execute('select app.is_owner() as ok').fetchone()['ok']:
                raise HTTPException(403, 'faqat bosh admin')
        email = auth.phone_email(body.phone)
        if not email:
            raise HTTPException(400, "telefon raqam noto'g'ri")
        check_new_password(body.password)
        with db.service() as conn, conn.transaction():
            new = create_account(conn, email, body.password)
            # profilni yangi xodimning O'ZI nomidan yozamiz — qoida (RLS) bilan bir xil yo'l
            conn.execute('set local role app_user')
            conn.execute("select set_config('app.uid', %s, true)", (new,))
            conn.execute("insert into users (id, name, email, phone, role) values (%s, %s, '', %s, 'user')",
                         (new, body.name.strip(), email.split('@')[0]))
        return {'uid': new}

    def own_email(conn, uid):
        with conn.cursor(row_factory=tuple_row) as cur:
            row = cur.execute('select email from kirish.accounts where id = %s and not disabled', (uid,)).fetchone()
        if not row:
            raise HTTPException(404, 'akkaunt topilmadi')
        return row[0]

    def confirm_password(conn, uid, password):
        if not limiter.allow(f'pw:{uid}', clock()):
            raise too_many()
        # 401 emas: ilova 401 ni "kirish muddati tugadi" deb tushunib chiqarib yuboradi
        if parol.login(conn, own_email(conn, uid), password, check) != uid:
            raise HTTPException(403, "parol noto'g'ri")

    @app.post('/auth/password')
    def change_password(body: PasswordIn, uid: str = Depends(current_uid)):
        """Parolni almashtirish — hozirgi parol bilan tasdiqlanadi."""
        check_new_password(body.next)
        with db.service() as conn:
            confirm_password(conn, uid, body.current)
            conn.execute("update kirish.accounts set password_algo = 'scrypt', password_hash = %s where id = %s",
                         (parol.hash_password(body.next), uid))
        return {'ok': True}

    @app.post('/auth/delete')
    def delete_login(body: PasswordIn, uid: str = Depends(current_uid)):
        """O'z kirish akkauntini o'chirish (Firebase user.delete kabi) — parol bilan tasdiqlanadi."""
        with db.service() as conn:
            confirm_password(conn, uid, body.current)
            conn.execute('delete from kirish.accounts where id = %s', (uid,))
        return {'ok': True}

    @app.get('/me')
    def me(uid: str = Depends(current_uid)):
        with db.as_user(uid) as conn:
            row = conn.execute('select * from users where id = %s', (uid,)).fetchone()
        if row is None:
            raise HTTPException(404, 'profil topilmadi')
        return row

    # ---------- hujjatlar (Firestore'ga o'xshash) ----------

    def run(uid, fn):
        """Hujjat amali foydalanuvchi nomidan, bitta tranzaksiyada; baza xatosi -> 400/403."""
        try:
            with db.as_user(uid) as conn:
                return fn(store.Store(conn))
        except psycopg.Error as e:
            err = store.db_error(e)
            if err:
                raise err from e
            raise

    def parse_q(q):
        try:
            return json.loads(q) if q else {}
        except ValueError as e:
            raise HTTPException(400, "so'rov noto'g'ri") from e

    @app.get('/doc/{path:path}')
    def get_doc(path: str, uid: str = Depends(current_uid)):
        ref = store.Ref(path)
        return {'doc': run(uid, lambda s: s.get(ref))}

    @app.put('/doc/{path:path}')
    def set_doc(path: str, body: DocIn, uid: str = Depends(current_uid)):
        ref = store.Ref(path)
        run(uid, lambda s: s.set(ref, body.data, merge=body.merge))
        return {'ok': True}

    @app.patch('/doc/{path:path}')
    def update_doc(path: str, body: DocIn, uid: str = Depends(current_uid)):
        ref = store.Ref(path)
        run(uid, lambda s: s.update(ref, body.data))
        return {'ok': True}

    @app.delete('/doc/{path:path}')
    def delete_doc(path: str, uid: str = Depends(current_uid)):
        ref = store.Ref(path)
        run(uid, lambda s: s.delete(ref))
        return {'ok': True}

    @app.get('/col/{path:path}')
    def query_col(path: str, q: str = '', uid: str = Depends(current_uid)):
        ref, query = store.Ref(path), parse_q(q)
        if ref.is_doc:
            raise HTTPException(400, "to'plam yo'li kerak")
        return {'docs': run(uid, lambda s: s.query(ref, query))}

    @app.post('/col/{path:path}')
    def add_doc(path: str, body: DocIn, uid: str = Depends(current_uid)):
        ref = store.Ref(path)
        return {'id': run(uid, lambda s: s.add(ref, body.data))}

    @app.get('/group/{name}')
    def query_group(name: str, q: str = '', uid: str = Depends(current_uid)):
        if name not in store.GROUPS:
            raise HTTPException(400, "noma'lum to'plam guruhi")
        _, top, _, _ = store.GROUPS[name]
        ref = store.Ref(f'{top}/_/{name}')
        ref.parent = None  # hamma ota hujjatlar bo'yicha
        query = parse_q(q)
        return {'docs': run(uid, lambda s: s.query(ref, query, group=True))}

    @app.post('/batch')
    def batch(body: BatchIn, uid: str = Depends(current_uid)):
        """Bir nechta yozuv bitta tranzaksiyada (Firestore writeBatch / transaction)."""
        if len(body.ops) > 500:
            raise HTTPException(400, "juda ko'p amal")

        def apply(s):
            ids = []
            for op in body.ops:
                ref = store.Ref(op.path)
                new_id = None
                if op.op == 'set':
                    s.set(ref, op.data, merge=op.merge)
                elif op.op == 'update':
                    s.update(ref, op.data)
                elif op.op == 'delete':
                    s.delete(ref)
                elif op.op == 'add':
                    new_id = s.add(ref, op.data)
                else:
                    raise HTTPException(400, f"noma'lum amal: {op.op}")
                ids.append(new_id)
            return ids

        return {'ids': run(uid, apply)}

    @app.websocket('/ws')
    async def ws(websocket: WebSocket, token: str = ''):
        """Jonli yangilanish: o'zgargan to'plam nomi keladi ({"c": "messages"}), ilova qayta so'raydi.
        Token so'rov qatorida — brauzer WebSocket'iga sarlavha qo'yib bo'lmaydi."""
        uid = auth.read_token(token, secret)
        if not uid or not await run_in_threadpool(active, uid):
            await websocket.close(code=4401)
            return
        await websocket.accept()
        hub.clients.add(websocket)
        try:
            while True:
                await websocket.receive_text()  # ilova vaqti-vaqti bilan "ping" yuboradi
        except WebSocketDisconnect:
            pass
        finally:
            hub.clients.discard(websocket)

    app.state.db = db
    return app


# uvicorn uchun; JWT_SECRET sozlanmagan bo'lsa (masalan testlarda) — yaratilmaydi
app = create_app() if env('JWT_SECRET', '') else None
