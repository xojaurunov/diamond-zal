"""Jonli yangilanish (/ws) — soxta ma'lumot bilan."""

import sys
import time
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app import auth  # noqa: E402
from app.db import Db, conninfo  # noqa: E402
from app.main import create_app  # noqa: E402
from kochirish import importer  # noqa: E402

DB = 'qobil_live_test'
SECRET = 'live-test-kaliti-' + 'q' * 30
P = 'projects/x/databases/(default)/documents/'


@pytest.fixture
def api():
    export = {'collections': {name: [] for name in importer.TABLES}}
    export['collections']['users'] = [
        {'name': P + 'users/t1', 'fields': {'role': {'stringValue': 'admin'}}},
        {'name': P + 'users/s1', 'fields': {'role': {'stringValue': 'user'}, 'trainerId': {'stringValue': 't1'}}},
    ]
    accounts = {'users': [{'localId': 't1', 'email': '998900000001@phone.kottaqani.uz'},
                          {'localId': 's1', 'email': '998900000002@phone.kottaqani.uz'}]}
    assert importer.run(export, dbname=DB, out=lambda _: None, auth_export=accounts)
    with TestClient(create_app(db=Db(conninfo(DB)), secret=SECRET)) as c:
        time.sleep(0.5)  # tinglovchi oqim ulanib olsin
        yield c


def test_tokensiz_va_soxta_token_yopiladi(api):
    for first in ({}, {'token': 'buzuq'}, {'token': auth.make_token('s1', 'boshqa-' + 'k' * 30)}, 'matn'):
        with pytest.raises(WebSocketDisconnect):
            with api.websocket_connect('/ws') as ws:
                ws.send_json(first)
                ws.receive_json()


def test_boshqasi_yozsa_toplam_nomi_keladi(api):
    trainer = auth.make_token('t1', SECRET)
    student = {'Authorization': f"Bearer {auth.make_token('s1', SECRET)}"}
    with api.websocket_connect('/ws') as ws:
        ws.send_json({'token': trainer})  # token manzilda emas — jurnalga tushmaydi
        r = api.post('/col/chats/s1/messages',
                     json={'data': {'senderId': 's1', 'text': 'salom', 'createdAt': {'$op': 'serverTimestamp'}}},
                     headers=student)
        assert r.status_code == 200
        assert ws.receive_json() == {'c': 'messages'}, 'signalda faqat to\'plam nomi'
        api.put('/doc/users/s1/days/2026-10-20', json={'data': {'water': 2}, 'merge': True}, headers=student)
        assert ws.receive_json() == {'c': 'days'}
