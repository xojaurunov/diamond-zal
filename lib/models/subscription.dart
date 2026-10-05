import 'package:cloud_firestore/cloud_firestore.dart';

/// Abonement muddatlari (oy) — tanlov ro'yxati uchun
const subscriptionMonths = [1, 3, 6, 12];

/// Narxlar (so'm) — zal egasi belgilagan (5-okt 2026). Oynada o'zi to'ladi, qo'lda o'zgaradi.
const subscriptionDayPrice = 50000;
const subscriptionMonthPrice = 500000;

/// `users/{uid}/subscriptions/{id}` — mijozning abonement yozuvi.
/// Qo'shilganda `AppUser.subscriptionExpiresAt` bir vaqtda yangilanadi (`Db.addSubscription`).
class Subscription {
  final String id;
  final DateTime startDate;

  /// Oylik abonement: oy soni. Kunlik bo'lsa 0.
  final int months;

  /// Kunlik tashrif: kun soni. Oylik bo'lsa 0 (eski yozuvlarda maydon yo'q).
  final int days;
  final int price;
  final String currency;
  final DateTime? paidDate;
  final DateTime? createdAt;

  const Subscription({
    this.id = '',
    required this.startDate,
    required this.months,
    this.days = 0,
    this.price = 0,
    this.currency = 'UZS',
    this.paidDate,
    this.createdAt,
  });

  bool get isDaily => days > 0;

  /// "Kunlik", "Oylik", "3 oy"
  String get kindLabel => kindLabelOf(months: months, days: days);

  static String kindLabelOf({int months = 0, int days = 0}) => days > 0
      ? (days == 1 ? 'Kunlik' : '$days kun')
      : (months == 1 ? 'Oylik' : '$months oy');

  /// Belgilangan narx: kunlik — kuniga, oylik — oyiga
  static int priceOf({int months = 0, int days = 0}) =>
      days > 0 ? days * subscriptionDayPrice : months * subscriptionMonthPrice;

  /// Tugash sanasi: boshlanish sanasidan [months] oy keyin
  static DateTime expiryOf(DateTime start, int months) =>
      DateTime(start.year, start.month + months, start.day);

  /// Kunlik — oxirgi to'langan kunning o'zi (1 kun = boshlanish kuni)
  DateTime get expiresAt => isDaily
      ? DateTime(startDate.year, startDate.month, startDate.day + days - 1)
      : expiryOf(startDate, months);

  /// Qolgan kun (manfiy bo'lishi mumkin — necha kun oldin tugagan)
  static int daysLeft(DateTime? exp, [DateTime? now]) {
    if (exp == null) return 0;
    final n = now ?? DateTime.now();
    final a = DateTime(n.year, n.month, n.day);
    final b = DateTime(exp.year, exp.month, exp.day);
    return b.difference(a).inDays;
  }

  /// Hali amal qiladimi
  static bool isActive(DateTime? exp, [DateTime? now]) =>
      exp != null && daysLeft(exp, now) >= 0;

  /// Tugashi yaqinlashganmi (0–3 kun qoldi)
  static bool isExpiringSoon(DateTime? exp, [DateTime? now]) {
    final d = daysLeft(exp, now);
    return exp != null && d >= 0 && d <= 3;
  }

  /// Muddati o'tganmi
  static bool isExpired(DateTime? exp, [DateTime? now]) =>
      exp != null && daysLeft(exp, now) < 0;

