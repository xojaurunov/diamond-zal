import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../models/subscription.dart';
import '../../services/db.dart';
import '../../theme.dart';
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
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xs, AppSpace.lg, AppSpace.sm),
        child: SegmentedButton<int>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 0, label: Text('Mijozlar')),
            ButtonSegment(value: 1, label: Text("To'lovlar")),
            ButtonSegment(value: 2, label: Text('Eslatmalar')),
          ],
          selected: {_tab},
          onSelectionChanged: (s) => setState(() => _tab = s.first),
        ),
      ),
      Expanded(
        child: IndexedStack(index: _tab, children: [
          _ClientsTab(stream: _clients, adminId: widget.admin.id),
          // zalning hamma mijozlari (boshqa trenerniki ham) — faqat ko'rish
          PaymentsScreen(me: widget.admin),
          _ReminderReportTab(stream: _reminders),
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
          return const EmptyState(icon: Icons.card_membership_outlined, title: "Hali mijoz yo'q");
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

  Future<void> _sendReminder(BuildContext context, int daysLeft) async {
    try {
      await Db.sendSubscriptionReminder(client, daysLeft, adminId);
      if (context.mounted) showSnack(context, 'Eslatma yuborildi');
    } catch (e) {
      if (context.mounted) showSnack(context, "Bo'lmadi: $e");
    }
  }

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
        ? Pill(text: 'Abonement yo‘q', color: AppColors.textMuted)
        : expired
            ? Pill(text: 'Muddati o‘tdi', color: AppColors.danger)
            : expiringSoon
                ? Pill(text: '$daysLeft kun qoldi', color: AppColors.warning)
                : Pill(text: '$daysLeft kun qoldi', color: AppColors.success);

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
              label: const Text('Eslatma yubor'),
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

  final saved = await showSheet<bool>(
    context,
    StatefulBuilder(
      builder: (ctx, setS) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Abonement — ${client.name.isEmpty ? fmtPhone(client.phone) : client.name}',
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
                label: Text(m == 0 ? 'Kunlik' : '$m oy'),
              ),
          ]),
        ),
        const SizedBox(height: AppSpace.md),
        TextField(
          controller: price,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Narxi', suffixText: "so'm"),
        ),
        const SizedBox(height: AppSpace.lg),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Saqlash'),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
      ]),
    ),
  );

  if (saved == true) {
    await Db.addSubscription(
      client,
      Subscription(
        startDate: DateTime.now(),
        months: months,
        days: months == 0 ? 1 : 0,
        price: int.tryParse(price.text.replaceAll(RegExp(r'\D'), '')) ?? 0,
        paidDate: DateTime.now(),
      ),
    );
    if (context.mounted) showSnack(context, 'Abonement qo‘shildi');
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
            SectionHeader('Oxirgi 7 kun', trailing: Pill(text: '$total ta', color: AppColors.accent)),
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
