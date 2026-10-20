"""Hujjat API (app/store.py, /doc /col /group /batch) va akkaunt amallari — soxta ma'lumot bilan."""

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.db import Db, conninfo  # noqa: E402
from app.main import create_app  # noqa: E402
from kochirish import importer, parol  # noqa: E402

DB = 'qobil_store_test'
SECRET = 'store-test-kaliti-' + 'z' * 30
P = 'projects/x/databases/(default)/documents/'
NOW = {'$op': 'serverTimestamp'}


def doc(path, **fields):
    return {'name': P + path, 'fields': {k: {'stringValue': v} for k, v in fields.items()}}


def email(n):
    return f'99890000000{n}@phone.kottaqani.uz'


@pytest.fixture
def api():
    export = {'collections': {name: [] for name in importer.TABLES}}
    export['collections']['users'] = [
        doc('users/o1', name='Egasi', role='owner'),
        doc('users/t1', name='Trener', role='admin', gymId='g1'),
        doc('users/s1', name='Shogird', role='user', trainerId='t1'),
        doc('users/s2', name='Begona', role='user', trainerId='t2'),
    ]
    export['collections']['subscriptions'] = [
        {'name': P + 'users/s2/subscriptions/x1', 'fields': {'months': {'integerValue': '1'}}}]
    auth = {'users': [{'localId': u, 'email': email(i)} for i, u in enumerate(['o1', 't1', 's1', 's2'], 1)]}
    assert importer.run(export, dbname=DB, out=lambda _: None, auth_export=auth)
    conn = importer.connect(DB)
    conn.execute("update kirish.accounts set password_algo = 'scrypt', password_hash = %s",
                 (parol.hash_password('sir123'),))
    conn.close()
    app = create_app(db=Db(conninfo(DB)), secret=SECRET, firebase_check=lambda *_: False)
    with TestClient(app) as c:
        def as_(n):
            r = c.post('/auth/login', json={'phone': f'90000000{n}', 'password': 'sir123'})
            assert r.status_code == 200, r.text
            return {'Authorization': f"Bearer {r.json()['token']}"}
        c.as_ = as_
        yield c


def q(**kw):
    return {'q': json.dumps(kw)}


def test_ozi_hujjati_camelcase_idsiz(api):
    r = api.get('/doc/users/s1', headers=api.as_(3))
    d = r.json()['doc']
    assert d['id'] == 's1' and d['path'] == 'users/s1'
    assert d['data']['trainerId'] == 't1' and d['data']['role'] == 'user'
    assert 'id' not in d['data'] and 'trainer_id' not in d['data']


def test_begona_hujjat_yoq_deb_qaytadi(api):
    r = api.get('/doc/users/s2', headers=api.as_(3))
    assert r.status_code == 200 and r.json()['doc'] is None


def test_trener_oz_shogirdlari_sorovi(api):
    r = api.get('/col/users', params=q(where=[['trainerId', '==', 't1']]), headers=api.as_(2))
    assert [d['id'] for d in r.json()['docs']] == ['s1']
    r = api.get('/col/users', params=q(where=[['role', 'in', ['user', 'admin']]]), headers=api.as_(2))
    assert sorted(d['id'] for d in r.json()['docs']) == ['s1', 't1'], 'begona shogird ko\'rinmaydi'


def test_merge_arrayunion_arrayremove(api):
    h, path = api.as_(3), '/doc/users/s1/days/2026-10-20'
    au = lambda *v: {'$op': 'arrayUnion', 'values': list(v)}  # noqa: E731
    ar = lambda *v: {'$op': 'arrayRemove', 'values': list(v)}  # noqa: E731
    assert api.put(path, json={'data': {'done': au(0)}, 'merge': True}, headers=h).status_code == 200
    api.put(path, json={'data': {'done': au(2, 0), 'water': 3}, 'merge': True}, headers=h)
    api.put(path, json={'data': {'done': ar(0)}, 'merge': True}, headers=h)
    meal = {'name': 'Olma', 'grams': 100, 'at': 5}
    api.put(path, json={'data': {'extras': au(meal)}, 'merge': True}, headers=h)
    api.put(path, json={'data': {'extras': au(meal)}, 'merge': True}, headers=h)
    d = api.get(path, headers=h).json()['doc']['data']
    assert d['done'] == [2] and d['water'] == 3 and d['extras'] == [meal]
    api.put(path, json={'data': {'extras': ar(meal)}, 'merge': True}, headers=h)
    assert api.get(path, headers=h).json()['doc']['data']['extras'] == []


def test_shogird_rolini_ozgartira_olmaydi_403(api):
    r = api.patch('/doc/users/s1', json={'data': {'role': 'owner'}}, headers=api.as_(3))
    assert r.status_code == 403
    r = api.patch('/doc/users/s1', json={'data': {'goal': 'lose'}}, headers=api.as_(3))
    assert r.status_code == 200


def test_vazn_batch_profil_bilan_tartibdan_qatiy_nazar(api):
    h = api.as_(3)
    ops = lambda w, i: [  # noqa: E731
        {'op': 'set', 'path': f'users/s1/weights/w{i}', 'data': {'date': NOW, 'weight': w}},
        {'op': 'update', 'path': 'users/s1', 'data': {'weight': w, 'lastWeighIn': NOW}},
    ]
    assert api.post('/batch', json={'ops': ops(70, 1)}, headers=h).status_code == 200
    assert api.post('/batch', json={'ops': ops(69, 2)}, headers=h).status_code == 403, 'haftada 1 marta'
    lone = api.put('/doc/users/s1/weights/w3', json={'data': {'date': NOW, 'weight': 60}}, headers=h)
    assert lone.status_code == 403, 'profilsiz yolg\'iz o\'lchov'
    docs = api.get('/col/users/s1/weights', params=q(orderBy=[['date', 'asc']]), headers=h).json()['docs']
    assert [d['data']['weight'] for d in docs] == [70]
    assert set(docs[0]['data']['date']) == {'$t'}


