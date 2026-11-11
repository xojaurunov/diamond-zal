import 'package:flutter/material.dart';
import '../../l10n/tr.dart';
import '../../models/models.dart';
import '../../models/shop.dart' show fmtMoney;
import '../../models/subscription.dart';
import '../../services/db.dart';
import '../../theme.dart';
import '../../widgets/lazy_stack.dart';
import '../../widgets/ui.dart';
import '../payments_screen.dart';

/// Trener (va bosh admin) uchun abonement: mijozlar holati (qolgan kun, eslatma yuborish)
/// va abonement tugashi haqida yuborilgan eslatmalarning haftalik hisoboti.
class SubscriptionsScreen extends StatefulWidget {
  final AppUser admin;
  const SubscriptionsScreen({super.key, required this.admin});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  late final _clients = widget.admin.isOwner ? Db.clients() : Db.clientsOf(widget.admin.id);
  late final _reminders =
      widget.admin.isOwner ? Db.allReminders() : Db.remindersOf(widget.admin.id);
  // alohida oqim: "Mijozlar" bo'limi bilan bitta oqimni ikki marta tinglab bo'lmaydi
  late final _debtClients = widget.admin.isOwner ? Db.clients() : Db.clientsOf(widget.admin.id);
  late final _memberships = Db.memberships(widget.admin);
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // 4 bo'lim tor telefonga sig'maydi — surib ko'riladi; "Qarzdorlar" ikkinchi, doim ko'rinadi
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xs, AppSpace.lg, AppSpace.sm),
        child: SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: 0, label: Text(tr('Mijozlar'))),
            ButtonSegment(value: 3, label: Text(tr('Qarzdorlar'))),
            ButtonSegment(value: 1, label: Text(tr("To'lovlar"))),
            ButtonSegment(value: 2, label: Text(tr('Eslatmalar'))),
          ],
          selected: {_tab},
          onSelectionChanged: (s) => setState(() => _tab = s.first),
        ),
      ),
      Expanded(
        child: LazyIndexedStack(index: _tab, children: [
          _ClientsTab(stream: _clients, adminId: widget.admin.id),
          // zalning hamma mijozlari (boshqa trenerniki ham) — faqat ko'rish
          PaymentsScreen(me: widget.admin),
          _ReminderReportTab(stream: _reminders),
          DebtorsTab(clients: _debtClients, memberships: _memberships, adminId: widget.admin.id),
        ]),
      ),
    ]);
  }
}

class _ClientsTab extends StatelessWidget {
  final Stream<List<AppUser>> stream;
  final String adminId;
  const _ClientsTab({required this.stream, required this.adminId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppUser>>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final list = [...snap.data!]..sort((a, b) => a.name.compareTo(b.name));
        if (list.isEmpty) {
          return EmptyState(icon: Icons.card_membership_outlined, title: tr("Hali mijoz yo'q"));
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xs, AppSpace.lg, AppSpace.xl),
          children: [
            for (final u in list)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: _SubscriptionTile(client: u, adminId: adminId),
              ),
          ],
        );
      },
    );
  }
}

class _SubscriptionTile extends StatelessWidget {
  final AppUser client;
  final String adminId;
  const _SubscriptionTile({required this.client, required this.adminId});

  Future<void> _sendReminder(BuildContext context, int daysLeft) =>
      _remind(context, client, daysLeft, adminId);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final u = client;
    final name = u.name.isEmpty ? fmtPhone(u.phone) : u.name;
    final exp = u.subscriptionExpiresAt;
    final daysLeft = Subscription.daysLeft(exp);
    final expiringSoon = Subscription.isExpiringSoon(exp);
    final expired = Subscription.isExpired(exp);
    final status = exp == null
        ? Pill(text: tr('Abonement yo‘q'), color: AppColors.textMuted)
        : expired
            ? Pill(text: tr('Muddati o‘tdi'), color: AppColors.danger)
            : expiringSoon
                ? Pill(text: trf('{0} kun qoldi', [daysLeft]), color: AppColors.warning)
                : Pill(text: trf('{0} kun qoldi', [daysLeft]), color: AppColors.success);

