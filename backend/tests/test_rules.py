"""tools/rules_test/test.mjs ning nusxasi — Postgres'da.

Testlar o'sha tartibda va o'sha nomlar bilan; bazadagi holat testdan testga o'tadi (test.mjs dagidek).
Bitta testni alohida (`-k`) ishga tushirib bo'lmaydi — butun faylni ishga tushiring.
Ustun nomlari snake_case (Firestore'dagi trainerId -> trainer_id).
"""

from datetime import datetime, timedelta, timezone

import pytest

from conftest import NOW

OWNER = 'owner1'
TRAINER = 'trainer1'
TRAINER2 = 'trainer2'
TRAINER3 = 'trainer3'  # boshqa trener — USER unga tegishli emas
USER = 'user1'  # TRAINER ning shogirdi
USER2 = 'user2'
USER3 = 'user3'  # TRAINER3 ning shogirdi
USER4 = 'user4'  # hali trener tanlamagan
USER5 = 'user5'  # hali trener tanlamagan
TRAINER4 = 'trainer4'  # shogird qabul qiladigan ikkinchi trener
W1, W2, W3 = 'w1', 'w2', 'w3'
BARMEN = 'barmen1'
BARMEN2 = 'barmen2'  # boshqa zal barmeni

CHECKS = []
_setups = []


def check(name):
    def reg(fn):
        CHECKS.append((name, fn, list(_setups)))
        _setups.clear()
        return fn
    return reg


def setup(fn):
    """Qoidalarsiz tayyorlov (Firestore `withSecurityRulesDisabled`) — keyingi testdan oldin."""
    _setups.append(fn)
    return fn


def now():
    return datetime.now(timezone.utc)


def day(y, m, d):
    return datetime(y, m, d, tzinfo=timezone.utc)


@setup
def _seed(pg):
    a = pg.admin
    for uid, data in [
        (OWNER, {'name': 'Egasi', 'role': 'owner', 'phone': '998900000000'}),
        (TRAINER, {'name': 'Trener', 'role': 'admin', 'phone': '998901111111'}),
        (TRAINER2, {'name': 'Trener2', 'role': 'admin', 'phone': '998902222222'}),
        (TRAINER3, {'name': 'Trener3', 'role': 'admin', 'phone': '998908888888'}),
        (USER, {'name': 'Shogird', 'role': 'user', 'phone': '998903333333', 'trainer_id': TRAINER, 'weight': 80}),
        (USER2, {'name': 'Eski', 'role': 'user', 'phone': '998904444444'}),
        (USER3, {'name': 'Boshqaning shogirdi', 'role': 'user', 'phone': '998909999999', 'trainer_id': TRAINER3}),
        (USER4, {'name': 'Yangi shogird', 'role': 'user', 'phone': '998901010101'}),
        (USER5, {'name': 'Yana yangi', 'role': 'user', 'phone': '998902020202'}),
        (TRAINER4, {'name': 'Trener4', 'role': 'admin', 'phone': '998903030303'}),
        # vazn testlari: W1 — hali o'lchov yo'q, W2 — oxirgi o'lchov 8 kun oldin, W3 — anketa to'ldirmagan
        (W1, {'name': 'W1', 'role': 'user', 'weight': 72}),
        (W2, {'name': 'W2', 'role': 'user', 'weight': 90, 'last_weigh_in': now() - timedelta(days=8)}),
        (W3, {'name': 'W3', 'role': 'user', 'weight': 0}),
        (BARMEN, {'name': 'Barmen', 'role': 'barmen', 'phone': '998905050505'}),
    ]:
        a.set('users', data, id=uid)
    a.set('trainers', {'name': 'Trener', 'bio': '', 'accepting': True}, id=TRAINER)
    a.set('trainers', {'name': 'Trener3', 'bio': '', 'accepting': False}, id=TRAINER3)
    a.set('trainers', {'name': 'Trener4', 'bio': '', 'accepting': True}, id=TRAINER4)
    a.set('user_days', {'done': [0]}, user_id=USER, day='2026-09-15')
    a.set('plans', {'title': 'Reja', 'meals': []}, id='p1')
    a.set('foods', {'name': 'Tovuq', 'kcal': 165}, id='f1')


# == ROL OZGARTIRISH ==
@check('bosh admin foydalanuvchini trener qiladi')
def _(pg): pg.ok(OWNER).update('users', {'role': 'admin'}, id=USER2)
@check('bosh admin trenerni tushiradi')
def _(pg): pg.ok(OWNER).update('users', {'role': 'user'}, id=TRAINER2)
@check('TRENER rol ozgartira OLMAYDI')
def _(pg): pg.no(TRAINER).update('users', {'role': 'admin'}, id=USER)
@check('trener ozini bosh admin qila OLMAYDI')
def _(pg): pg.no(TRAINER).update('users', {'role': 'owner'}, id=TRAINER)
@check('shogird ozini trener qila OLMAYDI')
def _(pg): pg.no(USER).update('users', {'role': 'admin'}, id=USER)
@check('bosh admin boshqani BOSH ADMIN qiladi')
def _(pg): pg.ok(OWNER).update('users', {'role': 'owner'}, id=TRAINER)
@check('bosh admin boshqa bosh adminni trenerga tushiradi')
def _(pg): pg.ok(OWNER).update('users', {'role': 'admin'}, id=TRAINER)
@check('trener boshqani bosh admin qila OLMAYDI')
def _(pg): pg.no(TRAINER).update('users', {'role': 'owner'}, id=USER)


# == OCHIRISH ==
@check('bosh admin akkauntni ochiradi')
def _(pg): pg.ok(OWNER).delete('users', id=USER2)
@check('trener ochira OLMAYDI')
def _(pg): pg.no(TRAINER).delete('users', id=USER)
@check('shogird ozini ochira OLMAYDI')
def _(pg): pg.no(USER).delete('users', id=USER)


# == TRENER BIRIKTIRISH ==
@check('bosh admin trener biriktiradi')
def _(pg): pg.ok(OWNER).update('users', {'trainer_id': TRAINER3}, id=USER)
@check('bosh admin qaytarib biriktiradi')
def _(pg): pg.ok(OWNER).update('users', {'trainer_id': TRAINER}, id=USER)
@check('trener oz shogirdini boshqa trenerga bera OLMAYDI')
def _(pg): pg.no(TRAINER).update('users', {'trainer_id': TRAINER3}, id=USER)
@check('trener BOSHQANING shogirdini oziga ola OLMAYDI')
def _(pg): pg.no(TRAINER).update('users', {'trainer_id': TRAINER}, id=USER3)
@check('shogird oz trenerini ozgartira OLMAYDI')
def _(pg): pg.no(USER).update('users', {'trainer_id': TRAINER3}, id=USER)


