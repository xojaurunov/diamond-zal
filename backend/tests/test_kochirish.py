"""Ko'chirish (kochirish/importer.py) testlari — soxta ma'lumot bilan, jonli Firebase'siz."""

import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from kochirish import importer  # noqa: E402

P = 'projects/x/databases/(default)/documents/'


def doc(path, **fields):
    return {'name': P + path, 'fields': fields}


def s(x): return {'stringValue': x}
def i(x): return {'integerValue': str(x)}
def arr(*xs): return {'arrayValue': {'values': list(xs)}}
def m(**xs): return {'mapValue': {'fields': xs}}


def test_firestore_turlari():
    assert importer.value({'nullValue': None}) is None
    assert importer.value(i(42)) == 42
    assert importer.value({'doubleValue': 1.5}) == 1.5
    assert importer.value({'booleanValue': False}) is False
    assert importer.value({'timestampValue': '2026-10-19T08:30:00.123Z'}) == \
        datetime(2026, 10, 19, 8, 30, 0, 123000, tzinfo=timezone.utc)
    assert importer.value({'bytesValue': 'AAE='}) == b'\x00\x01'
    assert importer.value(arr(i(1), s('a'))) == [1, 'a']
    assert importer.value({'arrayValue': {}}) == []
    assert importer.value(m(chest=arr(s('Otjimaniya')))) == {'chest': ['Otjimaniya']}


def test_nomlar_snake_case():
    assert importer.snake('trainerId') == 'trainer_id'
    assert importer.snake('subscriptionExpiresAt') == 'subscription_expires_at'
    assert importer.snake('name') == 'name'


def test_hujjat_yoli_kalitga():
    assert importer.to_row('users', doc('users/u1', trainerId=s('t1'))) == \
        ('users', {'trainer_id': 't1', 'id': 'u1'})
    assert importer.to_row('days', doc('users/u1/days/2026-10-19', water=i(3))) == \
        ('user_days', {'water': 3, 'day': '2026-10-19', 'user_id': 'u1'})
    assert importer.to_row('messages', doc('chats/u1/messages/abc', text=s('salom'))) == \
        ('chat_messages', {'text': 'salom', 'id': 'abc', 'chat_user_id': 'u1'})
    assert importer.to_row('ratings', doc('ratings/t1', stars=i(5)))[1]['trainer_id'] == 't1'


def _export(**cols):
    base = {name: [] for name in importer.TABLES}
    return {'collections': {**base, **cols}}


def test_soxta_eksport_toliq_yoziladi_va_qayta_yuklash_bir_xil():
    export = _export(
        users=[doc('users/u1', name=s('Soxta'), role=s('user'), trainerId=s('t9'), gymDays=arr(i(1), i(3), i(5)),
                   program=m(chest=arr(s('Otjimaniya'))), lastWeighIn={'timestampValue': '2026-10-01T00:00:00Z'})],
        plans=[doc('plans/p1', title=s('Reja'), meals=arr(m(time=s('07:00'), items=arr())),
                   week=m(**{'1': arr()}), forbidden=arr(s('shakar')))],
        days=[doc('users/u1/days/2026-10-19', done=arr(i(0)), extras=arr(m(name=s('Olma'), at=i(1))))],
        photos=[doc('users/u1/photos/r1', data={'bytesValue': 'AAE='}, weight={'doubleValue': 80.5})],
        messages=[doc('chats/u1/messages/x1', senderId=s('u1'), text=s('salom'))],
    )
    lines = []
    for _ in range(2):
        lines.clear()
        assert importer.run(export, dbname='qobil_kochirish_test', out=lines.append)
    assert any("users.trainer_id -> users: 1" in ln for ln in lines), lines
    conn = importer.connect('qobil_kochirish_test')
    try:
        assert conn.execute('select count(*) from users').fetchone()[0] == 1
        u = conn.execute('select gym_days, program from users').fetchone()
        assert u == ([1, 3, 5], {'chest': ['Otjimaniya']})
        assert conn.execute('select data from photos').fetchone()[0] == b'\x00\x01'
    finally:
        conn.close()


