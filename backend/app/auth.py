"""Kirish: telefon + parol -> token (HS256, 30 kun). Parol `kochirish/parol.py` bilan tekshiriladi:
hali ko'chmagan akkaunt birinchi kirishda Firebase orqali, keyin o'z xeshimiz bilan."""

import re
import time
from collections import defaultdict, deque

import jwt

TOKEN_DAYS = 30
ISSUER = 'qobil'
LOGIN_LIMIT = 5  # daqiqasiga, bitta telefon yoki IP uchun
EMAIL_DOMAIN = 'phone.kottaqani.uz'


def phone_email(phone):
    """'90 123 45 67' / '+998901234567' -> '998901234567@phone.kottaqani.uz'; noto'g'ri — None."""
    digits = re.sub(r'\D', '', phone or '')
    if len(digits) == 9:
        digits = '998' + digits
    if not re.fullmatch(r'998\d{9}', digits):
        return None
    return f'{digits}@{EMAIL_DOMAIN}'


def make_token(uid, secret, now=None):
    now = int(now if now is not None else time.time())
    return jwt.encode({'sub': uid, 'iss': ISSUER, 'iat': now, 'exp': now + TOKEN_DAYS * 86400}, secret, 'HS256')


def read_token(token, secret):
    """To'g'ri va muddati o'tmagan token — uid, aks holda None."""
    try:
        claims = jwt.decode(token, secret, algorithms=['HS256'], issuer=ISSUER,
                            options={'require': ['sub', 'exp', 'iat', 'iss']})
    except jwt.PyJWTError:
        return None
    return claims['sub']


class RateLimit:
    """Oddiy xotiradagi cheklov: kalit bo'yicha oxirgi 60 soniyadagi urinishlar."""

    def __init__(self, limit=LOGIN_LIMIT, window=60.0):
        self.limit, self.window = limit, window
        self.hits = defaultdict(deque)

    def allow(self, key, now):
        q = self.hits[key]
        while q and q[0] <= now - self.window:
            q.popleft()
        if len(q) >= self.limit:
            return False
        q.append(now)
        return True