# == SHOGIRD OZ MALUMOTI ==
@check('shogird vaznni olchovsiz (batchsiz) ozgartira OLMAYDI')
def _(pg): pg.no(USER).update('users', {'weight': 78}, id=USER)
@check('shogird oziga reja biriktira OLMAYDI')
def _(pg): pg.no(USER).update('users', {'plan_id': 'p1'}, id=USER)
@check('trener oz shogirdiga reja biriktiradi')
def _(pg): pg.ok(TRAINER).update('users', {'plan_id': 'p1', 'plan_assigned_at': now()}, id=USER)
@check('trener BOSHQANING shogirdiga reja bera OLMAYDI')
def _(pg): pg.no(TRAINER).update('users', {'plan_id': 'p1'}, id=USER3)
@check('shogird reja berilgan vaqtni ozgartira OLMAYDI')
def _(pg): pg.no(USER).update('users', {'plan_assigned_at': day(2020, 1, 1)}, id=USER)
@check('shogird oz maqsadi va metabolizmini tanlaydi')
def _(pg): pg.ok(USER).update('users', {'goal': 'gain', 'metabolism': 'fast'}, id=USER)
@check('trener oz shogirdi maqsadini belgilaydi')
def _(pg): pg.ok(TRAINER).update('users', {'goal': 'lose'}, id=USER)


# == OQISH ==
@check('shogird oz hujjatini oqiydi')
def _(pg): pg.ok(USER).get('users', id=USER)
@check('shogird BOSHQANI oqiy OLMAYDI')
def _(pg): pg.no(USER).get('users', id=TRAINER)
@check('trener oz shogirdini oqiydi')
def _(pg): pg.ok(TRAINER).get('users', id=USER)
@check('trener BOSHQANING shogirdini oqiy OLMAYDI')
def _(pg): pg.no(TRAINER).get('users', id=USER3)
@check('trener oz shogirdlari royxatini oladi')
def _(pg): pg.ok(TRAINER).list('users', trainer_id=TRAINER)
@check('trener HAMMA shogird royxatini ola OLMAYDI')
def _(pg): pg.no(TRAINER).list('users', role='user')
@check('trener xodimlar royxatini ola OLMAYDI (bosh admin korinmaydi)')
def _(pg): pg.no(TRAINER).list('users', role=['admin', 'owner'])
@check('trener bosh admin hujjatini oqiy OLMAYDI')
def _(pg): pg.no(TRAINER).get('users', id=OWNER)
@check('trener boshqa trener hujjatini oqiy OLMAYDI')
def _(pg): pg.no(TRAINER).get('users', id=TRAINER3)
@check('bosh admin hamma shogirdni oladi')
def _(pg): pg.ok(OWNER).list('users', role='user')
@check('bosh admin hammani oqiydi')
def _(pg): pg.ok(OWNER).get('users', id=USER3)
@check('kirmagan odam oqiy OLMAYDI')
def _(pg): pg.no(None).get('users', id=USER)
@check('trener oz shogirdi kunlarini oqiydi')
def _(pg): pg.ok(TRAINER).get('user_days', user_id=USER, day='2026-09-15')
@check('boshqa trener kunlarni oqiy OLMAYDI')
def _(pg): pg.no(TRAINER3).get('user_days', user_id=USER, day='2026-09-15')
@check('bosh admin kunlarni oqiydi (reyting)')
def _(pg): pg.ok(OWNER).get('user_days', user_id=USER, day='2026-09-15')


# == REJA VA MAHSULOT ==
@check('trener reja yozadi')
def _(pg): pg.ok(TRAINER).set('plans', {'title': 'Yangi', 'meals': []}, id='p2')
@check('bosh admin mahsulot yozadi')
def _(pg): pg.ok(OWNER).set('foods', {'name': 'Guruch', 'kcal': 130}, id='f2')
@check('shogird reja yoza OLMAYDI')
def _(pg): pg.no(USER).set('plans', {'title': 'Ozim', 'meals': []}, id='p3')
@check('shogird rejani oqiydi')
def _(pg): pg.ok(USER).get('plans', id='p1')


# == CHAT ==
def msg(sender, text):
    return {'sender_id': sender, 'text': text}


@check('shogird oz chatiga yozadi')
def _(pg): pg.ok(USER).add('chat_messages', msg(USER, 'salom'), chat_user_id=USER)
@check('trener oz shogirdi chatiga yozadi')
def _(pg): pg.ok(TRAINER).add('chat_messages', msg(TRAINER, 'javob'), chat_user_id=USER)
@check('boshqa trener shogird chatiga yoza OLMAYDI')
def _(pg): pg.no(TRAINER3).add('chat_messages', msg(TRAINER3, 'x'), chat_user_id=USER)
@check('bosh admin istalgan chatga yozadi')
def _(pg): pg.ok(OWNER).add('chat_messages', msg(OWNER, 'salom'), chat_user_id=USER3)
@check('shogird BOSHQANING chatiga yoza OLMAYDI')
def _(pg): pg.no(USER).add('chat_messages', msg(USER, 'x'), chat_user_id=TRAINER)
@check('boshqa nom bilan yoza OLMAYDI')
def _(pg): pg.no(USER).add('chat_messages', msg(TRAINER, 'soxta'), chat_user_id=USER)


