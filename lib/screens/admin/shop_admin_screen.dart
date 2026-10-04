import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../models/shop.dart';
import '../../services/db.dart';
import '../../theme.dart';
import '../../widgets/product_image.dart';
import '../../widgets/ui.dart';

/// Trener (va bosh admin) uchun do'kon: buyurtmalar va tovarlar.
/// Trener faqat O'Z shogirdlarining buyurtmalarini ko'radi, bosh admin — hammasini.
class ShopAdminScreen extends StatefulWidget {
  final AppUser admin;
  const ShopAdminScreen({super.key, required this.admin});

  @override
  State<ShopAdminScreen> createState() => _ShopAdminScreenState();
}

class _ShopAdminScreenState extends State<ShopAdminScreen> {
  // bosh admin va barmen — hamma buyurtma; trener — faqat o'z shogirdlariniki
  late final _orders = widget.admin.isOwner || widget.admin.isBarmen
      ? Db.allOrders()
      : Db.ordersOf(widget.admin.id);
  late final _products = Db.products();
  int _tab = 0;

  Future<void> _setStatus(ShopOrder o, String status) async {
    if (status == orderCanceled) {
      final ok = await confirm(
        context,
        title: 'Buyurtmani bekor qilish',
        message: '${o.clientName}: "${o.productName}" × ${o.qty} bekor qilinsinmi?',
        ok: 'Bekor qilish',
        destructive: true,
      );
      if (!ok) return;
    }
    try {
      await Db.setOrderStatus(o, status, widget.admin.id);
      if (mounted) {
        showSnack(context, status == orderGiven ? 'Berildi deb belgilandi' : 'Bekor qilindi');
      }
    } catch (e) {
      if (mounted) showSnack(context, "Bo'lmadi: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: _tab == 1
          ? FloatingActionButton.extended(
              onPressed: () => editProduct(context),
              icon: const Icon(Icons.add),
              label: const Text('Tovar'),
            )
          : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xs, AppSpace.lg, AppSpace.sm),
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, label: Text('Buyurtmalar')),
              ButtonSegment(value: 1, label: Text('Tovarlar')),
            ],
            selected: {_tab},
            onSelectionChanged: (s) => setState(() => _tab = s.first),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: [
              _OrdersTab(stream: _orders, onStatus: _setStatus),
              _ProductsTab(stream: _products),
            ],
          ),
        ),
      ]),
    );
  }
}

class _OrdersTab extends StatelessWidget {
  final Stream<List<ShopOrder>> stream;
  final Future<void> Function(ShopOrder, String) onStatus;
  const _OrdersTab({required this.stream, required this.onStatus});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return StreamBuilder<List<ShopOrder>>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final orders = snap.data!;
        if (orders.isEmpty) {
          return const EmptyState(
            icon: Icons.receipt_long_outlined,
            title: "Buyurtma yo'q",
            subtitle: "Shogird do'kondan tovar so'rasa, shu yerda chiqadi va chatga xabar keladi.",
          );
        }
        final waiting = orders.where((o) => o.isNew).toList();
        final done = orders.where((o) => !o.isNew).toList();
        final month = SalesReport.of(orders, days: 30);

        return ListView(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.xxl),
          children: [
            BentoTile(
              feature: true,
              child: Row(children: [
                IconBadge(Icons.payments_outlined, color: AppColors.success),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('30 kunda: ${month.money}', style: t.titleMedium),
                    Text('${month.count} ta buyurtma berildi',
                        style: t.bodySmall?.copyWith(color: AppColors.textMuted)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: AppSpace.md),
            SectionHeader('Kutilmoqda',
                trailing: Pill(text: '${waiting.length}', color: AppColors.warning)),
            if (waiting.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm, left: 4),
                child: Text('Yangi buyurtma yo\'q', style: TextStyle(color: AppColors.textMuted)),
              ),
            for (final o in waiting)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: _OrderTile(order: o, onStatus: onStatus),
              ),
            if (done.isNotEmpty) ...[
              const SizedBox(height: AppSpace.lg),
              const SectionHeader('Tarix'),
              for (final o in done.take(30))
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.sm),
                  child: _OrderTile(order: o, onStatus: onStatus),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _OrderTile extends StatelessWidget {
  final ShopOrder order;
  final Future<void> Function(ShopOrder, String) onStatus;
  const _OrderTile({required this.order, required this.onStatus});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final o = order;
    final who = o.clientName.isEmpty ? fmtPhone(o.clientPhone) : o.clientName;
    return BentoTile(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          ProductImage(category: o.category, name: o.productName, size: 42),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${o.title} × ${o.qty}', style: t.titleSmall),
              Text(
                '$who${o.createdAt == null ? '' : ' • ${uzDate(o.createdAt!)}'}',
                style: t.bodySmall?.copyWith(color: AppColors.textMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(o.totalText, style: t.titleSmall),
            if (!o.isNew)
              Pill(
                text: o.statusLabel,
                color: o.isGiven ? AppColors.success : AppColors.textFaint,
              ),
          ]),
        ]),
        if (o.isNew) ...[
          const SizedBox(height: AppSpace.sm),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
                onPressed: () => onStatus(o, orderGiven),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Berildi'),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
              onPressed: () => onStatus(o, orderCanceled),
              child: const Text('Bekor'),
            ),
          ]),
        ],
      ]),
    );
  }
}

