import 'package:cloud_firestore/cloud_firestore.dart';

/// Zal do'koni: forma, suv idishlari, anjomlar va dobavkalar (protein, kreatin ...).
/// Tovarlarni trener kiritadi, shogird ko'radi va buyurtma beradi.
/// To'lov ilovada emas — shogird zalga kelganda naqd to'laydi.

/// Dobavkalar ichidagi kichik bo'limlar (sport pitaniya turlari).
const supplementCategories = [
  'Protein',
  'Gainer',
  'Kreatin',
  'L-Karnitin',
  'L-Arginin',
  'Boshqa',
];

/// Do'konning asosiy bo'limlari — shogird avval shulardan tanlaydi.
const shopGroups = ['Forma', 'Suv idishlari', 'Anjomlar', 'Dobavkalar'];

/// Tovar bo'limlari — bazada aynan shu nomlar saqlanadi.
/// Tartibi shogirdga ham shu ko'rinishda chiqadi.
const shopCategories = ['Forma', 'Suv idishlari', 'Anjomlar', ...supplementCategories];

/// Tovar qaysi asosiy bo'limga kiradi: `Protein` -> `Dobavkalar`.
String shopGroupOf(String category) =>
    supplementCategories.contains(category) ? 'Dobavkalar' : category;

/// Valyutalar: so'm (asosiy) va dollar (chetdan keltirilgan tovarlar uchun)
const uzs = 'UZS';
const usd = 'USD';
const currencies = [uzs, usd];

/// Valyuta belgisi: "so'm" / "$"
String currencyLabel(String c) => c == usd ? '\$' : "so'm";