# == TRENER KATALOGI VA TRENER TANLASH ==
@check('shogird trenerlar katalogini oqiydi')
def _(pg): assert pg.ok(USER4).list('trainers')
@check('shogird trenerini ozi tanlaydi (hali treneri yoq)')
def _(pg): pg.ok(USER4).update('users', {'trainer_id': TRAINER}, id=USER4)
@check('shogird qabul qilmayotgan trenerga ota OLMAYDI')
def _(pg): pg.no(USER4).update('users', {'trainer_id': TRAINER3}, id=USER4)
@check('shogird qabul qilmayotgan trenerni tanlay OLMAYDI')
def _(pg): pg.no(USER5).update('users', {'trainer_id': TRAINER3}, id=USER5)
@check('shogird katalogda yoq odamni (bosh adminni) tanlay OLMAYDI')
def _(pg): pg.no(USER5).update('users', {'trainer_id': OWNER}, id=USER5)
@check('trener tanlagan shogirdini koradi')
def _(pg): pg.ok(TRAINER).get('users', id=USER4)
@check('trener oz katalog yozuvini ozgartiradi')
def _(pg): pg.ok(TRAINER).set('trainers', {'name': 'Ali trener', 'bio': '5 yil tajriba', 'accepting': False}, id=TRAINER)
@check('trener BOSHQA trener yozuvini ozgartira OLMAYDI')
def _(pg): pg.no(TRAINER).set('trainers', {'name': 'X', 'bio': '', 'accepting': True}, id=TRAINER3)
@check('trener yozuviga ortiqcha maydon (telefon) qosha OLMAYDI')
def _(pg): pg.no_extra(TRAINER).set('trainers', {'name': 'A', 'bio': '', 'accepting': True, 'phone': '998'}, id=TRAINER)
@check('bosh admin trener sozlamalarini ozgartira OLMAYDI (trener boshqaradi)')
def _(pg): pg.no(OWNER).update('trainers', {'accepting': True}, id=TRAINER3)
@check('bosh admin yangi trenerga yozuv qoshadi')
def _(pg): pg.ok(OWNER).set('trainers', {'name': 'Yangi', 'bio': '', 'accepting': True}, id='yangiTrener')
@check('bosh admin yozuvni ochiradi (trenerlikdan olinganda)')
def _(pg): pg.ok(OWNER).delete('trainers', id='yangiTrener')
@check('shogird katalogga yoza OLMAYDI')
def _(pg): pg.no(USER4).set('trainers', {'name': 'Men trener', 'bio': '', 'accepting': True}, id=USER4)


# == VAZN HAFTADA 1 MARTA (SERVER) ==
def weigh_in(uid, w):
    """O'lchov yozuvi va profildagi vazn — bitta tranzaksiyada."""
    def fn(t):
        t.update('users', {'weight': w, 'last_weigh_in': NOW}, id=uid)
        t.insert('weights', {'user_id': uid, 'date': NOW, 'weight': w})
    return fn


@check('birinchi olchov (profil + yozuv bitta batchda) otadi')
def _(pg): pg.ok(W1).batch(weigh_in(W1, 70))
@check('ertasi kuni ikkinchi olchov OTMAYDI')
def _(pg): pg.no(W1).batch(weigh_in(W1, 69))
@check('olchov yozuvini profilsiz qoshib bolmaydi')
def _(pg): pg.no(W1).add('weights', {'date': now(), 'weight': 60}, user_id=W1)
@check('lastWeighIn ni ozi orqaga surib qoya OLMAYDI')
def _(pg): pg.no(W1).update('users', {'last_weigh_in': day(2020, 1, 1)}, id=W1)
@check('7 kun otgan bolsa olchov otadi')
def _(pg): pg.ok(W2).batch(weigh_in(W2, 88))
@check('anketada birinchi marta vazn kiritish otadi (vazn 0 edi)')
def _(pg): pg.ok(W3).update('users', {'weight': 65, 'age': 20}, id=W3)
@check('boshqa maydonlarni ozgartirish vaznga tegmasa otadi')
def _(pg): pg.ok(W2).update('users', {'name': 'Yangi ism', 'fcm_tokens': ['t1']}, id=W2)


# == TRENERNI ALMASHTIRISH ==
@check('shogird boshqa qabul qilayotgan trenerga otadi')
def _(pg): pg.ok(USER4).update('users', {'trainer_id': TRAINER4}, id=USER4)
@check('shogird trenersiz qola OLMAYDI')
def _(pg): pg.no(USER4).update('users', {'trainer_id': None}, id=USER4)


# == BOSH ADMIN BAHOLARI ==
@check('bosh admin trenerga baho qoyadi')
def _(pg): pg.ok(OWNER).set('ratings', {'stars': 4, 'comment': 'Yaxshi', 'updated_at': NOW}, trainer_id=TRAINER)
@check('baho 1..5 oraligida bolishi kerak')
def _(pg): pg.no(OWNER).set('ratings', {'stars': 7, 'comment': ''}, trainer_id=TRAINER)
@check('trener oz bahosini koora OLMAYDI')
def _(pg): pg.no(TRAINER).get('ratings', trainer_id=TRAINER)
@check('trener oziga baho qoya OLMAYDI')
def _(pg): pg.no(TRAINER).set('ratings', {'stars': 5, 'comment': ''}, trainer_id=TRAINER)


# == ZAL ==
@check('shogird Se/Pay/Sha variantini tanlaydi')
def _(pg): pg.ok(USER).update('users', {'gym_days': [2, 4, 6]}, id=USER)
@check('shogird Du/Chor/Ju variantini tanlaydi')
def _(pg): pg.ok(USER).update('users', {'gym_days': [1, 3, 5]}, id=USER)
@check('variantdan tashqari kunlar (Du/Pay/Sha) OTMAYDI')
def _(pg): pg.no(USER).update('users', {'gym_days': [1, 4, 6]}, id=USER)
@check('5 kun tanlab bolmaydi')
def _(pg): pg.no(USER).update('users', {'gym_days': [1, 2, 3, 4, 5]}, id=USER)
@check('shogird ozi "uyda mashq" belgilay OLMAYDI')
def _(pg): pg.no(USER).update('users', {'home_workout_date': '2026-09-15'}, id=USER)
@check('trener oz shogirdiga "uyda mashq" belgilaydi')
def _(pg): pg.ok(TRAINER).update('users', {'home_workout_date': '2026-09-15'}, id=USER)
@check('boshqa trener "uyda mashq" belgilay OLMAYDI')
def _(pg): pg.no(TRAINER3).update('users', {'home_workout_date': '2026-09-16'}, id=USER)


# == ROYXATDAN OTISH ==
@check('yangi odam ozini user qilib yaratadi')
def _(pg): pg.ok('newbie').set('users', {'name': 'Yangi', 'role': 'user', 'phone': '998905555555'}, id='newbie')
@check('yangi odam ozini admin qilib yarata OLMAYDI')
def _(pg): pg.no('hacker').set('users', {'name': 'X', 'role': 'admin', 'phone': '998906666666'}, id='hacker')
@check('yangi odam ozini owner qilib yarata OLMAYDI')
def _(pg): pg.no('hacker2').set('users', {'name': 'X', 'role': 'owner', 'phone': '998907777777'}, id='hacker2')


# == DOKON: TOVARLAR ==
@check('trener tovar qoshadi')
def _(pg): pg.ok(TRAINER).set('shop', {
    'category': 'Sport pitaniya', 'name': 'Protein 900 g', 'note': '', 'image': '',
    'price': 450000, 'stock': 5, 'active': True}, id='prot1')