    return BentoTile(
      onTap: () => addSubscriptionSheet(context, u),
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          UserAvatar(name: name),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Text(name, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: AppSpace.sm),
          status,
        ]),
        if (expiringSoon || expired) ...[
          const SizedBox(height: AppSpace.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: () => _sendReminder(context, daysLeft),
              icon: const Icon(Icons.notifications_active_outlined, size: 18),
              label: Text(tr('Eslatma yubor')),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Mijozga yangi abonement qo'shish — tugash sanasi avtomatik hisoblanadi (boshlanish + oy soni).
Future<void> addSubscriptionSheet(BuildContext context, AppUser client) async {
  // 0 — kunlik tashrif, aks holda oy soni
  var months = subscriptionMonths.first;
  int stdPrice() => months == 0 ? Subscription.priceOf(days: 1) : Subscription.priceOf(months: months);
  final price = TextEditingController(text: '${stdPrice()}');
  // To'langan kun — muddat shundan hisoblanadi (zal egasi: "to'lagan kundan hisobla").
  // Mijoz oldin to'lab, trener keyin kiritsa ham to'g'ri chiqsin; kelajak sana yo'q.
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  var paid = today;

  final saved = await showSheet<bool>(
    context,
    StatefulBuilder(
      builder: (ctx, setS) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text(trf('Abonement — {0}', [client.name.isEmpty ? fmtPhone(client.phone) : client.name]),
            style: Theme.of(ctx).textTheme.titleLarge),
        const SizedBox(height: AppSpace.lg),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
            for (final m in [0, ...subscriptionMonths])
              ChoiceChip(
                selected: months == m,
                // tur almashganda narx belgilangan qiymatga qaytadi
                onSelected: (_) => setS(() {
                  months = m;
                  price.text = '${stdPrice()}';
                }),
                label: Text(m == 0 ? tr('Kunlik') : trf('{0} oy', [m])),
              ),
          ]),
        ),
        const SizedBox(height: AppSpace.md),
        TextField(
          controller: price,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: tr('Narxi'), suffixText: tr("so'm")),
        ),
        const SizedBox(height: AppSpace.sm),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.event_outlined),
            label: Text(trf("To'langan sana: {0}", [fmtDay(paid)])),
            onPressed: () async {
              final d = await showDatePicker(
                context: ctx,
                initialDate: paid,
                firstDate: today.subtract(const Duration(days: 60)),
                lastDate: today,
              );
              if (d != null) setS(() => paid = DateTime(d.year, d.month, d.day));
            },
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Saqlash')),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        // Oldingi to'lovlar — xato kiritilganini o'chirib, to'g'risini qayta kiritish uchun
        StreamBuilder<List<Subscription>>(
          stream: Db.subscriptions(client.id),
          builder: (ctx, snap) {
            final list = snap.data ?? const <Subscription>[];
            if (list.isEmpty) return const SizedBox.shrink();
            final muted = Theme.of(ctx).textTheme.bodySmall?.copyWith(color: AppColors.textMuted);
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: AppSpace.sm),
              Text(tr("Kiritilgan to'lovlar"), style: muted),
              for (final s in list.take(5))
                Row(children: [
                  Expanded(
                    child: Text([
                      fmtDay(s.paidDate ?? s.startDate),
                      s.kindLabel,
                      if (s.price > 0) fmtMoney(s.price, s.currency),
                    ].join(' · ')),
                  ),
                  IconButton(
                    tooltip: tr("To'lovni o'chirish"),
                    icon: Icon(Icons.delete_outline, color: AppColors.danger),
                    onPressed: () => _deleteSubscription(ctx, client, s),
                  ),
                ]),
            ]);
          },
        ),
      ]),
    ),
  );

  if (saved == true) {
    await Db.addSubscription(
      client,
      Subscription(
        startDate: paid,
        months: months,
        days: months == 0 ? 1 : 0,
        price: int.tryParse(price.text.replaceAll(RegExp(r'\D'), '')) ?? 0,
        paidDate: paid,
      ),
    );
    if (context.mounted) showSnack(context, tr('Abonement qo‘shildi'));
  }
}

Future<void> _deleteSubscription(BuildContext context, AppUser client, Subscription s) async {
  final what = [
    fmtDay(s.paidDate ?? s.startDate),
    s.kindLabel,
    if (s.price > 0) fmtMoney(s.price, s.currency),
  ].join(' · ');
  final ok = await confirm(
    context,
    title: tr("To'lov o'chirilsinmi?"),
    message: trf("{0}. Abonement muddati oldingi to'lovdan qayta hisoblanadi.", [what]),
    ok: tr("O'chirish"),
    destructive: true,
  );
  if (!ok) return;
  try {
    await Db.deleteSubscription(client, s);
    if (context.mounted) showSnack(context, tr("To'lov o'chirildi"));
  } catch (e) {
    if (context.mounted) showSnack(context, trf("Bo'lmadi: {0}", [e]));
  }
}

