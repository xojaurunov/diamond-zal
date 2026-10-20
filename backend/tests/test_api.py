"""Servis yadrosi (app/) testlari — soxta foydalanuvchilar, alohida `qobil_api_test` bazasi."""

import sys
import time
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app import auth  # noqa: E402
from app.db import Db, conninfo  # noqa: E402
from app.main import create_app  # noqa: E402
from kochirish import importer, parol  # noqa: E402

DB = 'qobil_api_test'
SECRET = 'test-kaliti-faqat-sinov-uchun-' + 'x' * 20
P = 'projects/x/databases/(default)/documents/'


def doc(path, **fields):
    return {'name': P + path, 'fields': {k: {'stringValue': v} for k, v in fields.items()}}


def email(n):
    return f'99890000000{n}@phone.kottaqani.uz'


USERS = [
    doc('users/o1', name='Egasi', role='owner'),
    doc('users/t1', name='Trener', role='admin'),
    doc('users/s1', name='Shogird', role='user', trainerId='t1'),
    doc('users/s2', name='Begona', role='user', trainerId='t2'),
]
AUTH = {'users': [
    {'localId': 'o1', 'email': email(1)},
    {'localId': 't1', 'email': email(2)},
    {'localId': 's1', 'email': email(3)},
    {'localId': 's2', 'email': email(4)},
]}


@pytest.fixture
def client():
    export = {'collections': {name: [] for name in importer.TABLES}}
    export['collections']['users'] = USERS
    assert importer.run(export, dbname=DB, out=lambda _: None, auth_export=AUTH)
    conn = importer.connect(DB)
    # s1 va t1 — allaqachon o'z xeshimizda; o1, s2 — hali Firebase'da (birinchi kirish)
    for uid in ('s1', 't1'):
        conn.execute("update kirish.accounts set password_algo = 'scrypt', password_hash = %s where id = %s",
                     (parol.hash_password('sir123'), uid))
    conn.close()
    firebase_calls = []

    def fake_firebase(mail, password):
        firebase_calls.append(mail)
        return password == 'eski-parol'

    app = create_app(db=Db(conninfo(DB)), secret=SECRET, firebase_check=fake_firebase)
    with TestClient(app) as c:
        c.firebase_calls = firebase_calls
        c.db = app.state.db
        yield c


def login(c, phone, password):
    return c.post('/auth/login', json={'phone': phone, 'password': password})


def bearer(token):
    return {'Authorization': f'Bearer {token}'}


def test_health(client):
    assert client.get('/health').json() == {'ok': True}


def test_togri_parol_token_va_ozi(client):
    r = login(client, '900000003', 'sir123')
    assert r.status_code == 200, r.text
    me = client.get('/me', headers=bearer(r.json()['token']))
    assert me.status_code == 200
    assert me.json()['id'] == 's1' and me.json()['name'] == 'Shogird'
    assert client.firebase_calls == [], 'ko\'chgan akkaunt Firebase\'ni chaqirmaydi'


def test_telefon_har_xil_yozilishi(client):
    for phone in ('900000003', '998900000003', '+998 90 000 00 03'):
        assert login(client, phone, 'sir123').status_code == 200, phone


def test_notogri_parol_va_notanish_raqam_bir_xil_javob(client):
    a = login(client, '900000003', 'xato-parol')
    b = login(client, '900000099', 'sir123')
    c = login(client, '12345', 'sir123')
    assert a.status_code == b.status_code == c.status_code == 401
    assert a.json() == b.json() == c.json(), 'qaysi biri noto\'g\'riligi aytilmaydi'


def test_kop_urinish_429(client):
    for _ in range(5):
        assert login(client, '900000003', 'xato').status_code == 401
    assert login(client, '900000003', 'sir123').status_code == 429, 'to\'g\'ri parol ham kutadi'


def test_firebase_akkaunt_birinchi_kirishda_kochadi(client):
    assert login(client, '900000001', 'eski-parol').status_code == 200
    assert client.firebase_calls == [email(1)]
    conn = importer.connect(DB)
    try:
        algo = conn.execute("select password_algo from kirish.accounts where id = 'o1'").fetchone()[0]
    finally:
        conn.close()
    assert algo == 'scrypt'
    client.firebase_calls.clear()
    assert login(client, '900000001', 'eski-parol').status_code == 200
    assert client.firebase_calls == [], 'ikkinchi kirish Firebase\'siz'


def test_tokensiz_soxta_va_muddati_otgan_token_401(client):
    assert client.get('/me').status_code == 401
    assert client.get('/me', headers=bearer('buzuq.token.xx')).status_code == 401
    other = auth.make_token('s1', 'boshqa-kalit-' + 'y' * 30)
    assert client.get('/me', headers=bearer(other)).status_code == 401
    old = auth.make_token('s1', SECRET, now=time.time() - (auth.TOKEN_DAYS + 1) * 86400)
    assert client.get('/me', headers=bearer(old)).status_code == 401
    good = auth.make_token('s1', SECRET)
    assert client.get('/me', headers=bearer(good)).status_code == 200


def test_servis_bazaga_foydalanuvchi_nomidan_boradi(client):
    """Ruxsatlarni baza tekshiradi: trener faqat o'zini va o'z shogirdini ko'radi, begonani — yo'q."""
    with client.db.as_user('t1') as conn:
        seen = sorted(r['id'] for r in conn.execute('select id from users').fetchall())
    assert seen == ['s1', 't1']
    with client.db.as_user('s2') as conn:
        seen = [r['id'] for r in conn.execute('select id from users').fetchall()]
    assert seen == ['s2']
    with client.db.as_user('t1') as conn:
        with pytest.raises(Exception):
            conn.execute('select * from kirish.accounts')


def test_ruxsatsiz_ozgartirish_403(client):
    from fastapi import HTTPException
    with pytest.raises(HTTPException) as e:
        with client.db.as_user('s1') as conn:
            conn.execute("update users set role = 'owner' where id = 's1'")
    assert e.value.status_code == 403