@check('bosh admin tovar qoshadi')
def _(pg): pg.ok(OWNER).set('shop', {
    'category': 'Forma', 'name': 'Mayka', 'note': '', 'image': '',
    'price': 120000, 'stock': 10, 'active': True}, id='forma1')
@check('shogird tovarlarni koradi')
def _(pg): assert pg.ok(USER).list('shop')
@check('shogird tovar qosha OLMAYDI')
def _(pg): pg.no(USER).set('shop', {'category': 'Forma', 'name': 'Tekin', 'price': 1, 'stock': 99, 'active': True}, id='hack')
@check('shogird narxni ozgartira OLMAYDI')
def _(pg): pg.no(USER).update('shop', {'price': 1000}, id='prot1')


# == DOKON: BUYURTMALAR ==
def order(**extra):
    return {'client_id': USER, 'client_name': 'Shogird', 'client_phone': '998903333333', 'trainer_id': TRAINER,
            'product_id': 'prot1', 'product_name': 'Protein 900 g', 'category': 'Sport pitaniya',
            'price': 450000, 'qty': 1, 'status': 'new', 'created_at': NOW, **extra}


@check('shogird buyurtma beradi')
def _(pg): pg.ok(USER).add('orders', order())
@check('arzon narx yozib bolmaydi')
def _(pg): pg.no(USER).add('orders', order(price=1000))
@check('boshqa odam nomidan buyurtma OTMAYDI')
def _(pg): pg.no(USER).add('orders', order(client_id=USER3))
@check('oz trenerinikidan boshqasiga yozib bolmaydi')
def _(pg): pg.no(USER).add('orders', order(trainer_id=TRAINER3))
@check('darhol "berildi" qilib yarata OLMAYDI')
def _(pg): pg.no(USER).add('orders', order(status='given'))
@check('shogird rang bilan buyurtma beradi')
def _(pg): pg.ok(USER).add('orders', order(color='sariq'))
@check('30 belgidan uzun rang OTMAYDI')
def _(pg): pg.no(USER).add('orders', order(color='x' * 31))
@check('shogird buyurtmaga soxta zal yoza OLMAYDI')
def _(pg): pg.no(USER).add('orders', order(gym_id='zalX'))
@check('0 dona buyurtma OTMAYDI')
def _(pg): pg.no(USER).add('orders', order(qty=0))


@check('sotuvda yoq tovarga buyurtma OTMAYDI')
def _(pg):
    pg.admin.set('shop', {'category': 'Anjomlar', 'name': 'Qolqop', 'price': 90000, 'stock': 3, 'active': False}, id='off1')
    pg.no(USER).add('orders', order(product_id='off1', product_name='Qolqop', category='Anjomlar', price=90000))


@setup
def _orders(pg):
    base = {'client_id': USER, 'client_name': 'Shogird', 'client_phone': '998903333333',
            'trainer_id': TRAINER, 'product_id': 'prot1', 'product_name': 'Protein 900 g',
            'category': 'Sport pitaniya', 'price': 450000, 'qty': 1, 'status': 'new', 'created_at': now()}
    pg.admin.set('orders', base, id='o1')
    pg.admin.set('orders', base, id='o2')
    pg.admin.set('orders', {**base, 'client_id': USER3, 'trainer_id': TRAINER3}, id='o3')


@check('shogird oz buyurtmasini koradi')
def _(pg): pg.ok(USER).get('orders', id='o1')
@check('shogird boshqaning buyurtmasini kora OLMAYDI')
def _(pg): pg.no(USER).get('orders', id='o3')
@check('trener oz shogirdi buyurtmasini koradi')
def _(pg): pg.ok(TRAINER).get('orders', id='o1')
@check('trener boshqa shogird buyurtmasini kora OLMAYDI')
def _(pg): pg.no(TRAINER).get('orders', id='o3')
@check('trener oz buyurtmalarini soraydi (filtr bilan)')
def _(pg): assert pg.ok(TRAINER).list('orders', trainer_id=TRAINER)
@check('trener HAMMA buyurtmani sorayolmaydi')
def _(pg): pg.no(TRAINER).list('orders')
@check('bosh admin hamma buyurtmani koradi')
def _(pg): assert len(pg.ok(OWNER).list('orders')) == len(pg.admin.list('orders'))
@check('trener "berildi" deb belgilaydi')
def _(pg): pg.ok(TRAINER).update('orders', {'status': 'given', 'updated_at': NOW}, id='o1')
@check('shogird ozi "berildi" qila OLMAYDI')
def _(pg): pg.no(USER).update('orders', {'status': 'given'}, id='o2')
@check('shogird buyurtmadagi narxni ozgartira OLMAYDI')
def _(pg): pg.no(USER).update('orders', {'price': 1000}, id='o2')
@check('shogird kutilayotgan buyurtmasini bekor qiladi')
def _(pg): pg.ok(USER).update('orders', {'status': 'canceled', 'updated_at': NOW}, id='o2')
@check('berilgan buyurtmani shogird bekor qila OLMAYDI')
def _(pg): pg.no(USER).update('orders', {'status': 'canceled'}, id='o1')
@check('boshqa trener holatni ozgartira OLMAYDI')
def _(pg): pg.no(TRAINER3).update('orders', {'status': 'canceled'}, id='o1')
@check('trener buyurtmani ochira OLMAYDI')
def _(pg): pg.no(TRAINER).delete('orders', id='o1')
@check('bosh admin buyurtmani ochiradi')
def _(pg): pg.ok(OWNER).delete('orders', id='o1')


# == ABONEMENT ==
def abon(**x):
    return {'start_date': now(), 'price': 50000, 'currency': 'UZS', 'created_at': NOW, **x}


