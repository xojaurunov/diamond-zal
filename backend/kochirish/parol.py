"""Parollar: o'z xeshimiz va Firebase'dan sezdirmasdan o'tish.

Akkaunt `firebase` bo'lsa (hali ko'chmagan), birinchi kirishda parol bir marta Firebase'da tekshiriladi;
to'g'ri bo'lsa, bizning xesh saqlanadi va keyin Firebase chaqirilmaydi.
"""

import base64
import hashlib
import hmac
import json
import re
import secrets
import urllib.error
import urllib.request
from pathlib import Path

N, R, P = 2 ** 14, 8, 1
REPO = Path(__file__).resolve().parents[2]


def hash_password(password):
    salt = secrets.token_bytes(16)
    h = hashlib.scrypt(password.encode(), salt=salt, n=N, r=R, p=P, dklen=32)
    b64 = lambda b: base64.b64encode(b).decode()  # noqa: E731
    return f'scrypt${N}${R}${P}${b64(salt)}${b64(h)}'


def verify(password, stored):
    try:
        _, n, r, p, salt, h = stored.split('$')
        got = hashlib.scrypt(password.encode(), salt=base64.b64decode(salt), n=int(n), r=int(r), p=int(p),
                             dklen=len(base64.b64decode(h)))
    except (ValueError, AttributeError):
        return False
    return hmac.compare_digest(got, base64.b64decode(h))


def firebase_check(email, password):
    """Parol Firebase Auth'da to'g'rimi (signInWithPassword). Tarmoq xatosi — istisno."""
    options = (REPO / 'lib' / 'firebase_options.dart').read_text(encoding='utf-8')
    api_key = re.search(r"apiKey: '([^']+)'", options).group(1)
    req = urllib.request.Request(
        f'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key={api_key}',
        json.dumps({'email': email, 'password': password, 'returnSecureToken': False}).encode(),
        {'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return bool(json.load(r).get('localId'))
    except urllib.error.HTTPError as e:
        if e.code == 400:  # noto'g'ri parol / akkaunt yo'q / bloklangan
            return False
        raise


def login(conn, email, password, check=firebase_check):
    """Kirish: to'g'ri bo'lsa — uid, aks holda None. `conn` — kirish sxemasiga ruxsati bor ulanish."""
    row = conn.execute(
        'select id, password_algo, password_hash from kirish.accounts where email = %s and not disabled',
        (email,)).fetchone()
    if row is None:
        return None
    uid, algo, stored = row
    if algo == 'scrypt':
        ok = verify(password, stored)
    else:
        ok = check(email, password)
        if ok:
            conn.execute("update kirish.accounts set password_algo = 'scrypt', password_hash = %s where id = %s",
                         (hash_password(password), uid))
    if not ok:
        return None
    conn.execute('update kirish.accounts set last_sign_in = now() where id = %s', (uid,))
    return uid
