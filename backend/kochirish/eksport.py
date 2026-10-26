"""Firestore -> backend/data/eksport-<sana>.json (faqat O'QIYDI, Firebase'da hech narsa o'zgarmaydi).

Bosh admin akkaunti bilan kiradi (ildizdagi `.env`: OWNER_EMAIL, OWNER_PASS — tools/maxfiy.mjs bilan bir
xil) va hamma to'plamni sahifalab oxirigacha o'qiydi. Hujjatlar Firestore REST ko'rinishida (yo'li va
turlangan maydonlari bilan) saqlanadi; importer.py ularni Postgres'ga o'giradi.
Ekranga faqat sonlar chiqadi. `backend/data/` git'ga tushmaydi.

    python backend/kochirish/eksport.py
"""

import json
import re
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

PROJECT = 'kotta-qani-09111753'
REPO = Path(__file__).resolve().parents[2]
DATA = REPO / 'backend' / 'data'

TOP_LEVEL = ['users', 'trainers', 'ratings', 'gyms', 'foods', 'plans', 'exercises', 'shop', 'orders',
             'reminders', 'memberships', 'videos']
# users/{uid}/<nom> va chats/{uid}/messages
USER_SUB = ['days', 'weights', 'photos', 'subscriptions', 'attendance']


def secret(key):
    for line in (REPO / '.env').read_text(encoding='utf-8').splitlines():
        line = line.strip()
        if line.startswith(key + '='):
            return line.split('=', 1)[1].strip()
    sys.exit(f'.env da {key} yo\'q')


def post_json(url, body):
    req = urllib.request.Request(url, json.dumps(body).encode(), {'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def sign_in():
    options = (REPO / 'lib' / 'firebase_options.dart').read_text(encoding='utf-8')
    api_key = re.search(r"apiKey: '([^']+)'", options).group(1)
    res = post_json(
        f'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key={api_key}',
        {'email': secret('OWNER_EMAIL'), 'password': secret('OWNER_PASS'), 'returnSecureToken': True})
    return res['idToken']


class Firestore:
    def __init__(self, token):
        self.base = f'https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents'
        self.headers = {'Authorization': f'Bearer {token}'}
        self.reads = 0

    def list(self, path):
        """To'plamdagi hamma hujjat — sahifalab (`nextPageToken`) oxirigacha."""
        docs, token = [], None
        while True:
            q = {'pageSize': 300, **({'pageToken': token} if token else {})}
            url = f'{self.base}/{urllib.parse.quote(path)}?{urllib.parse.urlencode(q)}'
            with urllib.request.urlopen(urllib.request.Request(url, headers=self.headers), timeout=60) as r:
                page = json.load(r)
            docs += page.get('documents', [])
            self.reads += max(1, len(page.get('documents', [])))
            token = page.get('nextPageToken')
            if not token:
                return docs


def main():
    fs = Firestore(sign_in())
    out = {'exportedAt': datetime.now(timezone.utc).isoformat(), 'project': PROJECT, 'collections': {}}
    cols = out['collections']
    for name in TOP_LEVEL:
        cols[name] = fs.list(name)
    for name in USER_SUB + ['messages']:
        cols[name] = []
    for user in cols['users']:
        uid = user['name'].rsplit('/', 1)[1]
        for name in USER_SUB:
            cols[name] += fs.list(f'users/{uid}/{name}')
        cols['messages'] += fs.list(f'chats/{uid}/messages')

    DATA.mkdir(parents=True, exist_ok=True)
    path = DATA / f'eksport-{datetime.now():%Y-%m-%d}.json'
    path.write_text(json.dumps(out, ensure_ascii=False), encoding='utf-8')
    for name, docs in cols.items():
        print(f'  {name:14} {len(docs)}')
    print(f'Jami {sum(map(len, cols.values()))} hujjat, ~{fs.reads} o\'qish. Saqlandi: {path.relative_to(REPO)}')


if __name__ == '__main__':
    main()
