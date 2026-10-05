import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../models/shop.dart';
import '../models/stats.dart';
import '../models/photo.dart';
import '../models/subscription.dart';
import 'notifications.dart';
import 'push.dart';

final _fs = FirebaseFirestore.instance;
final _auth = FirebaseAuth.instance;

String todayKey([DateTime? d]) => DateFormat('yyyy-MM-dd').format(d ?? DateTime.now());

/// Kirish telefon raqam + parol bilan (SMS yo'q). Firebase'da raqam ichki emailga aylanadi,
/// foydalanuvchi uni ko'rmaydi: 901234567 -> 998901234567@phone.kottaqani.uz
const _phoneDomain = 'phone.kottaqani.uz';

/// "90 123 45 67" / "+998 (90) 123-45-67" -> "998901234567"
String normalizePhone(String input) {
  final d = input.replaceAll(RegExp(r'\D'), '');
  return d.length == 9 ? '998$d' : d;
}

String phoneToEmail(String phone) => '${normalizePhone(phone)}@$_phoneDomain';

class AuthService {
  static Stream<User?> changes() => _auth.authStateChanges();

  static Future<void> signIn(String phone, String pass) =>
      _auth.signInWithEmailAndPassword(email: phoneToEmail(phone), password: pass);

  static Future<void> register(String name, String phone, String pass) async {
    final cred =
        await _auth.createUserWithEmailAndPassword(email: phoneToEmail(phone), password: pass);
    await _fs.collection('users').doc(cred.user!.uid).set(AppUser(
          id: cred.user!.uid,
          name: name.trim(),
          email: '',
          phone: normalizePhone(phone),
        ).toMap());
  }

  // Email bilan kirish (o'chirilgan — endi faqat telefon raqam + parol):
  // static Future<void> signInWithEmail(String email, String pass) =>
  //     _auth.signInWithEmailAndPassword(email: email.trim(), password: pass);
  //
  // static Future<void> registerWithEmail(String name, String email, String pass) async {
  //   final cred = await _auth.createUserWithEmailAndPassword(
  //       email: email.trim(), password: pass);
  //   await _fs.collection('users').doc(cred.user!.uid).set(
  //       AppUser(id: cred.user!.uid, name: name.trim(), email: email.trim()).toMap());
  // }

  /// Chiqish: bu telefon endi shu akkaunt bildirishnomalarini olmaydi, eslatmalar bekor
  static Future<void> signOut() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) await Push.unregister(uid);
    await Notifications.cancelAll();
    await _auth.signOut();
  }

  /// Hujjati o'chirilgan akkauntning kirish yozuvini o'chirish (faqat o'zi, hozir kirgan holda).
  /// Firestore hujjati allaqachon yo'q — shuning uchun faqat Auth.
  /// Firebase o'chirishdan oldin yaqinda kirishni talab qiladi — shuning uchun parol bilan
  /// qayta tasdiqlanadi.
  static Future<void> deleteOwnLogin(String password) async {
    final u = _auth.currentUser!;
    await u.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: u.email!, password: password),
    );
    await Notifications.cancelAll();
    await u.delete();
  }

  /// Parolni almashtirish: Firebase avval hozirgi parol bilan qayta tasdiqlashni talab qiladi
  static Future<void> changePassword(String current, String next) async {
    final u = _auth.currentUser!;
    await u.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: u.email!, password: current),
    );
    await u.updatePassword(next);
  }
}

class Db {
  // ---------- users ----------
  static Stream<AppUser?> user(String uid) =>
      _fs.collection('users').doc(uid).snapshots().map((d) => d.exists ? AppUser.fromDoc(d) : null);

  /// Hamma shogirdlar — faqat bosh admin uchun (qoidalar trenerga bu so'rovni bermaydi)
  static Stream<List<AppUser>> clients() => _fs
      .collection('users')
      .where('role', isEqualTo: 'user')
      .snapshots()
      .map((s) => s.docs.map(AppUser.fromDoc).toList());

  /// Trenerga biriktirilgan shogirdlar — trener faqat shularni ko'radi
  static Stream<List<AppUser>> clientsOf(String trainerId) => _fs
      .collection('users')
      .where('trainerId', isEqualTo: trainerId)
      .snapshots()
      .map((s) => s.docs.map(AppUser.fromDoc).where((u) => u.role == 'user').toList());