  factory Subscription.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return Subscription(
      id: doc.id,
      startDate: (d['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      months: ((d['months'] ?? 1) as num).toInt(),
      days: ((d['days'] ?? 0) as num).toInt(),
      price: ((d['price'] ?? 0) as num).toInt(),
      currency: (d['currency'] ?? 'UZS') as String,
      paidDate: (d['paidDate'] as Timestamp?)?.toDate(),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'startDate': Timestamp.fromDate(startDate),
        'months': months,
        if (days > 0) 'days': days,
        'price': price,
        'currency': currency,
        'paidDate': paidDate == null ? null : Timestamp.fromDate(paidDate!),
        'createdAt': FieldValue.serverTimestamp(),
      };
}

/// `reminders/{id}` — abonement tugashi haqida jo'natilgan har bir eslatma yozuvi
/// (haftalik hisobot uchun; o'zi hech narsani jo'natmaydi, faqat jurnal).
class Reminder {
  final String id;
  final String clientId;
  final String clientName;
  final String trainerId;
  final String sentBy;
  final DateTime? sentAt;
  final int daysLeft;

  const Reminder({
    this.id = '',
    required this.clientId,
    this.clientName = '',
    this.trainerId = '',
    required this.sentBy,
    this.sentAt,
    required this.daysLeft,
  });

  factory Reminder.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return Reminder(
      id: doc.id,
      clientId: (d['clientId'] ?? '') as String,
      clientName: (d['clientName'] ?? '') as String,
      trainerId: (d['trainerId'] ?? '') as String,
      sentBy: (d['sentBy'] ?? '') as String,
      sentAt: (d['sentAt'] as Timestamp?)?.toDate(),
      daysLeft: ((d['daysLeft'] ?? 0) as num).toInt(),
    );
  }

  Map<String, dynamic> toMap() => {
        'clientId': clientId,
        'clientName': clientName,
        'trainerId': trainerId,
        'sentBy': sentBy,
        'sentAt': FieldValue.serverTimestamp(),
        'daysLeft': daysLeft,
      };
}

/// Haftalik eslatma hisoboti: kuni nechta eslatma jo'natilgani.
class ReminderReport {
  /// Kun yorlig'i ("2026-10-04") -> shu kun jo'natilgan eslatmalar soni.
  /// So'nggi [days] kun, eng eskisi birinchi.
  static Map<String, int> byDay(List<Reminder> list, {int days = 7, DateTime? now}) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final counts = <String, int>{};
    for (var i = days - 1; i >= 0; i--) {
      final day = today.subtract(Duration(days: i));
      counts[_key(day)] = 0;
    }
    for (final r in list) {
      final at = r.sentAt;
      if (at == null) continue;
      final key = _key(DateTime(at.year, at.month, at.day));
      if (counts.containsKey(key)) counts[key] = counts[key]! + 1;
    }
    return counts;
  }

  static String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Sana: "03.10.2026" (null — bo'sh)
String fmtDay(DateTime? d) {
  if (d == null) return '';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year}';
}

/// `memberships/{uid}` — mijozning OXIRGI to'lovi ko'zgusi: zalning hamma treneri va barmeni
/// ko'radi. Faqat ism va to'lov — vazn, telefon, reja bu yerda yo'q.
/// `Db.addSubscription` abonement bilan bitta batch'da yozadi.
class Membership {
  final String uid;
  final String name;
  final String gymId;
  final int months;
  final int days;
  final int price;
  final String currency;
  final DateTime? paidDate;
  final DateTime? expiresAt;

  const Membership({
    required this.uid,
    this.name = '',
    this.gymId = '',
    this.months = 0,
    this.days = 0,
    this.price = 0,
    this.currency = 'UZS',
    this.paidDate,
    this.expiresAt,
  });

  String get kindLabel => Subscription.kindLabelOf(months: months, days: days);

  factory Membership.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return Membership(
      uid: doc.id,
      name: (d['name'] ?? '') as String,
      gymId: (d['gymId'] ?? '') as String,
      months: ((d['months'] ?? 0) as num).toInt(),
      days: ((d['days'] ?? 0) as num).toInt(),
      price: ((d['price'] ?? 0) as num).toInt(),
      currency: (d['currency'] ?? 'UZS') as String,
      paidDate: (d['paidDate'] as Timestamp?)?.toDate(),
      expiresAt: (d['expiresAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Abonementdan ko'zgu yozuvi
  static Map<String, dynamic> mapOf(String name, String gymId, Subscription s) => {
        'name': name,
        'gymId': gymId,
        'months': s.months,
        'days': s.days,
        'price': s.price,
        'currency': s.currency,
        'paidDate': Timestamp.fromDate(s.paidDate ?? s.startDate),
        'expiresAt': Timestamp.fromDate(s.expiresAt),
        'updatedAt': FieldValue.serverTimestamp(),
      };
}