/// Pulni to'liq yozish: (450000, UZS) -> "450 000 so'm"; (35, USD) -> "35 \$"
String fmtMoney(int amount, [String currency = uzs]) =>
    '${fmtSum(amount)} ${currencyLabel(currency)}';

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

  /// Asosiy rasm havolasi (ixtiyoriy) — bo'sh bo'lsa bo'lim ikonkasi chiqadi
  final String image;

  /// Qo'shimcha rasmlar (rang variantlari va h.k.). Birinchisi — [image].
  final List<String> images;

  /// Mavjud o'lchamlar: XL, XXL, 3XL … Bo'sh bo'lsa o'lcham so'ralmaydi.
  final List<String> sizes;

  /// Narx — butun son, [currency] valyutasida
  final int price;

  /// Narx valyutasi: `UZS` (so'm) yoki `USD` (dollar)
  final String currency;

  /// Zaldagi qoldiq (jamlangan — [sizes] bo'lsa [sizeStock] yig'indisi). 0 bo'lsa buyurtma
  /// tugmasi ochilmaydi. [sizes] bo'sh tovarlarda bu qiymat to'g'ridan-to'g'ri tahrirlanadi.
  final int stock;

  /// O'lcham bo'yicha qoldiq ([sizes] dagi nomlar bilan kalitlangan). [sizes] bo'sh bo'lgan
  /// tovarlarda ishlatilmaydi — ular [stock] dan to'g'ridan-to'g'ri foydalanadi.
  final Map<String, int> sizeStock;

  /// Tan narx (yetkazib beruvchidan) — ustama hisoblash uchun, ixtiyoriy (0 — kiritilmagan).
  final int costPrice;

  /// false — vaqtincha sotuvda yo'q, shogirdga ko'rinmaydi
  final bool active;

  const Product({
    this.id = '',
    required this.category,
    required this.name,
    this.note = '',
    this.image = '',
    this.images = const [],
    this.sizes = const [],
    this.price = 0,
    this.currency = uzs,
    this.stock = 0,
    this.sizeStock = const {},
    this.costPrice = 0,
    this.active = true,
  });

  /// Ko'rsatiladigan hamma rasm (asosiysi birinchi, takrorlanmaydi)
  List<String> get gallery {
    final all = <String>[if (image.trim().isNotEmpty) image.trim()];
    for (final u in images) {
      final t = u.trim();
      if (t.isNotEmpty && !all.contains(t)) all.add(t);
    }
    return all;
  }

  /// Jami qoldiq — [sizes] bo'lsa [sizeStock] yig'indisi, bo'lmasa [stock].
  int get totalStock => sizes.isEmpty ? stock : sizeStock.values.fold(0, (a, b) => a + b);

  /// Berilgan o'lchamdagi qoldiq ([sizes] bo'sh bo'lsa — [stock], o'lcham ko'rsatilmasa — 0).
  int stockFor(String? size) =>
      sizes.isEmpty ? stock : (size == null ? 0 : (sizeStock[size] ?? 0));

  /// Shogirdga ko'rinadimi va buyurtma berish mumkinmi
  bool get onSale => active && totalStock > 0 && price > 0;

  /// Narx yozuvi: "450 000 so'm" yoki "35 \$"
  String get priceText => fmtMoney(price, currency);

  /// Foyda ([costPrice] kiritilmagan bo'lsa 0 — hali hisoblanmagan)
  int get margin => costPrice > 0 ? price - costPrice : 0;

  factory Product.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return Product(
      id: doc.id,
      category: (d['category'] ?? '') as String,
      name: (d['name'] ?? '') as String,
      note: (d['note'] ?? '') as String,
      image: (d['image'] ?? '') as String,
      images: List<String>.from(d['images'] ?? const []),
      sizes: List<String>.from(d['sizes'] ?? const []),
      price: ((d['price'] ?? 0) as num).toInt(),
      currency: (d['currency'] ?? uzs) as String,
      stock: ((d['stock'] ?? 0) as num).toInt(),
      sizeStock: Map<String, int>.from(
        (d['sizeStock'] as Map? ?? const {})
            .map((k, v) => MapEntry(k as String, (v as num).toInt())),
      ),
      costPrice: ((d['costPrice'] ?? 0) as num).toInt(),
      active: (d['active'] ?? true) as bool,
    );
  }

  Map<String, dynamic> toMap() => {
        'category': category,
        'name': name,
        'note': note,
        'image': image,
        'images': images,
        'sizes': sizes,
        'price': price,
        'currency': currency,
        'stock': totalStock,
        'sizeStock': sizeStock,
        'costPrice': costPrice,
        'active': active,
      };

  Product copyWith({int? stock, Map<String, int>? sizeStock}) => Product(
        id: id,
        category: category,
        name: name,
        note: note,
        image: image,
        images: images,
        sizes: sizes,
        price: price,
        currency: currency,
        stock: stock ?? this.stock,
        sizeStock: sizeStock ?? this.sizeStock,
        costPrice: costPrice,
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

  /// Tanlangan o'lcham (bo'sh — tovarda o'lcham yo'q)
  final String size;
  final int price, qty;

  /// Narx valyutasi (buyurtma berilgan paytdagi)
  final String currency;
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
    this.size = '',
    required this.price,
    this.currency = uzs,
    this.qty = 1,
    this.status = orderNew,
    this.createdAt,
    this.givenBy = '',
    this.givenAt,
  });

  int get total => price * qty;

  /// Jami summa yozuvi: "900 000 so'm" yoki "70 \$"
  String get totalText => fmtMoney(total, currency);

  bool get isNew => status == orderNew;
  bool get isGiven => status == orderGiven;

  String get statusLabel => switch (status) {
        orderGiven => 'Berildi',
        orderCanceled => 'Bekor qilindi',
        _ => 'Kutilmoqda',
      };

  /// Nomi o'lchami bilan: "Venum komplekt (XL)"
  String get title => size.isEmpty ? productName : '$productName ($size)';

  /// Chatga yoziladigan matn — trener xabarnoma sifatida ko'radi
  String get chatText => '🛒 Buyurtma: $title × $qty — $totalText';

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
      size: (d['size'] ?? '') as String,
      price: ((d['price'] ?? 0) as num).toInt(),
      currency: (d['currency'] ?? uzs) as String,
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
  /// Jami summa — valyutalar aralash bo'lsa ma'nosiz bo'ladi, shuning uchun
  /// ko'rsatishda [money] ishlatiladi ([sums] valyuta bo'yicha ajratilgan).
  final int sum, count;

  /// Valyuta -> summa
  final Map<String, int> sums;

  const SalesReport(this.sum, this.count, [this.sums = const {}]);

  /// Ko'rsatish uchun: "450 000 so'm · 70 \$"
  String get money => sums.isEmpty
      ? fmtMoney(sum)
      : sums.entries.map((e) => fmtMoney(e.value, e.key)).join(' · ');

  static Map<String, int> _sums(List<ShopOrder> list) {
    final r = <String, int>{};
    for (final o in list) {
      r[o.currency] = (r[o.currency] ?? 0) + o.total;
    }
    return r;
  }

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
    return SalesReport(list.fold(0, (s, o) => s + o.total), list.length, _sums(list));
  }

  /// Sotuvchi (barmen/trener) bo'yicha: uid -> (summa, soni)
  static Map<String, SalesReport> bySeller(
    List<ShopOrder> orders, {
    int days = 0,
    DateTime? now,
  }) {
    final groups = <String, List<ShopOrder>>{};
    for (final o in sold(orders, days: days, now: now)) {
      groups.putIfAbsent(o.givenBy, () => []).add(o);
    }
    return {
      for (final e in groups.entries)
        e.key: SalesReport(
          e.value.fold(0, (s, o) => s + o.total),
          e.value.length,
          _sums(e.value),
        ),
    };
  }

  /// Tovar bo'yicha: nomi -> (summa, soni)
  static Map<String, SalesReport> byProduct(
    List<ShopOrder> orders, {
    int days = 0,
    DateTime? now,
  }) {
    final groups = <String, List<ShopOrder>>{};
    for (final o in sold(orders, days: days, now: now)) {
      groups.putIfAbsent(o.productName, () => []).add(o);
    }
    return {
      for (final e in groups.entries)
        e.key: SalesReport(
          e.value.fold(0, (s, o) => s + o.total),
          e.value.fold(0, (s, o) => s + o.qty),
          _sums(e.value),
        ),
    };
  }
}
