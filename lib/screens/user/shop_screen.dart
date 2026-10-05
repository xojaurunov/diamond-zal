import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../models/shop.dart';
import '../../services/db.dart';
import '../../theme.dart';
import '../../widgets/product_image.dart';
import '../../widgets/ui.dart';

/// Shogird uchun do'kon: forma, suv idishlari, anjomlar va dobavkalar.
/// Buyurtma berilganda trenerga chatga xabar tushadi, to'lov zalda naqd.
class ShopScreen extends StatefulWidget {
  final AppUser user;
  const ShopScreen({super.key, required this.user});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  late final _products = Db.products();
  late final _orders = Db.myOrders(widget.user.id);

  /// null — hamma bo'limlar
  /// Asosiy bo'lim (`Forma` / `Anjomlar` / `Dobavkalar`), null — hammasi
  String? _group;

  /// Dobavkalar ichidagi kichik bo'lim (`Protein` ...), null — hammasi
  String? _category;

  Future<void> _order(Product p) async {
    var qty = 1;
    String? size = p.sizes.length == 1 ? p.sizes.first : null;
    String? color = p.colors.length == 1 ? p.colors.first : null;
    final ok = await showSheet<bool>(
      context,
      StatefulBuilder(
        builder: (ctx, setS) {
          final t = Theme.of(ctx).textTheme;
          final avail = p.stockFor(size);
          final max = avail < 20 ? avail : 20;
          if (qty > max && max > 0) qty = max;
          return Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: AppSpace.md),
            // rasm galereyasi — rang variantlari
            if (p.gallery.length > 1) ...[
              SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: p.gallery.length,
                  separatorBuilder: (_, __) => const SizedBox(width: AppSpace.sm),
                  itemBuilder: (_, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    child: Image.network(
                      p.gallery[i],
                      width: 150,
                      height: 150,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.md),
            ],
            Row(children: [
              ProductImage(category: p.category, name: p.name, url: p.image, size: 56),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.name, style: t.titleMedium),
                  Text(p.priceText,
                      style: t.bodyMedium?.copyWith(color: AppColors.accent)),
                ]),
              ),
            ]),
            if (p.sizes.isNotEmpty) ...[
              const SizedBox(height: AppSpace.lg),
              Align(
                alignment: Alignment.centerLeft,
                child: Text("O'lchamni tanlang",
                    style: t.bodyMedium?.copyWith(color: AppColors.textMuted)),
              ),
              const SizedBox(height: AppSpace.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
                  for (final sz in p.sizes)
                    ChoiceChip(
                      selected: size == sz,
                      onSelected: (_) => setS(() => size = sz),
                      label: Text(sz),
                    ),
                ]),
              ),
            ],
            if (p.colors.isNotEmpty) ...[
              const SizedBox(height: AppSpace.lg),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Rangni tanlang',
                    style: t.bodyMedium?.copyWith(color: AppColors.textMuted)),
              ),
              const SizedBox(height: AppSpace.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
                  for (final c in p.colors)
                    ChoiceChip(
                      selected: color == c,
                      onSelected: (_) => setS(() => color = c),
                      label: Text(c),
                    ),
                ]),
              ),
            ],
            const SizedBox(height: AppSpace.lg),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton.filledTonal(
                onPressed: qty > 1 ? () => setS(() => qty--) : null,
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 72,
                child: Text('$qty', textAlign: TextAlign.center, style: t.headlineSmall),
              ),
              IconButton.filledTonal(
                onPressed: qty < max ? () => setS(() => qty++) : null,
                icon: const Icon(Icons.add),
              ),
            ]),
            const SizedBox(height: AppSpace.md),
            Text('Jami: ${fmtMoney(p.price * qty, p.currency)}', style: t.titleLarge),
            const SizedBox(height: AppSpace.sm),
            Text(
              "To'lov zalda, naqd. Trener buyurtmani ko'radi va tayyorlab qo'yadi.",
              textAlign: TextAlign.center,
              style: t.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpace.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (p.sizes.isNotEmpty && size == null) ||
                        (p.colors.isNotEmpty && color == null) ||
                        avail <= 0
                    ? null
                    : () => Navigator.pop(ctx, true),
                child: Text(p.sizes.isNotEmpty && size == null
                    ? "Avval o'lchamni tanlang"
                    : p.colors.isNotEmpty && color == null
                        ? 'Avval rangni tanlang'
                        : avail <= 0
                            ? 'Tugagan'
                            : 'Buyurtma berish'),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Bekor qilish'),
              ),
            ),
          ]);
        },
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await Db.createOrder(widget.user, p, qty, size: size ?? '', color: color ?? '');
      if (mounted) showSnack(context, 'Buyurtma yuborildi — trener xabardor bo\'ldi');
    } catch (e) {
      if (mounted) showSnack(context, "Bo'lmadi: $e");
    }
  }

  Future<void> _cancel(ShopOrder o) async {
    final ok = await confirm(
      context,
      title: 'Buyurtmani bekor qilish',
      message: '"${o.productName}" buyurtmasi bekor qilinsinmi?',
      ok: 'Bekor qilish',
      destructive: true,
    );
    if (!ok) return;
    try {
      await Db.cancelOrder(o.id);
    } catch (e) {
      if (mounted) showSnack(context, "Bo'lmadi: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return StreamBuilder<List<Product>>(
      stream: _products,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        // Shogird faqat sotuvdagi tovarlarni ko'radi (qoldig'i tugagani ham ko'rinadi,
        // lekin tugmasi ochilmaydi — trener yana keltiradi)
        final all = snap.data!.where((p) => p.active && p.price > 0).toList();
        // Tovari bor bo'limlar; biri doim tanlangan turadi ("Hammasi" yo'q)
        final groups =
            shopGroups.where((g) => all.any((p) => shopGroupOf(p.category) == g)).toList();
        final group = groups.contains(_group) ? _group! : (groups.isEmpty ? '' : groups.first);
        final subs = group == 'Dobavkalar'
            ? supplementCategories.where((c) => all.any((p) => p.category == c)).toList()
            : const <String>[];
        final sub = subs.contains(_category) ? _category! : (subs.isEmpty ? '' : subs.first);
        final list = all
            .where((p) => shopGroupOf(p.category) == group)
            .where((p) => subs.isEmpty || p.category == sub)
            .toList();

        return StreamBuilder<List<ShopOrder>>(
          stream: _orders,
          builder: (context, oSnap) {
            final orders = oSnap.data ?? const <ShopOrder>[];
            final waiting = orders.where((o) => o.isNew).toList();

            // AppBar yo'q - ro'yxat telefon status bari ostiga kirib ketmasin
            return SafeArea(
              bottom: false,
              child: ListView(
              // tepadan bo'sh joy - bo'lim tugmalari ekran chetiga yopishib qolmasin
              padding:
                  const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.xxl),
              children: [
                if (waiting.isNotEmpty) ...[
                  SectionHeader('Mening buyurtmalarim',
                      trailing: Pill(text: '${waiting.length}', color: AppColors.warning)),
                  for (final o in waiting)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.sm),
                      child: BentoTile(
                        child: Row(children: [
                          ProductImage(category: o.category, name: o.productName, size: 44),
                          const SizedBox(width: AppSpace.md),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${o.title} × ${o.qty}', style: t.titleSmall),
                              Text(
                                '${o.totalText} • ${o.statusLabel}',
                                style: t.bodySmall?.copyWith(color: AppColors.textMuted),
                              ),
                            ]),
                          ),
                          TextButton(onPressed: () => _cancel(o), child: const Text('Bekor')),
                        ]),
                      ),
                    ),
                  const SizedBox(height: AppSpace.md),
                ],
                if (all.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpace.xxl),
                    child: EmptyState(
                      icon: Icons.storefront_outlined,
                      title: "Do'kon hozircha bo'sh",
                      subtitle: 'Trener tovarlarni kiritgach, shu yerda ko\'rinadi.',
                    ),
                  )
                else ...[
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final g in groups)
                        _CatChip(
                          label: g,
                          icon: shopIcon(g == 'Dobavkalar' ? 'Boshqa' : g),
                          selected: group == g,
                          onTap: () => setState(() {
                            _group = g;
                            _category = null;
                          }),
                        ),
                    ]),
                  ),
                  // Dobavkalar tanlansa — ichidagi kichik bo'limlar
                  if (subs.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.sm),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        for (final c in subs)
                          _CatChip(
                            label: c,
                            icon: shopIcon(c),
                            selected: sub == c,
                            onTap: () => setState(() => _category = c),
                          ),
                      ]),
                    ),
                  ],
                  const SizedBox(height: AppSpace.md),
                  Text(
                    "To'lov zalda, naqd — ilovada karta so'ralmaydi.",
                    style: t.bodySmall?.copyWith(color: AppColors.textFaint),
                  ),
                  const SizedBox(height: AppSpace.md),
                  for (final p in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.sm),
                      child: _ProductTile(product: p, onOrder: () => _order(p)),
                    ),
                ],
                if (orders.any((o) => !o.isNew)) ...[
                  const SizedBox(height: AppSpace.lg),
                  const SectionHeader('Oldingi buyurtmalar'),
                  for (final o in orders.where((o) => !o.isNew).take(10))
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.xs),
                      child: Row(children: [
                        Expanded(
                          child: Text('${o.title} × ${o.qty}',
                              style: t.bodyMedium, overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: AppSpace.sm),
                        Pill(
                          text: o.statusLabel,
                          color: o.isGiven ? AppColors.success : AppColors.textFaint,
                        ),
                      ]),
                    ),
                ],
              ],
              ),
            );
          },
        );
      },
    );
  }
}