  /// Trenerlar va bosh admin — "Xodimlar" bo'limi uchun.
  /// `whereIn` bitta so'rovda ikkala rolni oladi.
  static Stream<List<AppUser>> staff() => _fs
      .collection('users')
      .where('role', whereIn: ['admin', 'owner', 'barmen'])
      .snapshots()
      .map((s) => s.docs.map(AppUser.fromDoc).toList());

  /// Faqat trenerlar (bosh admin emas) — shogirdga trener biriktirish ro'yxati uchun
  static Stream<List<AppUser>> trainers() => _fs
      .collection('users')
      .where('role', isEqualTo: 'admin')
      .snapshots()
      .map((s) => s.docs.map(AppUser.fromDoc).toList());

  // ---------- zallar (filiallar) ----------
  /// Zallar ro'yxati — nomi bo'yicha tartiblangan
  static Stream<List<Gym>> gyms() => _fs.collection('gyms').snapshots().map(
      (s) => s.docs.map(Gym.fromDoc).toList()..sort((a, b) => a.name.compareTo(b.name)));

  /// Zal qo'shish yoki nomini o'zgartirish; id qaytadi
  static Future<String> saveGym(Gym g) async {
    if (g.id.isEmpty) return (await _fs.collection('gyms').add(g.toMap())).id;
    await _fs.collection('gyms').doc(g.id).set(g.toMap());
    return g.id;
  }

  /// Zalni o'chirish — undagi trenerlar zalsiz qoladi
  static Future<void> deleteGym(String id) async {
    final staff = await _fs.collection('users').where('gymId', isEqualTo: id).get();
    for (final d in staff.docs) {
      await d.reference.update({'gymId': null});
      await _mirrorTrainerGym(d.id, null);
    }
    await _fs.collection('gyms').doc(id).delete();
  }

  /// Trenerni zalga biriktirish (null — zaldan chiqarish). Faqat bosh admin.
  static Future<void> setUserGym(String uid, String? gymId) async {
    await _fs.collection('users').doc(uid).update({'gymId': gymId});
    await _mirrorTrainerGym(uid, gymId);
  }

  /// Trener katalogidagi zal ko'zgusini yangilaydi (trener bo'lmasa — yozuv yo'q, tegilmaydi)
  static Future<void> _mirrorTrainerGym(String uid, String? gymId) async {
    final ref = _fs.collection('trainers').doc(uid);
    if ((await ref.get()).exists) await ref.update({'gymId': gymId ?? ''});
  }

  /// Yangi trener akkaunti — bosh admin yaratadi.
  ///
  /// Firebase mijoz kutubxonasi yangi akkaunt yaratganda o'sha akkauntga kirib oladi,
  /// shuning uchun ish IKKINCHI Firebase ulanishida bajariladi — bosh admin o'z
  /// seansida qoladi. Hujjat ham o'sha seansdan yoziladi (qoidalar: har kim faqat
  /// o'z hujjatini va faqat `user` roli bilan yarata oladi), so'ng bosh admin uni
  /// trenerga aylantiradi va zalga biriktiradi.
  static Future<String> createStaff({
    required String name,
    required String phone,
    required String password,
    String role = 'admin',
    String? gymId,
  }) async {
    final app = await Firebase.initializeApp(
      name: 'trener-yaratish-${DateTime.now().millisecondsSinceEpoch}',
      options: Firebase.app().options,
    );
    String uid;
    try {
      final cred = await FirebaseAuth.instanceFor(app: app).createUserWithEmailAndPassword(
        email: phoneToEmail(phone),
        password: password,
      );
      uid = cred.user!.uid;
      await FirebaseFirestore.instanceFor(app: app).collection('users').doc(uid).set(
            AppUser(id: uid, name: name.trim(), email: '', phone: normalizePhone(phone)).toMap(),
          );
    } finally {
      await app.delete();
    }
    // Endi bosh admin (asosiy seans) rolni va zalni qo'yadi
    await setRole(uid, role);
    if (gymId != null) await setUserGym(uid, gymId);
    return uid;
  }