def test_ustuni_yoq_maydon_bolsa_hech_narsa_yozilmaydi():
    export = _export(users=[doc('users/u1', name=s('Soxta'), yangiMaydon=s('x'))])
    lines = []
    assert not importer.run(export, dbname='qobil_kochirish_test', out=lines.append)
    assert any('users.yangi_maydon: 1' in ln for ln in lines), lines
    conn = importer.connect('qobil_kochirish_test')
    try:
        assert conn.execute('select count(*) from users').fetchone()[0] == 0
    finally:
        conn.close()


# ---------- akkauntlar va parollar (02b) ----------
import psycopg  # noqa: E402
import pytest  # noqa: E402

from kochirish import parol  # noqa: E402

FAKE_AUTH = {'users': [
    {'localId': 'u1', 'email': '998900000001@phone.kottaqani.uz', 'createdAt': '1760000000000',
     'passwordHash': 'xesh-saqlanmaydi', 'salt': 'tuz'},
    {'localId': 'u2', 'email': '998900000002@phone.kottaqani.uz', 'disabled': True},
]}


def test_xesh_togri_va_notogri_parol():
    h = parol.hash_password('sir123')
    assert h.startswith('scrypt$') and 'sir123' not in h
    assert parol.verify('sir123', h)
    assert not parol.verify('sir124', h)
    assert not parol.verify('sir123', 'buzuq')
    assert parol.hash_password('sir123') != h  # har safar yangi tuz


def test_akkauntlar_eksportdan_firebase_xeshisiz():
    rows = importer.account_rows(FAKE_AUTH)
    assert [r['id'] for r in rows] == ['u1', 'u2']
    assert rows[0]['phone'] == '998900000001' and rows[0]['password_algo'] == 'firebase'
    assert rows[1]['disabled'] is True
    assert all('xesh-saqlanmaydi' not in str(r) and 'tuz' not in str(r.values()) for r in rows)


@pytest.fixture
def accounts_db():
    export = _export(users=[doc('users/u1', name=s('Soxta'))])
    assert importer.run(export, dbname='qobil_kochirish_test', out=lambda _: None, auth_export=FAKE_AUTH)
    conn = importer.connect('qobil_kochirish_test')
    yield conn
    conn.close()


def test_birinchi_kirish_firebase_orqali_keyin_mahalliy(accounts_db):
    calls = []

    def fake_firebase(email, password):
        calls.append(email)
        return password == 'eski-parol'

    email = '998900000001@phone.kottaqani.uz'
    assert parol.login(accounts_db, email, 'xato', fake_firebase) is None
    assert parol.login(accounts_db, email, 'eski-parol', fake_firebase) == 'u1'
    assert accounts_db.execute("select password_algo from kirish.accounts where id = 'u1'").fetchone()[0] == 'scrypt'
    calls.clear()

    def no_firebase(*_):
        raise AssertionError('Firebase chaqirilmasligi kerak')

    assert parol.login(accounts_db, email, 'eski-parol', no_firebase) == 'u1'
    assert parol.login(accounts_db, email, 'xato', no_firebase) is None


def test_bloklangan_va_yoq_akkaunt_kira_olmaydi(accounts_db):
    always = lambda *_: True  # noqa: E731
    assert parol.login(accounts_db, '998900000002@phone.kottaqani.uz', 'x', always) is None
    assert parol.login(accounts_db, 'yoq@phone.kottaqani.uz', 'x', always) is None


def test_hisobot_hujjatsiz_akkauntni_sanaydi():
    lines = []
    importer.run(_export(users=[doc('users/u1', name=s('Soxta'))]), dbname='qobil_kochirish_test',
                 out=lines.append, auth_export=FAKE_AUTH)
    assert 'akkauntlar: Firebase 2, Postgres 2; hujjatsiz akkaunt 1, akkauntsiz hujjat 0' in lines


def test_ilova_akkauntlarni_oqiy_olmaydi(pg):
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        with pg.conn.transaction():
            pg.conn.execute('set local role app_user')
            pg.conn.execute("select set_config('app.uid', 'owner1', true)")
            pg.conn.execute('select * from kirish.accounts')
