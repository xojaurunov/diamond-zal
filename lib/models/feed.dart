import 'gym.dart';
import 'models.dart';
import 'shop.dart';

/// Ilova ichidagi bildirishnomalar ro'yxati ("Eslatma" bo'limi).
///
/// Bu yerda yangi ma'lumot saqlanmaydi — ro'yxat bazadagi narsalardan yig'iladi:
/// chat xabarlari, biriktirilgan reja, vazn muddati, bugungi mahallar, buyurtmalar.
/// Shuning uchun telefonda bildirishnoma o'chirilgan bo'lsa ham hammasi shu yerda ko'rinadi.

enum FeedKind { chat, plan, weighIn, meal, order, attention, gym }

class FeedItem {
  final FeedKind kind;
  final String title;
  final String body;
  final DateTime at;

  /// true — foydalanuvchidan amal kutilmoqda (vazn kiritish, javob berish)
  final bool action;

  const FeedItem({
    required this.kind,
    required this.title,
    required this.body,
    required this.at,
    this.action = false,
  });
}

/// Ro'yxatni vaqt bo'yicha (yangisi yuqorida) saralaydi va [limit] tagacha qisqartiradi
List<FeedItem> sortFeed(List<FeedItem> items, {int limit = 60}) {
  final list = [...items]..sort((a, b) => b.at.compareTo(a.at));
  return list.length > limit ? list.sublist(0, limit) : list;
}

/// Bugungi kun uchun "07:30" kabi vaqtni to'liq sanaga aylantiradi
DateTime? _todayAt(String hhmm, DateTime now) {
  final p = hhmm.split(':');
  if (p.length != 2) return null;
  final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
  if (h == null || m == null || h > 23 || m > 59) return null;
  return DateTime(now.year, now.month, now.day, h, m);
}

/// Shogird uchun bildirishnomalar
List<FeedItem> studentFeed({
  required AppUser user,
  required List<ChatMessage> messages,
  Plan? plan,
  List<WeightLog> weights = const [],
  List<ShopOrder> orders = const [],
  Set<int> doneMeals = const {},
  DateTime? now,
}) {
  final n = now ?? DateTime.now();
  final items = <FeedItem>[];

  // 1. Trenerdan kelgan xabarlar
  for (final m in messages) {
    if (m.senderId == user.id) continue;
    items.add(FeedItem(
      kind: FeedKind.chat,
      title: 'Trener xabar yozdi',
      body: m.text,
      at: m.createdAt,
    ));
  }

  // 2. Biriktirilgan reja
  if (plan != null && user.planAssignedAt != null) {
    items.add(FeedItem(
      kind: FeedKind.plan,
      title: 'Yangi reja berildi',
      body: plan.title,
      at: user.planAssignedAt!,
    ));
  }

  // 3. Haftalik vazn — muddat kelgan bo'lsa
  final last = weights.isEmpty ? null : weights.last;
  if (user.profileDone && WeightLog.canAdd(last, n)) {
    items.add(FeedItem(
      kind: FeedKind.weighIn,
      title: 'Vazn kiritish vaqti keldi',
      body: last == null
          ? 'Birinchi o‘lchov — ertalab, nahorga tortiling'
          : 'Oxirgi o‘lchovdan ${WeightLog.daysSince(last.date, n)} kun o‘tdi',
      at: last == null ? n : last.date.add(const Duration(days: weighInIntervalDays)),
      action: true,
    ));
  }

  // 4. Bugungi mahallar — vaqti o'tgan, lekin belgilanmagani
  if (plan != null && user.fitsPlan(plan)) {
    final meals = plan.mealsFor(n.weekday);
    for (var i = 0; i < meals.length; i++) {
      if (doneMeals.contains(i)) continue;
      final at = _todayAt(meals[i].time, n);
      if (at == null || at.isAfter(n)) continue;
      final names = meals[i].items.map((e) => e.name.split('(').first.trim()).take(3);
      items.add(FeedItem(
        kind: FeedKind.meal,
        title: '${meals[i].title.isEmpty ? 'Ovqat' : meals[i].title} vaqti o‘tdi',
        body: names.isEmpty ? 'Belgilashni unutmang' : names.join(', '),
        at: at,
        action: true,
      ));
    }
  }

  // 5. Buyurtmalar
  for (final o in orders) {
    final at = o.createdAt;
    if (at == null) continue;
    items.add(FeedItem(
      kind: FeedKind.order,
      title: switch (o.status) {
        orderGiven => 'Buyurtma berildi',
        orderCanceled => 'Buyurtma bekor qilindi',
        _ => 'Buyurtma kutilmoqda',
      },
      body: '${o.productName} × ${o.qty} — ${fmtSum(o.total)} so‘m',
      at: at,
    ));
  }

  return sortFeed(items);
}