  static Future<void> updateUser(AppUser u) =>
      _fs.collection('users').doc(u.id).set(u.toMap(), SetOptions(merge: true));

  /// Reja biriktirilgan vaqt ham saqlanadi — reytingda rioya shu kundan hisoblanadi
  static Future<void> assignPlan(String uid, String? planId) =>
      _fs.collection('users').doc(uid).update({
        'planId': planId,
        'planAssignedAt': planId == null ? null : FieldValue.serverTimestamp(),
      });

  /// Shogird maqsadini trener belgilaydi ('lose' / 'gain')
  static Future<void> setGoal(String uid, String goal) =>
      _fs.collection('users').doc(uid).update({'goal': goal});

  /// Shogirdni trenerga biriktirish (null — biriktirishni bekor qilish)
  static Future<void> assignTrainer(String uid, String? trainerId) =>
      _fs.collection('users').doc(uid).update({'trainerId': trainerId});

  /// Trenerlar katalogi — shogird anketada tanlaydi (qabul qilayotganlar)
  static Stream<List<TrainerInfo>> trainerDirectory() => _fs.collection('trainers').snapshots().map(
      (s) => s.docs.map(TrainerInfo.fromDoc).where((t) => t.accepting).toList()
        ..sort((a, b) => a.name.compareTo(b.name)));

  /// Trenerning katalogdagi o'z yozuvi (trener boshqaradi)
  static Stream<TrainerInfo?> trainerProfile(String uid) => _fs
      .collection('trainers')
      .doc(uid)
      .snapshots()
      .map((d) => d.exists ? TrainerInfo.fromDoc(d) : null);

  /// Zal har doim trenerning o'z hujjatidan olinadi — bosh admin zalni almashtirgan
  /// bo'lsa ham eski qiymat yozilib qolmaydi.
  static Future<void> saveTrainerProfile(TrainerInfo t) async {
    final gymId = await _gymOf(t.id);
    await _fs.collection('trainers').doc(t.id).set(
        TrainerInfo(t.id, t.name, bio: t.bio, accepting: t.accepting, gymId: gymId).toMap());
  }

  static Future<String> _gymOf(String uid) async =>
      ((await _fs.collection('users').doc(uid).get()).data()?['gymId'] ?? '') as String;

  /// Yangi trener uchun katalog yozuvi (bor bo'lsa — trener sozlamalariga tegilmaydi)
  static Future<void> _ensureTrainerEntry(String uid, String name) async {
    final ref = _fs.collection('trainers').doc(uid);
    if (!(await ref.get()).exists) {
      await ref.set(TrainerInfo(uid, name, gymId: await _gymOf(uid)).toMap());
    }
  }

  /// Shogird trenerini o'zi tanlaydi yoki almashtiradi (qoidalar: faqat katalogda shogird
  /// qabul qilayotgan trener)
  static Future<void> chooseTrainer(String uid, String trainerId) =>
      _fs.collection('users').doc(uid).update({'trainerId': trainerId});

  // ---------- zal ----------
  /// Shogird o'z mashg'ulot kunlarini tanlaydi (aynan 3 ta)
  static Future<void> setGymDays(String uid, List<int> days) =>
      _fs.collection('users').doc(uid).update({
        'gymDays': [...days]..sort()
      });

  /// Trener: bugun uyda mashq (null — bekor qilish)
  static Future<void> setHomeWorkout(String uid, String? day) =>
      _fs.collection('users').doc(uid).update({'homeWorkoutDate': day});

  // ---------- bosh admin baholari ----------
  static Stream<Map<String, TrainerRating>> ratings() => _fs
      .collection('ratings')
      .snapshots()
      .map((s) => {for (final d in s.docs) d.id: TrainerRating.fromDoc(d)});