class _ProductsTab extends StatelessWidget {
  final Stream<List<Product>> stream;
  const _ProductsTab({required this.stream});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return StreamBuilder<List<Product>>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final all = snap.data!;
        if (all.isEmpty) {
          return EmptyState(
            icon: Icons.storefront_outlined,
            title: "Do'kon bo'sh",
            subtitle: 'Forma, suv idishlari, anjomlar va dobavkalar shu yerga kiritiladi. '
                "Shogird narxini ko'radi va buyurtma beradi, to'lov zalda naqd.",
            action: FilledButton.icon(
              onPressed: () => editProduct(context),
              icon: const Icon(Icons.add),
              label: const Text("Birinchi tovarni qo'shish"),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, 96),
          children: [
            for (final c in shopCategories) ...[
              // Dobavkalar guruhining boshi — bitta umumiy sarlavha
              if (c == supplementCategories.first &&
                  all.any((p) => supplementCategories.contains(p.category)))
                SectionHeader(
                  'Dobavkalar',
                  trailing: Pill(
                    text: '${all.where((p) => supplementCategories.contains(p.category)).length}',
                    color: shopColor('Boshqa'),
                  ),
                ),
              if (all.any((p) => p.category == c)) ...[
                SubHeader(
                  c,
                  count: all.where((p) => p.category == c).length,
                  color: shopColor(c),
                ),
                for (final p in all.where((p) => p.category == c))
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.sm),
                    child: _ProductAdminTile(product: p),
                  ),
              ],
            ],
            // Bo'limi noto'g'ri yozilgan eski yozuvlar ko'rinmay qolmasin
            for (final p in all.where((p) => !shopCategories.contains(p.category)))
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: _ProductAdminTile(product: p),
              ),
            const SizedBox(height: AppSpace.md),
            Text(
              "Qoldiq: tovar berilganda avtomatik kamayadi. Tugasa shogird buyurtma bera olmaydi.",
              style: t.bodySmall?.copyWith(color: AppColors.textFaint),
            ),
          ],
        );
      },
    );
  }
}

class _ProductAdminTile extends StatelessWidget {
  final Product product;
  const _ProductAdminTile({required this.product});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = product;
    return BentoTile(
      padding: const EdgeInsets.all(AppSpace.md),
      onTap: () => editProduct(context, p),
      child: Row(children: [
        ProductImage(category: p.category, name: p.name, url: p.image, size: 48),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: [
              Pill(text: p.priceText, color: AppColors.accent),
              Pill(
                text: p.totalStock > 0 ? 'Qoldiq: ${p.totalStock}' : 'Tugagan',
                color: p.totalStock > 0 ? AppColors.textMuted : AppColors.danger,
              ),
              if (p.sizes.isNotEmpty)
                Pill(text: p.sizes.join(' · '), color: AppColors.water),
              if (p.margin > 0)
                Pill(text: 'Foyda: ${fmtSum(p.margin)}', color: AppColors.success),
              if (p.gallery.length > 1)
                Pill(text: '${p.gallery.length} rasm', color: AppColors.textMuted),
              if (!p.active) Pill(text: 'Sotuvda emas', color: AppColors.warning),
            ]),
          ]),
        ),
        const Icon(Icons.chevron_right),
      ]),
    );
  }
}