def test_nuqtali_maydon_va_ochirish(api):
    h = api.as_(2)
    api.patch('/doc/users/s1', json={'data': {'program.chest': ['A', 'B']}}, headers=h)
    api.patch('/doc/users/s1', json={'data': {'program.back': ['C']}}, headers=h)
    api.patch('/doc/users/s1', json={'data': {'program.chest': {'$op': 'delete'}}}, headers=h)
    d = api.get('/doc/users/s1', headers=h).json()['doc']['data']
    assert d['program'] == {'back': ['C']}


def test_chat_add_va_saralash(api):
    h = api.as_(3)
    for t in ('salom', 'ikkinchi'):
        r = api.post('/col/chats/s1/messages', json={'data': {'senderId': 's1', 'text': t, 'createdAt': NOW}},
                     headers=h)
        assert r.status_code == 200 and len(r.json()['id']) == 20
    docs = api.get('/col/chats/s1/messages', params=q(orderBy=[['createdAt', 'desc']], limit=1),
                   headers=h).json()['docs']
    assert len(docs) == 1 and docs[0]['path'].startswith('chats/s1/messages/')
    fake = api.post('/col/chats/s1/messages', json={'data': {'senderId': 't1', 'text': 'soxta'}}, headers=h)
    assert fake.status_code == 403


def test_toplam_guruhi_faqat_ruxsat_etilgani(api):
    h = api.as_(2)
    api.post('/col/users/s1/subscriptions', json={'data': {
        'startDate': {'$t': '2026-10-01T00:00:00Z'}, 'months': 1, 'price': 500000, 'currency': 'UZS',
        'createdAt': NOW}}, headers=h)
    mine = api.get('/group/subscriptions', headers=h).json()['docs']
    assert [d['path'].split('/')[1] for d in mine] == ['s1'], 'trener begona abonementni ko\'rmaydi'
    assert mine[0]['data']['startDate'] == {'$t': '2026-10-01T00:00:00Z'}
    every = api.get('/group/subscriptions', headers=api.as_(1)).json()['docs']
    assert sorted(d['path'].split('/')[1] for d in every) == ['s1', 's2']


def test_notogri_yol_va_maydon_400(api):
    h = api.as_(3)
    assert api.get('/doc/parollar/x', headers=h).status_code == 400
    assert api.get('/doc/users/s1/sirlar/x', headers=h).status_code == 400
    assert api.patch('/doc/users/s1', json={'data': {'yangiMaydon': 1}}, headers=h).status_code == 400
    assert api.patch('/doc/users/s1', json={'data': {'id': 'x'}}, headers=h).status_code == 400
    assert api.get('/col/users', params={'q': 'buzuq'}, headers=h).status_code == 400
    assert api.get('/doc/users/s1').status_code == 401


def test_royxatdan_otish_va_takror_raqam(api):
    r = api.post('/auth/register', json={'phone': '901112233', 'password': 'yangi123'})
    assert r.status_code == 200
    uid, h = r.json()['uid'], {'Authorization': f"Bearer {r.json()['token']}"}
    assert len(uid) == 28
    ok = api.put(f'/doc/users/{uid}', json={'data': {'name': 'Yangi', 'phone': '998901112233', 'role': 'user'}},
                 headers=h)
    assert ok.status_code == 200
    bad = api.put(f'/doc/users/{uid}', json={'data': {'name': 'X', 'role': 'owner'}}, headers=h)
    assert bad.status_code == 403
    assert api.post('/auth/register', json={'phone': '901112233', 'password': 'boshqa12'}).status_code == 409
    assert api.post('/auth/register', json={'phone': '901112234', 'password': '123'}).status_code == 400


def test_xodimni_faqat_bosh_admin_ochadi(api):
    body = {'phone': '905556677', 'password': 'trener1', 'name': 'Yangi trener'}
    assert api.post('/auth/staff', json=body, headers=api.as_(2)).status_code == 403
    r = api.post('/auth/staff', json=body, headers=api.as_(1))
    assert r.status_code == 200
    new = r.json()['uid']
    assert api.patch(f'/doc/users/{new}', json={'data': {'role': 'admin'}}, headers=api.as_(1)).status_code == 200
    login = api.post('/auth/login', json={'phone': '905556677', 'password': 'trener1'})
    assert login.status_code == 200 and login.json()['uid'] == new


def test_parol_almashtirish_va_ochirilgan_akkaunt_tokeni(api):
    h = api.as_(3)
    assert api.post('/auth/password', json={'current': 'xato', 'next': 'yangi123'}, headers=h).status_code == 403
    assert api.post('/auth/password', json={'current': 'sir123', 'next': 'yangi123'}, headers=h).status_code == 200
    assert api.post('/auth/login', json={'phone': '900000003', 'password': 'yangi123'}).status_code == 200
    assert api.post('/auth/delete', json={'current': 'yangi123'}, headers=h).status_code == 200
    assert api.get('/doc/users/s1', headers=h).status_code == 401, 'o\'chirilgan akkaunt tokeni ishlamaydi'


def test_vaqt_qiymati_aylanib_keladi(api):
    h = api.as_(2)
    when = datetime(2027, 1, 1, tzinfo=timezone.utc).isoformat().replace('+00:00', 'Z')
    api.patch('/doc/users/s1', json={'data': {'subscriptionExpiresAt': {'$t': when}}}, headers=h)
    assert api.get('/doc/users/s1', headers=h).json()['doc']['data']['subscriptionExpiresAt'] == {'$t': when}
