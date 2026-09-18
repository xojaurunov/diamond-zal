import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../models/shop.dart';
import '../../services/db.dart';
import '../../theme.dart';
import '../../widgets/product_image.dart';
import '../../widgets/ui.dart';

/// Sotuv hisoboti — zal egasi uchun: kim nechta sotdi, qancha pul, qaysi tovar.
/// Barmen ham shu ekranni ko'radi, lekin faqat o'z sotuvini (ownerView: false).
class SalesReportScreen extends StatefulWidget {
  final AppUser me;

  /// true — hamma sotuvchi kesimida (zal egasi); false — faqat o'zi (barmen)
  final bool ownerView;
  const SalesReportScreen({super.key, required this.me, this.ownerView = true});

  @override
  State<SalesReportScreen> createState() => _SalesReportScreenState();
}

class _SalesReportScreenState extends State<SalesReportScreen> {
  static const _periods = [('Bugun', 1), ('7 kun', 7), ('30 kun', 30), ('Hammasi', 0)];
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Sotuv hisoboti')),
      body: StreamBuilder<List<ShopOrder>>(
        stream: Db.allOrders(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final all = snap.data!;
          final orders = widget.ownerView
              ? all
              : all.where((o) => o.givenBy == widget.me.id).toList();

          final total = SalesReport.of(orders, days: _days);
          final sellers = SalesReport.bySeller(orders, days: _days);
          final products = SalesReport.byProduct(orders, days: _days);
          final sold = SalesReport.sold(orders, days: _days);

          return StreamBuilder<List<AppUser>>(
            stream: Db.staff(),
            builder: (context, staffSnap) {
              final names = {
                for (final s in staffSnap.data ?? const <AppUser>[])
                  s.id: s.name.isEmpty ? fmtPhone(s.phone) : s.name,
              };

              return ListView(
                padding: const EdgeInsets.fromLTRB(
                    AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.xxl),
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final (label, days) in _periods)
                        Padding(
                          padding: const EdgeInsets.only(right: AppSpace.sm),
                          child: ChoiceChip(
                            selected: _days == days,
                            onSelected: (_) => setState(() => _days = days),
                            label: Text(label),
                          ),
                        ),
                    ]),
                  ),
                  const SizedBox(height: AppSpace.md),

                  // ---------- jami ----------
                  BentoTile(
                    feature: true,
                    padding: const EdgeInsets.all(AppSpace.lg),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Eyebrow(widget.ownerView ? 'Jami tushum' : 'Men sotdim'),
                      const SizedBox(height: AppSpace.xs),
                      Text("${fmtSum(total.sum)} so'm",
                          style: t.headlineMedium?.copyWith(color: AppColors.accent)),
                      const SizedBox(height: 2),
                      Text('${total.count} ta buyurtma berildi',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    ]),
                  ),

                  // ---------- sotuvchilar ----------
                  if (widget.ownerView) ...[
                    const SizedBox(height: AppSpace.xl),
                    const SectionHeader('Kim sotdi', eyebrow: 'Hisobot'),
                    if (sellers.isEmpty)
                      Text('Bu davrda sotuv bo‘lmagan',
                          style: TextStyle(color: AppColors.textMuted)),
                    for (final e in (sellers.entries.toList()
                      ..sort((a, b) => b.value.sum.compareTo(a.value.sum))))
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpace.sm),
                        child: BentoTile(
                          padding: const EdgeInsets.all(AppSpace.md),
                          child: Row(children: [
                            UserAvatar(name: names[e.key] ?? 'Noma’lum', size: 38),
                            const SizedBox(width: AppSpace.md),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      e.key.isEmpty
                                          ? 'Kim bergani yozilmagan'
                                          : (names[e.key] ?? 'Xodim'),
                                      style: t.titleSmall,
                                    ),
                                    Text('${e.value.count} ta buyurtma',
                                        style: t.bodySmall
                                            ?.copyWith(color: AppColors.textMuted)),
                                  ]),
                            ),
                            Text("${fmtSum(e.value.sum)} so'm",
                                style: t.titleSmall?.copyWith(color: AppColors.accent)),
                          ]),
                        ),
                      ),
                  ],

                  // ---------- tovarlar ----------
                  const SizedBox(height: AppSpace.xl),
                  const SectionHeader('Qaysi tovar', eyebrow: 'Sotilgani'),
                  if (products.isEmpty)
                    Text('Bu davrda sotuv bo‘lmagan',
                        style: TextStyle(color: AppColors.textMuted)),
                  for (final e in (products.entries.toList()
                    ..sort((a, b) => b.value.sum.compareTo(a.value.sum))))
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.sm),
                      child: BentoTile(
                        padding: const EdgeInsets.all(AppSpace.md),
                        child: Row(children: [
                          ProductImage(category: '', name: e.key, size: 38),
                          const SizedBox(width: AppSpace.md),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(e.key,
                                      style: t.titleSmall,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  Text('${e.value.count} dona',
                                      style:
                                          t.bodySmall?.copyWith(color: AppColors.textMuted)),
                                ]),
                          ),
                          Text("${fmtSum(e.value.sum)} so'm",
                              style: t.titleSmall?.copyWith(color: AppColors.accent)),
                        ]),
                      ),
                    ),

                  // ---------- ro'yxat ----------
                  const SizedBox(height: AppSpace.xl),
                  SectionHeader('Har bir sotuv', eyebrow: '${sold.length} ta'),
                  for (final o in sold)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.xs),
                      child: Row(children: [
                        Expanded(
                          child: Text('${o.productName} × ${o.qty}',
                              style: t.bodyMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: AppSpace.sm),
                        Text(
                          SalesReport.soldAt(o) == null
                              ? ''
                              : uzDate(SalesReport.soldAt(o)!),
                          style: TextStyle(color: AppColors.textFaint, fontSize: 11.5),
                        ),
                        const SizedBox(width: AppSpace.sm),
                        Text("${fmtSum(o.total)} so'm",
                            style: t.bodySmall?.copyWith(fontFeatures: tabular)),
                      ]),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