@check('trener oz shogirdiga abonement qoshadi')
def _(pg): pg.ok(TRAINER).add('subscriptions', abon(months=3, price=300000), user_id=USER)
@check('trener BOSHQANING shogirdiga abonement qosha OLMAYDI')
def _(pg): pg.no(TRAINER).add('subscriptions', abon(months=1, price=100000), user_id=USER3)
@check('shogird ozi abonement qosha OLMAYDI')
def _(pg): pg.no(USER).add('subscriptions', abon(months=1, price=0), user_id=USER)
@check('bosh admin istalgan shogirdga abonement qoshadi')
def _(pg): pg.ok(OWNER).add('subscriptions', abon(months=12, price=1000000), user_id=USER3)
@check('notogri oy soni (25) OTMAYDI')
def _(pg): pg.no(TRAINER).add('subscriptions', abon(months=25, price=100000), user_id=USER)
@check('ortiqcha maydonli abonement OTMAYDI')
def _(pg): pg.no_extra(TRAINER).add('subscriptions', abon(months=1, price=100000, izoh='x'), user_id=USER)
@check('kunlik abonement (days 1, months 0) otadi')
def _(pg): pg.ok(TRAINER).add('subscriptions', abon(months=0, days=1), user_id=USER)
@check('oy ham kun ham 0 — OTMAYDI')
def _(pg): pg.no(TRAINER).add('subscriptions', abon(months=0, days=0), user_id=USER)
@check('oy va kun birga — OTMAYDI')
def _(pg): pg.no(TRAINER).add('subscriptions', abon(months=1, days=1), user_id=USER)
@check('32 kunlik — OTMAYDI')
def _(pg): pg.no(TRAINER).add('subscriptions', abon(months=0, days=32), user_id=USER)
@check('days maydonisiz oylik avvalgidek otadi')
def _(pg): pg.ok(TRAINER).add('subscriptions', abon(months=1), user_id=USER)
@check('shogird oz abonementlar royxatini oqiydi')
def _(pg): assert pg.ok(USER).list('subscriptions', user_id=USER)
@check('boshqa trener abonementni oqiy OLMAYDI')
def _(pg): pg.no(TRAINER3).list('subscriptions', user_id=USER)
@check('trener oz shogirdiga abonement muddatini belgilaydi')
def _(pg): pg.ok(TRAINER).update('users', {'subscription_expires_at': day(2027, 1, 1)}, id=USER)
@check('shogird ozi abonement muddatini ozgartira OLMAYDI')
def _(pg): pg.no(USER).update('users', {'subscription_expires_at': day(2099, 1, 1)}, id=USER)


# == DAVOMAT ==
def mark(by, present=True):
    return {'present': present, 'marked_by': by, 'marked_at': NOW}


@check('trener oz shogirdining davomatini belgilaydi')
def _(pg): pg.ok(TRAINER).set('attendance', mark(TRAINER), user_id=USER, day='2026-10-04')
@check('boshqa trener davomat belgilay OLMAYDI')
def _(pg): pg.no(TRAINER3).set('attendance', mark(TRAINER3), user_id=USER, day='2026-10-04')
@check('shogird ozi davomat belgilay OLMAYDI')
def _(pg): pg.no(USER).set('attendance', mark(USER), user_id=USER, day='2026-10-04')
@check('boshqa odam nomidan davomat belgilab bolmaydi')
def _(pg): pg.no(TRAINER).set('attendance', mark(OWNER), user_id=USER, day='2026-10-05')
@check('present notogri turda OTMAYDI')
def _(pg): pg.no(TRAINER).set('attendance', mark(TRAINER, present='ha'), user_id=USER, day='2026-10-06')
@check('shogird oz davomatini oqiydi')
def _(pg): pg.ok(USER).get('attendance', user_id=USER, day='2026-10-04')
@check('boshqa trener davomatni oqiy OLMAYDI')
def _(pg): pg.no(TRAINER3).get('attendance', user_id=USER, day='2026-10-04')


# == ESLATMALAR ==
def reminder(client, name, trainer, by, left):
    return {'client_id': client, 'client_name': name, 'trainer_id': trainer, 'sent_by': by,
            'sent_at': NOW, 'days_left': left}


@check('trener oz shogirdiga eslatma yozadi')
def _(pg): pg.ok(TRAINER).add('reminders', reminder(USER, 'Shogird', TRAINER, TRAINER, 2))
@check('trener BOSHQANING shogirdiga eslatma yoza OLMAYDI')
def _(pg): pg.no(TRAINER).add('reminders', reminder(USER3, 'Boshqa', TRAINER, TRAINER, 1))
@check('bosh admin istalgan mijozga eslatma yozadi')
def _(pg): pg.ok(OWNER).add('reminders', reminder(USER3, 'Boshqa', TRAINER3, OWNER, 0))
@check('barmen eslatma yoza OLMAYDI')
def _(pg): pg.no(BARMEN).add('reminders', reminder(USER, 'Shogird', TRAINER, BARMEN, 2))
@check('shogird eslatma yoza OLMAYDI')
def _(pg): pg.no(USER).add('reminders', reminder(USER, 'Shogird', TRAINER, USER, 2))
@check('boshqa odam nomidan eslatma yozib bolmaydi')
def _(pg): pg.no(TRAINER).add('reminders', reminder(USER, 'Shogird', TRAINER, OWNER, 2))
@check('trener oz (filtrlangan) eslatmalarini oqiydi')
def _(pg): assert pg.ok(TRAINER).list('reminders', trainer_id=TRAINER)
@check('trener filtrsiz eslatmalarni sorayolmaydi')
def _(pg): pg.no(TRAINER).list('reminders')
@check('bosh admin hamma eslatmani koradi')
def _(pg): assert len(pg.ok(OWNER).list('reminders')) == len(pg.admin.list('reminders'))


# == ZALLAR ==
@check('bosh admin zal qoshadi')
def _(pg): pg.ok(OWNER).set('gyms', {'name': 'Diamond Chilonzor', 'address': 'Bunyodkor 12'}, id='zal1')
@check('zal joyi bilan saqlanadi (mamlakat/viloyat/tuman)')
def _(pg): pg.ok(OWNER).set('gyms', {
    'name': 'Kotta Qani zali', 'address': 'Bunyodkor 12',
    'country': 'Ozbekiston', 'region': 'Toshkent shahri', 'district': 'Chilonzor'}, id='zal1')
@check('notanish maydonli zal OTMAYDI')
def _(pg): pg.no_extra(OWNER).set('gyms', {'name': 'X', 'country': 'Ozbekiston', 'kenglik': 41.3}, id='zal1b')
@check('bosh admin zal nomini ozgartiradi')
def _(pg): pg.ok(OWNER).set('gyms', {'name': 'Diamond Chilonzor 2', 'address': ''}, id='zal1')
@check('nomsiz zal OTMAYDI')
def _(pg): pg.no(OWNER).set('gyms', {'name': '', 'address': ''}, id='zal2')
@check('ortiqcha maydonli zal OTMAYDI')
def _(pg): pg.no_extra(OWNER).set('gyms', {'name': 'X', 'address': '', 'egasi': 'men'}, id='zal3')
@check('trener zal qosha OLMAYDI')
def _(pg): pg.no(TRAINER).set('gyms', {'name': 'Yangi', 'address': ''}, id='zal4')
@check('shogird zal qosha OLMAYDI')
def _(pg): pg.no(USER).set('gyms', {'name': 'Yangi', 'address': ''}, id='zal5')
@check('trener zallarni koradi')
def _(pg): assert pg.ok(TRAINER).list('gyms')
@check('shogird zallarni koradi')
def _(pg): assert pg.ok(USER).list('gyms')
@check('kirmagan odam zalni kora OLMAYDI')
def _(pg): pg.no(None).list('gyms')
@check('bosh admin trenerni zalga biriktiradi')
def _(pg): pg.ok(OWNER).update('users', {'gym_id': 'zal1'}, id=TRAINER)
@check('trener ozini boshqa zalga kochira OLMAYDI')
def _(pg): pg.no(TRAINER).update('users', {'gym_id': 'zal9'}, id=TRAINER)
@check('shogird ozining zalini ozgartira OLMAYDI')
def _(pg): pg.no(USER).update('users', {'gym_id': 'zal1'}, id=USER)
@check('trener shogirdining zalini ozgartira OLMAYDI')
def _(pg): pg.no(TRAINER).update('users', {'gym_id': 'zal1'}, id=USER)
@check('bosh admin zalni ochiradi')
def _(pg): pg.ok(OWNER).delete('gyms', id='zal1')