Future<void> _remind(BuildContext context, AppUser client, int daysLeft, String adminId) async {
  try {
    await Db.sendSubscriptionReminder(client, daysLeft, adminId);
    if (context.mounted) showSnack(context, tr('Eslatma yuborildi'));
  } catch (e) {
    if (context.mounted) showSnack(context, trf("Bo'lmadi: {0}", [e]));
  }
}

/// Qarzdorlar — abonement muddati o'tgan mijozlar, eng ko'p kun o'tgani tepada (zal egasi, 11-noy).
/// Mijozlar oqimi — "Mijozlar" bo'limidagi bilan bir xil (trener — o'z shogirdlari, bosh admin — hammasi);
/// oxirgi to'lov summasi `memberships` ko'zgusidan, bo'lmasa ko'rsatilmaydi.
class DebtorsTab extends StatelessWidget {
  final Stream<List<AppUser>> clients;
  final Stream<List<Membership>> memberships;
  final String adminId;
  final DateTime? now;
  const DebtorsTab({
    super.key,
    required this.clients,
    required this.memberships,
    required this.adminId,
    this.now,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppUser>>(
      stream: clients,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final list = debtors(snap.data!, now);
        return StreamBuilder<List<Membership>>(
          stream: memberships,
          builder: (context, ms) {
            final paid = {for (final m in ms.data ?? const <Membership>[]) m.uid: m};
            return ListView(
              padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xs, AppSpace.lg, AppSpace.xl),
              children: [
                SectionHeader(
                  tr('Qarzdorlar'),
                  trailing: Pill(
                    text: trf('{0} ta', [list.length]),
                    color: list.isEmpty ? AppColors.textMuted : AppColors.danger,
                  ),
                ),
                if (list.isEmpty)
                  EmptyState(icon: Icons.check_circle_outline, title: tr("Qarzdor yo'q")),
                for (final u in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.sm),
                    child: _DebtorTile(client: u, last: paid[u.id], adminId: adminId, now: now),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _DebtorTile extends StatelessWidget {
  final AppUser client;
  final Membership? last;
  final String adminId;
  final DateTime? now;
  const _DebtorTile({required this.client, required this.last, required this.adminId, this.now});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final u = client;
    final name = u.name.isEmpty ? fmtPhone(u.phone) : u.name;
    final daysLeft = Subscription.daysLeft(u.subscriptionExpiresAt, now);
    final m = last;
    return BentoTile(
      onTap: () => addSubscriptionSheet(context, u),
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          UserAvatar(name: name, photoUrl: u.photoUrl),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (m != null && m.price > 0)
                Text(
                  trf("Oxirgi to'lov: {0} · {1}", [fmtMoney(m.price, m.currency), m.kindLabel]),
                  style: t.bodySmall?.copyWith(color: AppColors.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ]),
          ),
          const SizedBox(width: AppSpace.sm),
          Pill(text: trf("{0} kun o'tdi", [-daysLeft]), color: AppColors.danger),
        ]),
        const SizedBox(height: AppSpace.sm),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: () => _remind(context, u, daysLeft, adminId),
            icon: const Icon(Icons.notifications_active_outlined, size: 18),
            label: Text(tr('Eslatma yubor')),
          ),
        ),
      ]),
    );
  }
}

class _ReminderReportTab extends StatelessWidget {
  final Stream<List<Reminder>> stream;
  const _ReminderReportTab({required this.stream});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return StreamBuilder<List<Reminder>>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final byDay = ReminderReport.byDay(snap.data!, days: 7);
        final total = byDay.values.fold<int>(0, (s, v) => s + v);
        return ListView(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xs, AppSpace.lg, AppSpace.xl),
          children: [
            SectionHeader(tr('Oxirgi 7 kun'), trailing: Pill(text: trf('{0} ta', [total]), color: AppColors.accent)),
            for (final e in byDay.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: BentoTile(
                  padding: const EdgeInsets.all(AppSpace.md),
                  child: Row(children: [
                    Expanded(
                      child: Text(uzDate(DateTime.parse(e.key)), style: t.bodyMedium),
                    ),
                    Pill(
                      text: '${e.value}',
                      color: e.value > 0 ? AppColors.accent : AppColors.textMuted,
                    ),
                  ]),
                ),
              ),
          ],
        );
      },
    );
  }
}