class _CatChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  const _CatChip({required this.label, this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: AppSpace.sm),
        child: ChoiceChip(
          selected: selected,
          onSelected: (_) => onTap(),
          avatar: icon == null ? null : Icon(icon, size: 16),
          label: Text(label),
        ),
      );
}

class _ProductTile extends StatelessWidget {
  final Product product;
  final VoidCallback onOrder;
  const _ProductTile({required this.product, required this.onOrder});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = product;
    return BentoTile(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ProductImage(category: p.category, name: p.name, url: p.image, size: 60),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, style: t.titleSmall),
            if (p.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(p.note,
                    style: t.bodySmall?.copyWith(color: AppColors.textMuted),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
            const SizedBox(height: AppSpace.sm),
            if (p.sizes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text("O'lchamlar: ${p.sizes.join(' · ')}",
                    style: t.bodySmall?.copyWith(color: AppColors.water)),
              ),
            Row(children: [
              Text(p.priceText,
                  style: t.titleSmall?.copyWith(color: AppColors.accent)),
              const SizedBox(width: AppSpace.sm),
              if (p.totalStock <= 0)
                Pill(text: 'Hozir yo\'q', color: AppColors.danger)
              else if (p.totalStock <= 3)
                Pill(text: 'Qoldi: ${p.totalStock}', color: AppColors.warning),
            ]),
          ]),
        ),
        const SizedBox(width: AppSpace.sm),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: p.totalStock > 0 ? onOrder : null,
          child: const Text('Olaman'),
        ),
      ]),
    );
  }
}