/// Tovar qo'shish/tahrirlash varag'i. [p] null bo'lsa — yangi tovar.
Future<void> editProduct(BuildContext context, [Product? p]) async {
  final name = TextEditingController(text: p?.name);
  final note = TextEditingController(text: p?.note);
  final price = TextEditingController(text: p == null || p.price == 0 ? '' : '${p.price}');
  final stock = TextEditingController(text: '${p?.stock ?? 1}');
  final costPrice =
      TextEditingController(text: p == null || p.costPrice == 0 ? '' : '${p.costPrice}');
  final image = TextEditingController(text: p?.gallery.join('\n'));
  final sizes = TextEditingController(text: p?.sizes.join(', '));
  final sizeStockControllers = <String, TextEditingController>{};
  TextEditingController sizeStockCtrl(String sz) => sizeStockControllers.putIfAbsent(
      sz, () => TextEditingController(text: '${p?.sizeStock[sz] ?? 0}'));
  var category = p?.category ?? shopCategories.first;
  var currency = p?.currency ?? uzs;
  var active = p?.active ?? true;
  int n(TextEditingController c) => int.tryParse(c.text.replaceAll(RegExp(r'\D'), '')) ?? 0;

  final saved = await showSheet<bool>(
    context,
    StatefulBuilder(
      builder: (ctx, setS) => SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: AppSpace.md),
          Row(children: [
            ProductImage(
              category: category,
              name: name.text,
              url: image.text.split(RegExp(r'[\n,]')).first.trim(),
              size: 52,
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Text(p == null ? "Yangi tovar" : 'Tovarni tahrirlash',
                  style: Theme.of(ctx).textTheme.titleLarge),
            ),
          ]),
          const SizedBox(height: AppSpace.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: AppSpace.sm, children: [
              for (final c in shopCategories)
                ChoiceChip(
                  selected: category == c,
                  onSelected: (_) => setS(() => category = c),
                  avatar: Icon(shopIcon(c), size: 16),
                  label: Text(c),
                ),
            ]),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: name,
            autofocus: p == null,
            textCapitalization: TextCapitalization.sentences,
            // nom yozilganda yuqoridagi rasm ham yangilanadi (protein, gainer ...)
            onChanged: (_) => setS(() {}),
            decoration: const InputDecoration(
                labelText: 'Nomi', hintText: 'Protein izolyat 900 g (shokolad)'),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: note,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Izoh (ixtiyoriy)',
              hintText: "O'lchami, ta'mi, ishlab chiqaruvchi",
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Row(children: [
            Expanded(
              child: TextField(
                controller: price,
                keyboardType: TextInputType.number,
                onChanged: (_) => setS(() {}),
                decoration: InputDecoration(
                  labelText: 'Narxi',
                  suffixText: currencyLabel(currency),
                ),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: TextField(
                controller: costPrice,
                keyboardType: TextInputType.number,
                onChanged: (_) => setS(() {}),
                decoration: const InputDecoration(labelText: 'Tan narxi (ixtiyoriy)'),
              ),
            ),
          ]),
          if (n(costPrice) > 0) ...[
            const SizedBox(height: AppSpace.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Foyda: ${fmtSum(n(price) - n(costPrice))} ${currencyLabel(currency)}',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
              ),
            ),
          ],
          const SizedBox(height: AppSpace.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: AppSpace.sm, children: [
              for (final c in currencies)
                ChoiceChip(
                  selected: currency == c,
                  onSelected: (_) => setS(() => currency = c),
                  label: Text(c == usd ? 'Dollar (\$)' : "So'm"),
                ),
            ]),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: image,
            keyboardType: TextInputType.url,
            minLines: 1,
            maxLines: 4,
            onChanged: (_) => setS(() {}),
            decoration: const InputDecoration(
              labelText: 'Rasm havolalari (ixtiyoriy)',
              hintText: 'https://...',
              helperText: 'Bir nechta bo\'lsa — har birini yangi qatorga yozing',
            ),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: sizes,
            onChanged: (_) => setS(() {}),
            decoration: const InputDecoration(
              labelText: "O'lchamlar (ixtiyoriy)",
              hintText: 'XL, XXL, 3XL, 4XL',
              helperText: "Vergul bilan. Yozilsa — shogird buyurtmada o'lchamni tanlaydi",
            ),
          ),
          const SizedBox(height: AppSpace.md),
          if (sizes.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).isEmpty)
            TextField(
              controller: stock,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Qoldiq', suffixText: 'dona'),
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("Qoldiq (o'lcham bo'yicha)",
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                const SizedBox(height: AppSpace.xs),
                Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
                  for (final sz in sizes.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty))
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: sizeStockCtrl(sz),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: sz),
                      ),
                    ),
                ]),
              ]),
            ),
          const SizedBox(height: AppSpace.md),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: active,
            onChanged: (v) => setS(() => active = v),
            title: const Text('Sotuvda'),
            subtitle: Text(
              active ? "Shogirdlar ko'radi" : "Shogirdlarga ko'rinmaydi",
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Saqlash'),
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          if (p != null)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                onPressed: () => Navigator.pop(ctx, false),
                icon: const Icon(Icons.delete_outline),
                label: const Text("O'chirish"),
              ),
            ),
          const SizedBox(height: AppSpace.sm),
        ]),
      ),
    ),
  );

  if (saved == true) {
    if (name.text.trim().isEmpty) return;
    final urls = image.text
        .split(RegExp(r'[\n,]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final sizeList =
        sizes.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    await Db.saveProduct(Product(
      id: p?.id ?? '',
      category: category,
      name: name.text.trim(),
      note: note.text.trim(),
      image: urls.isEmpty ? '' : urls.first,
      images: urls.length > 1 ? urls.sublist(1) : const [],
      sizes: sizeList,
      price: n(price),
      currency: currency,
      stock: n(stock),
      sizeStock: {for (final sz in sizeList) sz: n(sizeStockCtrl(sz))},
      costPrice: n(costPrice),
      active: active,
    ));
  } else if (saved == false && p != null && context.mounted) {
    final ok = await confirm(
      context,
      title: "Tovarni o'chirish",
      message: '"${p.name}" do\'kondan o\'chirilsinmi?',
      ok: "O'chirish",
      destructive: true,
    );
    if (ok) await Db.deleteProduct(p.id);
  }
}