# == BARMEN ==
@check('barmen tovar qoshadi')
def _(pg): pg.ok(BARMEN).set('shop', {
    'category': 'Sport pitaniya', 'name': 'Kreatin 300 g', 'note': '', 'image': '',
    'price': 250000, 'stock': 4, 'active': True}, id='bar1')
@check('barmen tovar qoldigini ozgartiradi')
def _(pg): pg.ok(BARMEN).update('shop', {'stock': 3}, id='bar1')


@setup
def _barmen(pg):
    # TRAINER yuqorida zal1 ga biriktirilgan; barmenlar — zal1 va zal2
    pg.admin.update('users', {'gym_id': 'zal1'}, id=BARMEN)
    pg.admin.set('users', {'name': 'Barmen2', 'role': 'barmen', 'phone': '998906060606', 'gym_id': 'zal2'}, id=BARMEN2)
    pg.admin.set('orders', {
        'client_id': USER3, 'client_name': 'Boshqa', 'trainer_id': TRAINER3, 'gym_id': 'zal2',
        'product_id': 'bar1', 'product_name': 'Kreatin', 'category': 'Sport pitaniya',
        'price': 250000, 'qty': 1, 'status': 'new', 'created_at': now()}, id='og2')


@check('barmen oz zali buyurtmalarini soraydi (filtr bilan)')
def _(pg): pg.ok(BARMEN).list('orders', gym_id='zal1')
@check('barmen filtrsiz hamma buyurtmani sora OLMAYDI')
def _(pg): pg.no(BARMEN).list('orders')
@check('barmen boshqa zal buyurtmalarini sora OLMAYDI')
def _(pg): pg.no(BARMEN).list('orders', gym_id='zal2')
@check('barmen boshqa zal buyurtmasini kora OLMAYDI')
def _(pg): pg.no(BARMEN).get('orders', id='og2')
@check('barmen boshqa zal buyurtmasini "berildi" qila OLMAYDI')
def _(pg): pg.no(BARMEN).update('orders', {'status': 'given', 'updated_at': NOW, 'given_by': BARMEN, 'given_at': NOW}, id='og2')
@check('ikkinchi zal barmeni oz buyurtmasini koradi')
def _(pg): pg.ok(BARMEN2).get('orders', id='og2')
@check('zali bor trener shogirdi buyurtmaga trener zalini yozadi')
def _(pg): pg.ok(USER).add('orders', order(gym_id='zal1'))
@check('zali bor trener shogirdi zalsiz buyurtma bera OLMAYDI')
def _(pg): pg.no(USER).add('orders', order())
@check('bosh admin katalogdagi zal kozgusini togrilaydi')
def _(pg): pg.ok(OWNER).update('trainers', {'gym_id': 'zal1'}, id=TRAINER)
@check('katalogdagi zal haqiqiy zaldan farq qila OLMAYDI')
def _(pg): pg.no(OWNER).update('trainers', {'gym_id': 'zal2'}, id=TRAINER)
@check('trener katalogga soxta zal yoza OLMAYDI')
def _(pg): pg.no(TRAINER).set('trainers', {'name': 'Ali', 'bio': '', 'accepting': True, 'gym_id': 'zal2'}, id=TRAINER)


@check('barmen "berildi" deb belgilaydi va kim bergani yoziladi')
def _(pg):
    pg.admin.set('orders', {
        'client_id': USER, 'client_name': 'Shogird', 'client_phone': '998903333333', 'trainer_id': TRAINER,
        'gym_id': 'zal1', 'product_id': 'bar1', 'product_name': 'Kreatin 300 g', 'category': 'Sport pitaniya',
        'price': 250000, 'qty': 1, 'status': 'new', 'created_at': now()}, id='ob1')
    pg.ok(BARMEN).update('orders', {'status': 'given', 'updated_at': NOW, 'given_by': BARMEN, 'given_at': NOW}, id='ob1')


@check('boshqa nomdan "men berdim" deb yozib bolmaydi')
def _(pg):
    pg.admin.set('orders', {
        'client_id': USER, 'client_name': 'Shogird', 'trainer_id': TRAINER, 'gym_id': 'zal1',
        'product_id': 'bar1', 'product_name': 'Kreatin', 'category': 'Sport pitaniya',
        'price': 250000, 'qty': 1, 'status': 'new', 'created_at': now()}, id='ob2')
    pg.no(BARMEN).update('orders', {'status': 'given', 'given_by': TRAINER}, id='ob2')


@check('barmen buyurtmani ochira OLMAYDI')
def _(pg): pg.no(BARMEN).delete('orders', id='ob1')
@check('barmen shogird hujjatini kora OLMAYDI')
def _(pg): pg.no(BARMEN).get('users', id=USER)
@check('barmen shogird chatini kora OLMAYDI')
def _(pg): pg.no(BARMEN).list('chat_messages', chat_user_id=USER)
@check('barmen rol ozgartira OLMAYDI')
def _(pg): pg.no(BARMEN).update('users', {'role': 'admin'}, id=USER)
@check('barmen reja yoza OLMAYDI')
def _(pg): pg.no(BARMEN).set('plans', {'title': 'X', 'meals': []}, id='pb1')
@check('barmen zal qosha OLMAYDI')
def _(pg): pg.no(BARMEN).set('gyms', {'name': 'Yangi'}, id='zalb')


# == RASMLAR (oldin / keyin) ==
def rasm(n=1000):
    return {'data': bytes(n), 'taken_at': NOW, 'weight': 80}


