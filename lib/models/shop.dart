import 'package:cloud_firestore/cloud_firestore.dart';

/// Zal do'koni: forma, anjomlar va sport pitaniya (protein, kreatin ...).
/// Tovarlarni trener kiritadi, shogird ko'radi va buyurtma beradi.
/// To'lov ilovada emas — shogird zalga kelganda naqd to'laydi.

/// Do'kon bo'limlari. Tartibi shogirdga ham shu ko'rinishda chiqadi.
const shopCategories = ['Forma', 'Anjomlar', 'Sport pitaniya'];

/// Narxni o'qishli qilish: 450000 -> "450 000"
String fmtSum(int v) {
  final s = v.abs().toString();
  final b = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}

/// `shop/{id}` — sotuvdagi tovar
class Product {
  final String id;

  /// [shopCategories] dan biri
  final String category;
  final String name;

  /// Qisqa izoh: ta'mi, hajmi, o'lchami
  final String note;

  /// Rasm havolasi (ixtiyoriy) — bo'sh bo'lsa bo'lim ikonkasi chiqadi
  final String image;

  /// Narx — so'mda, butun son
  final int price;

  /// Zaldagi qoldiq. 0 bo'lsa buyurtma tugmasi ochilmaydi.
  final int stock;

  /// false — vaqtincha sotuvda yo'q, shogirdga ko'rinmaydi
  final bool active;

  const Product({
    this.id = '',
    required this.category,
    required this.name,
    this.note = '',
    this.image = '',
    this.price = 0,
    this.stock = 0,
    this.active = true,
  });

  /// Shogirdga ko'rinadimi va buyurtma berish mumkinmi
  bool get onSale => active && stock > 0 && price > 0;

  factory Product.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return Product(
      id: doc.id,
      category: (d['category'] ?? '') as String,
      name: (d['name'] ?? '') as String,
      note: (d['note'] ?? '') as String,
      image: (d['image'] ?? '') as String,
      price: ((d['price'] ?? 0) as num).toInt(),
      stock: ((d['stock'] ?? 0) as num).toInt(),
      active: (d['active'] ?? true) as bool,
    );
  }

  Map<String, dynamic> toMap() => {
        'category': category,
        'name': name,
        'note': note,
        'image': image,
        'price': price,
        'stock': stock,
        'active': active,
      };

  Product copyWith({int? stock}) => Product(
        id: id,
        category: category,
        name: name,
        note: note,
        image: image,
        price: price,
        stock: stock ?? this.stock,
        active: active,
      );
}

/// Buyurtma holatlari
const orderNew = 'new'; // shogird so'radi, trener hali bermagan
const orderGiven = 'given'; // zalda berildi va to'lov olindi
const orderCanceled = 'canceled'; // bekor qilindi

/// `orders/{id}` — shogirdning bitta tovarga buyurtmasi
class ShopOrder {
  final String id;
  final String clientId, clientName, clientPhone;

  /// Shogirdning treneri (bo'sh — trener tanlanmagan, buyurtmani bosh admin ko'radi)
  final String trainerId;
  final String productId, productName, category;
  final int price, qty;
  final String status;
  final DateTime? createdAt;

  /// Kim berdi (trener yoki barmen uid) va qachon — sotuv hisoboti shunga tayanadi
  final String givenBy;
  final DateTime? givenAt;

  const ShopOrder({
    this.id = '',
    required this.clientId,
    this.clientName = '',
    this.clientPhone = '',
    this.trainerId = '',
    required this.productId,
    required this.productName,
    this.category = '',
    required this.price,
    this.qty = 1,
    this.status = orderNew,
    this.createdAt,
    this.givenBy = '',
    this.givenAt,
  });

  int get total => price * qty;

  bool get isNew => status == orderNew;
  bool get isGiven => status == orderGiven;

  String get statusLabel => switch (status) {
        orderGiven => 'Berildi',
        orderCanceled => 'Bekor qilindi',
        _ => 'Kutilmoqda',
      };

  /// Chatga yoziladigan matn — trener xabarnoma sifatida ko'radi
  String get chatText => '🛒 Buyurtma: $productName × $qty — ${fmtSum(total)} so\'m';

  factory ShopOrder.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return ShopOrder(
      id: doc.id,
      clientId: (d['clientId'] ?? '') as String,
      clientName: (d['clientName'] ?? '') as String,
      clientPhone: (d['clientPhone'] ?? '') as String,
      trainerId: (d['trainerId'] ?? '') as String,
      productId: (d['productId'] ?? '') as String,
      productName: (d['productName'] ?? '') as String,
      category: (d['category'] ?? '') as String,
      price: ((d['price'] ?? 0) as num).toInt(),
      qty: ((d['qty'] ?? 1) as num).toInt(),
      status: (d['status'] ?? orderNew) as String,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      givenBy: (d['givenBy'] ?? '') as String,
      givenAt: (d['givenAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// Sotuv hisoboti: berilgan buyurtmalar bo'yicha summa va soni
class SalesReport {
  final int sum, count;
  const SalesReport(this.sum, this.count);

  /// Hisobga olinadigan sana: berilgan vaqt, bo'lmasa buyurtma vaqti
  static DateTime? soldAt(ShopOrder o) => o.givenAt ?? o.createdAt;

  /// Shu davrga kiradigan, berilgan buyurtmalar (0 — hamma vaqt)
  static List<ShopOrder> sold(List<ShopOrder> orders, {int days = 0, DateTime? now}) {
    final n = now ?? DateTime.now();
    return orders.where((o) {
      if (!o.isGiven) return false;
      if (days <= 0) return true;
      final at = soldAt(o);
      return at != null && n.difference(at).inDays < days;
    }).toList();
  }

  /// [days] kun ichida berilgan buyurtmalar (0 — hammasi)
  factory SalesReport.of(List<ShopOrder> orders, {int days = 0, DateTime? now}) {
    final list = sold(orders, days: days, now: now);
    return SalesReport(list.fold(0, (s, o) => s + o.total), list.length);
  }

  /// Sotuvchi (barmen/trener) bo'yicha: uid -> (summa, soni)
  static Map<String, SalesReport> bySeller(
    List<ShopOrder> orders, {
    int days = 0,
    DateTime? now,
  }) {
    final r = <String, SalesReport>{};
    for (final o in sold(orders, days: days, now: now)) {
      final key = o.givenBy.isEmpty ? '' : o.givenBy;
      final old = r[key] ?? const SalesReport(0, 0);
      r[key] = SalesReport(old.sum + o.total, old.count + 1);
    }
    return r;
  }

  /// Tovar bo'yicha: nomi -> (summa, soni)
  static Map<String, SalesReport> byProduct(
    List<ShopOrder> orders, {
    int days = 0,
    DateTime? now,
  }) {
    final r = <String, SalesReport>{};
    for (final o in sold(orders, days: days, now: now)) {
      final old = r[o.productName] ?? const SalesReport(0, 0);
      r[o.productName] = SalesReport(old.sum + o.total, old.count + o.qty);
    }
    return r;
  }
}