  static Future<void> saveRating(String trainerId, int stars, String comment) =>
      _fs.collection('ratings').doc(trainerId).set({
        'stars': stars,
        'comment': comment,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// Katalogni haqiqiy trenerlar bilan tenglashtirish — bosh admin ilovani ochganda:
  /// yozuvi yo'q trenerga yozuv qo'shiladi, trener bo'lmaganlarniki o'chiriladi.
  /// Mavjud yozuvlarning ism/ma'lumot/qabul sozlamalariga tegilmaydi (ularni trener boshqaradi).
  static Future<void> syncTrainerDirectory() async {
    final trainersNow = await trainers().first;
    final dir = await _fs.collection('trainers').get();
    for (final t in trainersNow) {
      final gymId = t.gymId ?? '';
      final entry = dir.docs.where((d) => d.id == t.id).firstOrNull;
      if (entry == null) {
        await _fs
            .collection('trainers')
            .doc(t.id)
            .set(TrainerInfo(t.id, t.name.isEmpty ? t.phone : t.name, gymId: gymId).toMap());
      } else if ((entry.data()['gymId'] ?? '') != gymId) {
        // zal ko'zgusi eskirgan (yoki eski yozuvda yo'q) — to'g'rilanadi
        await entry.reference.update({'gymId': gymId});
      }
    }
    for (final d in dir.docs) {
      if (!trainersNow.any((t) => t.id == d.id)) await d.reference.delete();
    }
  }

  /// Rolni o'zgartirish — faqat bosh admin (qoidalar bilan himoyalangan).
  /// Trenerlikdan olinganda unga biriktirilgan shogirdlar bo'shatiladi.
  /// Trenerlar katalogi ham yangilanadi (katalogda faqat `admin` roli).
  static Future<void> setRole(String uid, String role) async {
    await _fs.collection('users').doc(uid).update({'role': role});
    if (role == 'admin') {
      final d = (await _fs.collection('users').doc(uid).get()).data() ?? {};
      await _ensureTrainerEntry(uid, (d['name'] ?? d['phone'] ?? '') as String);
    } else {
      await _fs.collection('trainers').doc(uid).delete();
    }
    // trener bo'lmay qolsa — shogirdlari bo'shaydi
    if (role != 'admin') {
      final orphans = await _fs.collection('users').where('trainerId', isEqualTo: uid).get();
      for (final d in orphans.docs) {
        await d.reference.update({'trainerId': null});
      }
    }
  }

  /// Akkauntni o'chirish — faqat bosh admin.
  /// Firestore hujjati o'chadi; kirish akkaunti (Auth) mijoz tomonidan
  /// o'chirilmaydi, shuning uchun AuthGate hujjatsiz kirishni to'sadi.
  static Future<void> deleteUser(String uid) async {
    final clientsOfUser = await _fs.collection('users').where('trainerId', isEqualTo: uid).get();
    for (final d in clientsOfUser.docs) {
      await d.reference.update({'trainerId': null});
    }
    await _fs.collection('trainers').doc(uid).delete();
    await _fs.collection('users').doc(uid).delete();
  }

  // ---------- foods ----------
  static Stream<List<Food>> foods() => _fs
      .collection('foods')
      .orderBy('name')
      .snapshots()
      .map((s) => s.docs.map(Food.fromDoc).toList());

  static Future<void> saveFood(Food f) => f.id.isEmpty
      ? _fs.collection('foods').add(f.toMap())
      : _fs.collection('foods').doc(f.id).set(f.toMap());

  static Future<void> deleteFood(String id) => _fs.collection('foods').doc(id).delete();

  // ---------- plans ----------
  static Stream<List<Plan>> plans() =>
      _fs.collection('plans').snapshots().map((s) => s.docs.map(Plan.fromDoc).toList());

  static Stream<Plan?> plan(String id) =>
      _fs.collection('plans').doc(id).snapshots().map((d) => d.exists ? Plan.fromDoc(d) : null);

  /// Rejani saqlaydi va uning id sini qaytaradi (yangi reja bo'lsa — yaratilgan id)
  static Future<String> savePlan(Plan p) async {
    if (p.id.isEmpty) return (await _fs.collection('plans').add(p.toMap())).id;
    await _fs.collection('plans').doc(p.id).set(p.toMap());
    return p.id;
  }

  static Future<void> deletePlan(String id) => _fs.collection('plans').doc(id).delete();

  // ---------- do'kon: tovarlar (`shop`) ----------
  /// Hamma tovarlar — bo'lim tartibi bo'yicha, ichida nomi bo'yicha.
  /// (Sotuvda yo'qlarini ekranning o'zi ajratadi: trener ko'radi, shogird ko'rmaydi.)
  static Stream<List<Product>> products() =>
      _fs.collection('shop').snapshots().map((s) => s.docs.map(Product.fromDoc).toList()
        ..sort((a, b) {
          final c =
              shopCategories.indexOf(a.category).compareTo(shopCategories.indexOf(b.category));
          return c != 0 ? c : a.name.compareTo(b.name);
        }));

  static Future<void> saveProduct(Product p) => p.id.isEmpty
      ? _fs.collection('shop').add(p.toMap())
      : _fs.collection('shop').doc(p.id).set(p.toMap());

  static Future<void> deleteProduct(String id) => _fs.collection('shop').doc(id).delete();

  // ---------- do'kon: buyurtmalar (`orders`) ----------
  /// Yangisi yuqorida. Saralash ilovada — shunda Firestore'da qo'shimcha indeks kerak emas.
  static List<ShopOrder> _sortedOrders(QuerySnapshot s) => s.docs.map(ShopOrder.fromDoc).toList()
    ..sort((a, b) => (b.createdAt ?? DateTime(2100)).compareTo(a.createdAt ?? DateTime(2100)));

  /// Shogirdning o'z buyurtmalari
  static Stream<List<ShopOrder>> myOrders(String uid) =>
      _fs.collection('orders').where('clientId', isEqualTo: uid).snapshots().map(_sortedOrders);

  /// Trenerga tushgan buyurtmalar (o'z shogirdlariniki)
  static Stream<List<ShopOrder>> ordersOf(String trainerId) => _fs
      .collection('orders')
      .where('trainerId', isEqualTo: trainerId)
      .snapshots()
      .map(_sortedOrders);

  /// Hamma buyurtmalar — faqat bosh admin uchun
  /// (qoidalar trener va barmenga bu so'rovni bermaydi)
  static Stream<List<ShopOrder>> allOrders() =>
      _fs.collection('orders').snapshots().map(_sortedOrders);

  /// Barmen: faqat o'z zalining buyurtmalari. Zalga biriktirilmagan barmen hech narsa ko'rmaydi.
  static Stream<List<ShopOrder>> gymOrders(String? gymId) => (gymId ?? '').isEmpty
      ? Stream.value(const <ShopOrder>[])
      : _fs
          .collection('orders')
          .where('gymId', isEqualTo: gymId)
          .snapshots()
          .map(_sortedOrders);

  /// Kim qaysi buyurtmalarni ko'radi: bosh admin — hammasi, barmen — o'z zali,
  /// trener — o'z shogirdlariniki
  static Stream<List<ShopOrder>> ordersFor(AppUser u) => u.isOwner
      ? allOrders()
      : u.isBarmen
          ? gymOrders(u.gymId)
          : ordersOf(u.id);

  /// Shogird buyurtma beradi. Yozuv bilan birga chatga xabar ketadi —
  /// trener buyurtmani bildirishnoma sifatida ham ko'radi.
  static Future<void> createOrder(AppUser client, Product p, int qty,
      {String size = '', String color = ''}) async {
    final trainerId = client.trainerId ?? '';
    // zal trener katalogidan (shogird trenerning `users` hujjatini o'qiy olmaydi)
    final gymId = trainerId.isEmpty
        ? ''
        : ((await _fs.collection('trainers').doc(trainerId).get()).data()?['gymId'] ?? '')
            as String;
    final o = ShopOrder(
      clientId: client.id,
      clientName: client.name,
      clientPhone: client.phone,
      trainerId: trainerId,
      gymId: gymId,
      productId: p.id,
      productName: p.name,
      category: p.category,
      size: size,
      color: color,
      price: p.price,
      currency: p.currency,
      qty: qty,
    );
    await _fs.collection('orders').add({
      'clientId': o.clientId,
      'clientName': o.clientName,
      'clientPhone': o.clientPhone,
      'trainerId': o.trainerId,
      'gymId': o.gymId,
      'productId': o.productId,
      'productName': o.productName,
      'category': o.category,
      if (o.size.isNotEmpty) 'size': o.size,
      if (o.color.isNotEmpty) 'color': o.color,
      'price': o.price,
      'currency': o.currency,
      'qty': o.qty,
      'status': orderNew,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await send(client.id, client.id, o.chatText);
  }

  /// Trener holatni belgilaydi. "Berildi" — zaldagi qoldiqdan ayiriladi.
  /// Shogird chatda javob xabarini ko'radi.
  static Future<void> setOrderStatus(ShopOrder o, String status, String byId) async {
    await _fs.collection('orders').doc(o.id).update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
      // kim berdi — sotuv hisoboti shunga tayanadi
      if (status == orderGiven) 'givenBy': byId,
      if (status == orderGiven) 'givenAt': FieldValue.serverTimestamp(),
    });
    if (status == orderGiven && o.productId.isNotEmpty) {
      final ref = _fs.collection('shop').doc(o.productId);
      await _fs.runTransaction((tx) async {
        final d = await tx.get(ref);
        if (!d.exists) return;
        final data = d.data() as Map<String, dynamic>;
        if (o.size.isNotEmpty) {
          // O'lchamli tovar: faqat tanlangan o'lcham kamayadi, jamlangan `stock` ham yangilanadi.
          final sizeStock = Map<String, dynamic>.from(data['sizeStock'] as Map? ?? const {});
          final left = ((sizeStock[o.size] ?? 0) as num).toInt() - o.qty;
          sizeStock[o.size] = left < 0 ? 0 : left;
          final total = sizeStock.values.fold<int>(0, (s, v) => s + (v as num).toInt());
          tx.update(ref, {'sizeStock.${o.size}': left < 0 ? 0 : left, 'stock': total});
        } else {
          final left = ((data['stock'] ?? 0) as num).toInt() - o.qty;
          tx.update(ref, {'stock': left < 0 ? 0 : left});
        }
      });
    }
    await send(
      o.clientId,
      byId,
      status == orderGiven
          ? '✅ Buyurtma berildi: ${o.title} × ${o.qty} — ${o.totalText}'
          : '❌ Buyurtma bekor qilindi: ${o.title}',
    );
  }

  /// Shogird o'z buyurtmasini bekor qiladi (faqat hali berilmagan bo'lsa)
  static Future<void> cancelOrder(String id) => _fs.collection('orders').doc(id).update({
        'status': orderCanceled,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  // ---------- meal logs ----------
  static DocumentReference _dayRef(String uid, String day) =>
      _fs.collection('users').doc(uid).collection('days').doc(day);

  static Stream<Set<int>> doneMeals(String uid, String day) =>
      _dayRef(uid, day).snapshots().map((d) {
        final data = d.data() as Map<String, dynamic>?;
        return Set<int>.from(data?['done'] ?? []);
      });

  static Future<void> toggleMeal(String uid, String day, int index, bool done) =>
      _dayRef(uid, day).set({
        'done': done ? FieldValue.arrayUnion([index]) : FieldValue.arrayRemove([index])
      }, SetOptions(merge: true));

  static Stream<int> water(String uid, String day) => _dayRef(uid, day)
      .snapshots()
      .map((d) => ((d.data() as Map<String, dynamic>?)?['water'] ?? 0) as int);

  static Future<void> setWater(String uid, String day, int glasses) =>
      _dayRef(uid, day).set({'water': glasses}, SetOptions(merge: true));

  // ---------- weights ----------
  static Stream<List<WeightLog>> weights(String uid) => _fs
      .collection('users')
      .doc(uid)
      .collection('weights')
      .orderBy('date')
      .snapshots()
      .map((s) => s.docs.map(WeightLog.fromDoc).toList());

  /// Vazn kiritish — o'lchov yozuvi va profildagi vazn BITTA batch'da.
  /// `lastWeighIn` server vaqti bilan yoziladi: qoidalar shu orqali haftada 1 martadan
  /// ko'p kiritishga ruxsat bermaydi (ilovani chetlab o'tganda ham).
  static Future<void> addWeight(String uid, double w) async {
    final user = _fs.collection('users').doc(uid);
    final batch = _fs.batch()
      ..set(user.collection('weights').doc(), {'date': Timestamp.now(), 'weight': w})
      ..update(user, {'weight': w, 'lastWeighIn': FieldValue.serverTimestamp()});
    await batch.commit();
  }

  // ---------- "oldin / keyin" rasmlari ----------
  /// Eskisi birinchi — "oldin" chapda, "keyin" o'ngda
  static Stream<List<ProgressPhoto>> photos(String uid) => _fs
      .collection('users')
      .doc(uid)
      .collection('photos')
      .orderBy('takenAt')
      .snapshots()
      .map((s) => s.docs.map(ProgressPhoto.fromDoc).toList());

  /// Rasm hujjatning o'zida saqlanadi (siqilgan, [ProgressPhoto.maxBytes] gacha)
  static Future<void> addPhoto(String uid, Uint8List bytes, double weight) =>
      _fs.collection('users').doc(uid).collection('photos').add({
        'data': Blob(bytes),
        'takenAt': FieldValue.serverTimestamp(),
        'weight': weight,
      });

  static Future<void> deletePhoto(String uid, String id) =>
      _fs.collection('users').doc(uid).collection('photos').doc(id).delete();

  // ---------- abonement ----------
  static Stream<List<Subscription>> subscriptions(String uid) => _fs
      .collection('users')
      .doc(uid)
      .collection('subscriptions')
      .orderBy('startDate', descending: true)
      .snapshots()
      .map((s) => s.docs.map(Subscription.fromDoc).toList());

  /// Hamma shogirdlarning abonementlari (shogird uid bilan) — faqat bosh admin, oylik hisobot uchun.
  /// Qoidalar trener va barmenga bu so'rovni bermaydi.
  static Stream<List<(String, Subscription)>> allSubscriptions() =>
      _fs.collectionGroup('subscriptions').snapshots().map((s) => s.docs
          .map((d) => (d.reference.parent.parent?.id ?? '', Subscription.fromDoc(d)))
          .toList());

  /// Abonement qo'shish — yozuv va profildagi tugash sanasi BITTA batch'da (`addWeight` kabi).
  static Future<void> addSubscription(String uid, Subscription s) async {
    final user = _fs.collection('users').doc(uid);
    final batch = _fs.batch()
      ..set(user.collection('subscriptions').doc(), s.toMap())
      ..update(user, {'subscriptionExpiresAt': Timestamp.fromDate(s.expiresAt)});
    await batch.commit();
  }

  // ---------- davomat ----------
  static DocumentReference _attendanceRef(String uid, String day) =>
      _fs.collection('users').doc(uid).collection('attendance').doc(day);

  static Stream<bool> attendance(String uid, String day) => _attendanceRef(uid, day)
      .snapshots()
      .map((d) => (d.data() as Map<String, dynamic>?)?['present'] == true);

  static Future<void> markAttendance(String uid, String day, bool present, String byId) =>
      _attendanceRef(uid, day).set({
        'present': present,
        'markedBy': byId,
        'markedAt': FieldValue.serverTimestamp(),
      });

  // ---------- eslatmalar (abonement tugashi haqida jo'natilgan jurnal) ----------
  static Stream<List<Reminder>> remindersOf(String trainerId) => _fs
      .collection('reminders')
      .where('trainerId', isEqualTo: trainerId)
      .snapshots()
      .map((s) => s.docs.map(Reminder.fromDoc).toList());

  static Stream<List<Reminder>> allReminders() =>
      _fs.collection('reminders').snapshots().map((s) => s.docs.map(Reminder.fromDoc).toList());

  /// Abonement tugashi haqida eslatma: jurnalga yoziladi va shogirdga chatga xabar boradi.
  static Future<void> sendSubscriptionReminder(AppUser client, int daysLeft, String byId) async {
    final r = Reminder(
      clientId: client.id,
      clientName: client.name,
      trainerId: client.trainerId ?? '',
      sentBy: byId,
      daysLeft: daysLeft,
    );
    await _fs.collection('reminders').add(r.toMap());
    await send(
      client.id,
      byId,
      daysLeft <= 0
          ? '⏰ Abonementingiz tugadi — yangilang'
          : '⏰ Abonementingiz $daysLeft kundan keyin tugaydi',
    );
  }

  // ---------- trenerlar reytingi (faqat bosh admin) ----------

  /// Har xodim va unga biriktirilgan shogirdlar bo'yicha so'nggi [statsDays] kun
  /// ko'rsatkichlari. Bir martalik yuklash — ekranda "yangilash" bilan qayta chaqiriladi.
  static Future<List<TrainerStat>> trainerStats() async {
    // Reytingda faqat trenerlar — bosh admin trener emas
    final results = await Future.wait([trainers().first, clients().first, plans().first]);
    final staffList = results[0] as List<AppUser>;
    final clientList = results[1] as List<AppUser>;
    final mealsByPlan = {for (final p in results[2] as List<Plan>) p.id: p.mealsPerDay};
    final now = DateTime.now();
    final days = [for (var i = 0; i < statsDays; i++) todayKey(now.subtract(Duration(days: i)))];

    Future<ClientStat> load(AppUser c) async {
      final perDay = mealsByPlan[c.planId] ?? 0;
      // Reja berilgan kundan oldingi kunlar (eski reja) rioyaga kirmaydi
      final tracked = days.take(ClientStat.trackedDaysFor(c.planAssignedAt, now));
      final data = await Future.wait([
        Future.wait(tracked.map((d) => _dayRef(c.id, d).get())),
        _fs.collection('users').doc(c.id).collection('weights').orderBy('date').get(),
        _fs
            .collection('chats')
            .doc(c.id)
            .collection('messages')
            .orderBy('createdAt', descending: true)
            .limit(50)
            .get(),
      ]);
      final done = (data[0] as List<DocumentSnapshot>).fold<int>(0, (s, d) {
        final m = d.data() as Map<String, dynamic>?;
        final n = (m?['done'] as List?)?.length ?? 0;
        return s + (n > perDay ? perDay : n);
      });
      return ClientStat(
        client: c,
        mealsPerDay: perDay,
        mealsDone: done,
        weights: (data[1] as QuerySnapshot).docs.map(WeightLog.fromDoc).toList(),
        messages: (data[2] as QuerySnapshot).docs.map(ChatMessage.fromDoc).toList(),
        now: now,
      );
    }

    final assigned = clientList.where((c) => staffList.any((t) => t.id == c.trainerId));
    final loaded = await Future.wait(assigned.map(load));
    return [
      for (final t in staffList)
        TrainerStat(trainer: t, clients: loaded.where((s) => s.client.trainerId == t.id).toList()),
    ];
  }

  // ---------- chat (har bir user uchun bitta chat: chats/{uid}) ----------
  static Stream<List<ChatMessage>> messages(String chatUid) => _fs
      .collection('chats')
      .doc(chatUid)
      .collection('messages')
      .orderBy('createdAt', descending: true)
      .limit(200)
      .snapshots()
      .map((s) => s.docs.map(ChatMessage.fromDoc).toList());

  /// Bildirishnomalar uchun: oxirgi xabarlar hujjat id si bilan (takror bildirmaslik uchun)
  static Stream<List<(String, ChatMessage)>> messageEvents(String chatUid) => _fs
      .collection('chats')
      .doc(chatUid)
      .collection('messages')
      .orderBy('createdAt', descending: true)
      .limit(20)
      .snapshots()
      .map((s) => s.docs.map((d) => (d.id, ChatMessage.fromDoc(d))).toList());

  // ---------- push tokenlar (FCM) ----------
  static Future<void> addFcmToken(String uid, String token) =>
      _fs.collection('users').doc(uid).update({
        'fcmTokens': FieldValue.arrayUnion([token])
      });

  static Future<void> removeFcmToken(String uid, String token) =>
      _fs.collection('users').doc(uid).update({
        'fcmTokens': FieldValue.arrayRemove([token])
      });

  static Future<void> send(String chatUid, String senderId, String text) =>
      _fs.collection('chats').doc(chatUid).collection('messages').add({
        'senderId': senderId,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });
}

// ---------- providers ----------
final authProvider = StreamProvider<User?>((ref) => AuthService.changes());

/// Trenerlar katalogi — anketa va AuthGate uchun (kirmagan bo'lsa bo'sh)
final trainerDirectoryProvider = StreamProvider<List<TrainerInfo>>((ref) {
  final u = ref.watch(authProvider).value;
  if (u == null) return Stream.value(const []);
  return Db.trainerDirectory();
});

final meProvider = StreamProvider<AppUser?>((ref) {
  final u = ref.watch(authProvider).value;
  if (u == null) return Stream.value(null);
  return Db.user(u.uid);
});