@check('shogird ozi rasm qoshadi')
def _(pg): pg.ok(USER).set('photos', rasm(), user_id=USER, id='r1')
@check('350 KB dan katta rasm OTMAYDI')
def _(pg): pg.no(USER).set('photos', rasm(400 * 1024), user_id=USER, id='r2')
@check('rasmga ortiqcha maydon qoshib bolmaydi')
def _(pg): pg.no_extra(USER).set('photos', {**rasm(), 'izoh': 'x'}, user_id=USER, id='r3')
@check('boshqa shogird nomiga rasm qoshib bolmaydi')
def _(pg): pg.no(USER3).set('photos', rasm(), user_id=USER, id='r4')
@check('trener shogirdi rasmini koradi')
def _(pg): pg.ok(TRAINER).get('photos', user_id=USER, id='r1')
@check('boshqa trener rasmni kora OLMAYDI')
def _(pg): pg.no(TRAINER3).get('photos', user_id=USER, id='r1')
@check('boshqa shogird rasmni kora OLMAYDI')
def _(pg): pg.no(USER3).get('photos', user_id=USER, id='r1')
@check('barmen rasmni kora OLMAYDI')
def _(pg): pg.no(BARMEN).get('photos', user_id=USER, id='r1')
@check('trener shogird rasmini ochira OLMAYDI')
def _(pg): pg.no(TRAINER).delete('photos', user_id=USER, id='r1')
@check('shogird oz rasmini ochiradi')
def _(pg): pg.ok(USER).delete('photos', user_id=USER, id='r1')


# == TOLOV KOZGUSI (memberships) ==
@setup
def _memberships(pg):
    a = pg.admin
    a.update('users', {'trainer_id': TRAINER}, id=USER)
    a.update('users', {'gym_id': 'zal1'}, id=TRAINER)
    a.update('users', {'role': 'admin', 'gym_id': 'zal1'}, id=TRAINER2)
    a.update('users', {'role': 'admin', 'gym_id': 'zal2'}, id=TRAINER3)
    a.update('users', {'gym_id': None}, id=TRAINER4)
    a.update('users', {'gym_id': 'zal1'}, id=BARMEN)
    a.update('users', {'name': 'Barmen2', 'role': 'barmen', 'gym_id': 'zal2'}, id=BARMEN2)


def kozgu(**x):
    return {'name': 'Shogird', 'gym_id': 'zal1', 'months': 1, 'days': 0, 'price': 500000, 'currency': 'UZS',
            'paid_date': now(), 'expires_at': now(), 'updated_at': NOW, **x}


@check('trener oz shogirdi tolov kozgusini yozadi')
def _(pg): pg.ok(TRAINER).set('memberships', kozgu(), user_id=USER)
@check('kozguga notogri zal yozib bolmaydi')
def _(pg): pg.no(TRAINER).set('memberships', kozgu(gym_id='zal2'), user_id=USER)
@check('kozguga ortiqcha maydon qoshib bolmaydi')
def _(pg): pg.no_extra(TRAINER).set('memberships', kozgu(phone='99890'), user_id=USER)
@check('boshqa trener kozguni yoza OLMAYDI')
def _(pg): pg.no(TRAINER2).set('memberships', kozgu(), user_id=USER)
@check('shogird oz kozgusini yoza OLMAYDI')
def _(pg): pg.no(USER).set('memberships', kozgu(), user_id=USER)
@check('bosh admin kozguni yozadi')
def _(pg): pg.ok(OWNER).set('memberships', kozgu(months=0, days=1, price=50000), user_id=USER)
@check('shu zalning boshqa treneri tolovni koradi')
def _(pg): assert pg.ok(TRAINER2).list('memberships', gym_id='zal1')
@check('shu zal barmeni tolovni koradi')
def _(pg): assert pg.ok(BARMEN).list('memberships', gym_id='zal1')
@check('boshqa zal treneri kora OLMAYDI')
def _(pg): pg.no(TRAINER3).get('memberships', user_id=USER)
@check('boshqa zal barmeni kora OLMAYDI')
def _(pg): pg.no(BARMEN2).list('memberships', gym_id='zal1')
@check('zalsiz trener kora OLMAYDI')
def _(pg): pg.no(TRAINER4).get('memberships', user_id=USER)


@check('xodim hamma zal tolovlarini filtrsiz ola OLMAYDI')
def _(pg):
    # Postgres so'rovni rad etmaydi, boshqa zal yozuvini yashiradi — tekshirish uchun boshqa zal to'lovi kerak
    pg.admin.set('memberships', kozgu(name='Boshqa', gym_id='zal2', updated_at=now()), user_id=USER3)
    pg.no(TRAINER2).list('memberships')


@check('shogird oz tolov kozgusini oqiydi')
def _(pg): pg.ok(USER).get('memberships', user_id=USER)
@check('boshqa shogird kora OLMAYDI')
def _(pg): pg.no(USER3).get('memberships', user_id=USER)
@check('bosh admin hamma tolovlarni oqiydi')
def _(pg): assert len(pg.ok(OWNER).list('memberships')) == len(pg.admin.list('memberships'))
@check('boshqa trener tolov kozgusi orqali shogird hujjatini ocha OLMAYDI')
def _(pg): pg.no(TRAINER2).get('users', id=USER)
@check('trener kozguni ochira OLMAYDI')
def _(pg): pg.no(TRAINER).delete('memberships', user_id=USER)


# == OYLIK HISOBOT (collectionGroup) ==
@setup
def _report(pg):
    pg.admin.set('subscriptions', {'start_date': now(), 'months': 1, 'price': 300000, 'currency': 'UZS',
                                   'paid_date': now()}, user_id=USER, id='sh1')


@check('bosh admin hamma abonementlarni bir sorovda oqiydi')
def _(pg): assert len(pg.ok(OWNER).list('subscriptions')) == len(pg.admin.list('subscriptions'))
@check('trener hamma abonementlarni oqiy OLMAYDI')
def _(pg): pg.no(TRAINER).list('subscriptions')
@check('barmen hamma abonementlarni oqiy OLMAYDI')
def _(pg): pg.no(BARMEN).list('subscriptions')
@check('shogird hamma abonementlarni oqiy OLMAYDI')
def _(pg): pg.no(USER).list('subscriptions')


# == VIDEO DARSLAR (videos) — firestore test.mjs dagi bilan bir xil ==
def dars(by, **more):
    return {'title': 'Ovqatlanish asoslari', 'category': 'ovqatlanish', 'description': '', 'seconds': 240,
            'url': 'https://qobil-video.qobilfitness.workers.dev/v/videos/123e4567-e89b-12d3-a456-426614174000.mp4',
            'created_at': 1760000000000, 'created_by': by, **more}