/// Trener uchun bildirishnomalar
List<FeedItem> trainerFeed({
  required AppUser trainer,
  required List<AppUser> clients,
  Map<String, List<ChatMessage>> messages = const {},
  List<ShopOrder> orders = const [],
  List<Gym> gyms = const [],
  DateTime? now,
}) {
  final n = now ?? DateTime.now();
  final items = <FeedItem>[];
  final nameOf = {
    for (final c in clients) c.id: c.name.isEmpty ? 'Shogird' : c.name,
  };

  // 1. Shogirdlardan kelgan xabarlar
  for (final e in messages.entries) {
    for (final m in e.value) {
      if (m.senderId != e.key) continue;
      items.add(FeedItem(
        kind: FeedKind.chat,
        title: nameOf[e.key] ?? 'Shogird',
        body: m.text,
        at: m.createdAt,
      ));
    }
  }

  // 2. Buyurtmalar — yangisi amal talab qiladi
  for (final o in orders) {
    final at = o.createdAt;
    if (at == null) continue;
    items.add(FeedItem(
      kind: FeedKind.order,
      title: o.isNew ? 'Yangi buyurtma' : 'Buyurtma: ${o.statusLabel.toLowerCase()}',
      body: '${o.clientName.isEmpty ? 'Shogird' : o.clientName} · '
          '${o.productName} × ${o.qty}',
      at: at,
      action: o.isNew,
    ));
  }

  // 3. E'tibor: rejasiz shogirdlar
  for (final c in clients) {
    if (c.planId != null) continue;
    items.add(FeedItem(
      kind: FeedKind.attention,
      title: 'Reja berilmagan',
      body: '${nameOf[c.id]} — hali ovqatlanish rejasi yo‘q',
      at: n,
      action: true,
    ));
  }

  // 4. E'tibor: zal kunlarini tanlamagan shogirdlar
  for (final c in clients) {
    if (validGymDays(c.gymDays)) continue;
    items.add(FeedItem(
      kind: FeedKind.gym,
      title: 'Zal kunlari tanlanmagan',
      body: '${nameOf[c.id]} — mashg‘ulot kunlarini tanlamagan',
      at: n.subtract(const Duration(seconds: 1)),
      action: true,
    ));
  }

  return sortFeed(items);
}

/// Barmen uchun — faqat do'kon buyurtmalari
List<FeedItem> barmenFeed({List<ShopOrder> orders = const []}) {
  final items = <FeedItem>[];
  for (final o in orders) {
    final at = o.createdAt;
    if (at == null) continue;
    items.add(FeedItem(
      kind: FeedKind.order,
      title: o.isNew ? 'Yangi buyurtma' : 'Buyurtma: ${o.statusLabel.toLowerCase()}',
      body: '${o.clientName.isEmpty ? 'Shogird' : o.clientName} · '
          '${o.productName} × ${o.qty} — ${fmtSum(o.total)} so‘m',
      at: at,
      action: o.isNew,
    ));
  }
  return sortFeed(items);
}

/// Yangi (ko'rilmagan) bildirishnomalar soni
int unreadCount(List<FeedItem> items, DateTime? lastSeen) {
  if (lastSeen == null) return items.length;
  return items.where((i) => i.at.isAfter(lastSeen)).length;
}