@check('trener dars qoshadi')
def _(pg): pg.ok(TRAINER).set('videos', dars(TRAINER), id='d1')
@check('bosh admin dars qoshadi')
def _(pg): pg.ok(OWNER).set('videos', dars(OWNER), id='d2')
@check('shogird dars qosha OLMAYDI')
def _(pg): pg.no(USER).set('videos', dars(USER), id='d3')
@check('barmen dars qosha OLMAYDI')
def _(pg): pg.no(BARMEN).set('videos', dars(BARMEN), id='d4')
@check('shogird darsni koradi')
def _(pg): pg.ok(USER).get('videos', id='d1')
@check('kirmagan odam darsni kora OLMAYDI')
def _(pg): pg.no(None).get('videos', id='d1')
@check('noma lum turdagi dars OTMAYDI')
def _(pg): pg.no(TRAINER).set('videos', dars(TRAINER, category='reklama'), id='d5')
@check('ortiqcha maydonli (izoh/layk) dars OTMAYDI')
def _(pg): pg.no_extra(TRAINER).set('videos', dars(TRAINER, likes=5), id='d6')
@check('boshqa nomidan dars qosha OLMAYDI')
def _(pg): pg.no(TRAINER).set('videos', dars(OWNER), id='d7')
@check('tahrirda muallifni ozgartirib BOLMAYDI (dars)')
def _(pg): pg.no(TRAINER).set('videos', dars(OWNER), id='d1')
@check('trener darsni tahrirlaydi')
def _(pg): pg.ok(TRAINER).set('videos', dars(TRAINER, title='Yangi nom'), id='d1')
@check('shogird darsni ochira OLMAYDI')
def _(pg): pg.no(USER).delete('videos', id='d1')
@check('trener darsni ochiradi')
def _(pg): pg.ok(TRAINER).delete('videos', id='d1')


# == MASHQLAR (trener qoshadi) ==
def ex(by, **more):
    return {'name': 'Sinov mashqi', 'muscle': 'chest', 'sets': '4 x 10', 'tip': 'Sekin', 'also': ['triceps'],
            'video': '', 'created_at': 1760000000000, 'created_by': by, **more}


@setup
def _exercises(pg):
    pg.admin.set('exercises', ex(TRAINER), id='e1')


@check('trener mashq qoshadi')
def _(pg): pg.ok(TRAINER).set('exercises', ex(TRAINER), id='e2')
@check('bosh admin mashq qoshadi')
def _(pg): pg.ok(OWNER).set('exercises', ex(OWNER), id='e3')
@check('shogird mashq qosha OLMAYDI')
def _(pg): pg.no(USER).set('exercises', ex(USER), id='e4')
@check('barmen mashq qosha OLMAYDI')
def _(pg): pg.no(BARMEN).set('exercises', ex(BARMEN), id='e5')
@check('kirmagan odam mashqni oqiy OLMAYDI')
def _(pg): pg.no(None).get('exercises', id='e1')
@check('shogird mashqni oqiydi')
def _(pg): pg.ok(USER).get('exercises', id='e1')
@check('trener boshqa nomidan qosha OLMAYDI')
def _(pg): pg.no(TRAINER).set('exercises', ex(OWNER), id='e6')
@check('notogri mushak bilan qoshib BOLMAYDI')
def _(pg): pg.no(TRAINER).set('exercises', ex(TRAINER, muscle='bosh'), id='e7')
@check('bosh nom bilan qoshib BOLMAYDI')
def _(pg): pg.no(TRAINER).set('exercises', ex(TRAINER, name=''), id='e8')
@check('ortiqcha maydon bilan qoshib BOLMAYDI')
def _(pg): pg.no_extra(TRAINER).set('exercises', ex(TRAINER, role='owner'), id='e9')
@check('trener namunaviy mashqqa video qoshadi (base bilan)')
def _(pg): pg.ok(TRAINER).set('exercises', ex(TRAINER, base='Otjimaniya', video='https://example.com/v'), id='e10')
@check('trener mashqqa daraja qoyadi')
def _(pg): pg.ok(TRAINER).set('exercises', ex(TRAINER, level='pro'), id='e11')
@check('notogri daraja bilan saqlab BOLMAYDI')
def _(pg): pg.no(TRAINER).set('exercises', ex(TRAINER, level='chempion'), id='e12')
@check('tahrirda base ni ozgartirib BOLMAYDI')
def _(pg): pg.no(TRAINER).set('exercises', ex(TRAINER, base='Boshqa'), id='e10')
@check('boshqa trener mashqni tahrirlaydi (muallif saqlanadi)')
def _(pg): pg.ok(TRAINER2).set('exercises', ex(TRAINER, name='Yangi nom'), id='e1')
@check('tahrirda muallifni ozgartirib BOLMAYDI')
def _(pg): pg.no(TRAINER2).set('exercises', ex(TRAINER2), id='e1')
@check('shogird mashqni tahrirlay OLMAYDI')
def _(pg): pg.no(USER).set('exercises', ex(TRAINER, name='Buzdim'), id='e1')
@check('shogird mashqni ochira OLMAYDI')
def _(pg): pg.no(USER).delete('exercises', id='e1')
@check('trener mashqni ochiradi')
def _(pg): pg.ok(TRAINER).delete('exercises', id='e1')


# == SHOGIRD DASTURI (trener tanlagan mashqlar) ==
@check('trener oz shogirdiga mashq tanlaydi')
def _(pg): pg.ok(TRAINER).update('users', {'program.chest': ['Otjimaniya']}, id=USER)
@check('shogird oz dasturini ozgartira OLMAYDI')
def _(pg): pg.no(USER).update('users', {'program.chest': ['Boshqa']}, id=USER)
@check('shogird dasturga tegmasdan oz profilini saqlaydi')
def _(pg): pg.ok(USER).update('users', {'name': 'Shogird'}, id=USER)
@check('boshqa trener begona shogirdga mashq tanlay OLMAYDI')
def _(pg): pg.no(TRAINER3).update('users', {'program.chest': ['X']}, id=USER)
@check('bosh admin istalgan shogirdga mashq tanlaydi')
def _(pg): pg.ok(OWNER).update('users', {'program.back': ['Y']}, id=USER)


assert not _setups, 'oxirgi tayyorlovdan keyin test yo\'q'


@pytest.mark.parametrize('name,fn,setups', CHECKS, ids=[c[0] for c in CHECKS])
def test_rule(pg, name, fn, setups):
    for s in setups:
        s(pg)
    fn(pg)
