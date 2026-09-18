import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../services/db.dart';
import '../../theme.dart';
import '../../widgets/ui.dart';
import 'clients_screen.dart';
import 'trainer_stats_screen.dart';

/// "Xodimlar" — faqat bosh admin (zal egasi) uchun.
/// Trener tayinlaydi, har trenerning shogirdlarini ko'radi, akkaunt o'chiradi.
class StaffScreen extends StatelessWidget {
  final AppUser owner;
  const StaffScreen({super.key, required this.owner});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppUser>>(
      stream: Db.staff(),
      builder: (context, staffSnap) {
        return StreamBuilder<List<AppUser>>(
          stream: Db.clients(),
          builder: (context, clientSnap) {
            if (!staffSnap.hasData || !clientSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final staff = [...staffSnap.data!]..sort((a, b) {
                // bosh admin doim birinchi, keyin ism bo'yicha
                if (a.isOwner != b.isOwner) return a.isOwner ? -1 : 1;
                return a.name.compareTo(b.name);
              });
            final clients = clientSnap.data!;
            final trainers = staff.where((u) => u.isTrainer).length;
            final free = clients.where((c) => c.trainerId == null).length;

            int countFor(String uid) => clients.where((c) => c.trainerId == uid).length;

            return ListView(
              padding:
                  const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xs, AppSpace.lg, AppSpace.xxl),
              children: [
                FadeInUp(
                  child: Row(children: [
                    Expanded(
                      child: StatTile(
                        icon: Icons.badge_outlined,
                        label: 'Trener',
                        value: '$trainers',
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: StatTile(
                        icon: Icons.groups_outlined,
                        label: 'Shogird',
                        value: '${clients.length}',
                        color: AppColors.water,
                      ),
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: StatTile(
                        icon: Icons.person_off_outlined,
                        label: 'Biriktirilmagan',
                        value: '$free',
                        color: free > 0 ? AppColors.warning : AppColors.textMuted,
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: AppSpace.md),
                FadeInUp(
                  index: 1,
                  child: BentoTile(
                    feature: true,
                    padding: const EdgeInsets.all(AppSpace.md),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => TrainerStatsScreen(owner: owner)),
                    ),
                    child: Row(children: [
                      IconBadge(Icons.leaderboard_outlined, color: AppColors.accent, size: 38),
                      const SizedBox(width: AppSpace.md),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Trenerlar reytingi',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text(
                            "Solishtirish, ball va kimga e'tibor kerak",
                            style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                          ),
                        ]),
                      ),
                      Icon(Icons.chevron_right, size: 20, color: AppColors.textFaint),
                    ]),
                  ),
                ),
                const SizedBox(height: AppSpace.xl),
                SectionHeader(
                  'Xodimlar',
                  eyebrow: 'Zal jamoasi',
                  trailing: TextButton.icon(
                    onPressed: () => _promoteSheet(context, clients),
                    icon: const Icon(Icons.person_add_alt, size: 18),
                    label: const Text('Trener tayinlash'),
                  ),
                ),
                for (var i = 0; i < staff.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.sm),
                    child: FadeInUp(
                      index: 1 + i,
                      child: _StaffTile(
                        person: staff[i],
                        clientCount: countFor(staff[i].id),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TrainerDetail(
                              trainer: staff[i],
                              owner: owner,
                            ),
                          ),
                        ),
                        // O'zini o'zgartirib bo'lmaydi; boshqa bosh adminni
                        // faqat bosh adminlikdan olish mumkin
                        onActions: staff[i].id == owner.id
                            ? null
                            : () => _staffActions(
                                  context,
                                  staff[i],
                                  countFor(staff[i].id),
                                  ownerCount: staff.where((u) => u.isOwner).length,
                                ),
                      ),
                    ),
                  ),
                if (free > 0) ...[
                  const SizedBox(height: AppSpace.xl),
                  SectionHeader(
                    'Trenersiz shogirdlar',
                    eyebrow: 'Biriktirish kerak',
                    trailing: Pill(text: '$free', color: AppColors.warning),
                  ),
                  for (final c in clients.where((c) => c.trainerId == null))
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.sm),
                      child: _ClientRow(
                        client: c,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ClientDetail(client: c, admin: owner),
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  /// Oddiy foydalanuvchini trener qilish
  Future<void> _promoteSheet(BuildContext context, List<AppUser> clients) async {
    if (clients.isEmpty) {
      showSnack(context, "Hali ro'yxatdan o'tgan foydalanuvchi yo'q");
      return;
    }
    final picked = await showSheet<AppUser>(
      context,
      _PickUserSheet(users: clients),
    );
    if (picked == null || !context.mounted) return;

    final ok = await confirm(
      context,
      title: 'Trener qilinsinmi?',
      message: '${picked.name.isEmpty ? fmtPhone(picked.phone) : picked.name} '
          'trener paneliga kira oladi: reja tuzadi, mahsulot qo’shadi, '
          'shogirdlar bilan yozishadi.',
      ok: 'Trener qilish',
    );
    if (!ok) return;
    await Db.setRole(picked.id, 'admin');
    if (context.mounted) showSnack(context, 'Trener tayinlandi');
  }

  /// Xodim ustidagi amallar (bosh admin uchun)
  Future<void> _staffActions(
    BuildContext context,
    AppUser person,
    int count, {
    required int ownerCount,
  }) async {
    final name = person.name.isEmpty ? fmtPhone(person.phone) : person.name;
    // Oxirgi bosh adminni tushirib bo'lmaydi — aks holda hech kim rol tayinlay olmaydi
    final lastOwner = person.isOwner && ownerCount <= 1;
    final action = await showSheet<String>(
      context,
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpace.xs),
          Text(
            person.isOwner
                ? 'Bosh admin'
                : (count == 0 ? 'Shogirdi yo’q' : '$count ta shogird biriktirilgan'),
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: AppSpace.lg),
          if (!person.isOwner) ...[
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, 'makeOwner'),
              icon: const Icon(Icons.shield_outlined, size: 18),
              label: const Text('Bosh admin qilish'),
            ),
            const SizedBox(height: AppSpace.sm),
          ],
          OutlinedButton.icon(
            onPressed: lastOwner ? null : () => Navigator.pop(context, 'demote'),
            icon: const Icon(Icons.person_remove_outlined, size: 18),
            label: Text(person.isOwner ? 'Bosh adminlikdan olish' : 'Trenerlikdan olish'),
          ),
          if (lastOwner)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.sm),
              child: Text(
                'Bu yagona bosh admin — tushirib bo’lmaydi. Avval boshqa birovni '
                'bosh admin qiling.',
                style: TextStyle(color: AppColors.textFaint, fontSize: 12),
              ),
            ),
          const SizedBox(height: AppSpace.sm),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: BorderSide(color: AppColors.danger.withValues(alpha: 0.4)),
            ),
            onPressed: () => Navigator.pop(context, 'delete'),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Akkauntni o’chirish'),
          ),
        ],
      ),
    );
    if (action == null || !context.mounted) return;

    if (action == 'makeOwner') {
      final ok = await confirm(
        context,
        title: 'Bosh admin qilinsinmi?',
        message: '$name sizga teng huquq oladi: trener tayinlaydi, akkaunt o’chiradi, '
            'hamma trener va shogirdni ko’radi.\n\nUni faqat boshqa bosh admin '
            'tushira oladi.',
        ok: 'Bosh admin qilish',
      );
      if (!ok) return;
      await Db.setRole(person.id, 'owner');
      if (context.mounted) showSnack(context, 'Bosh admin tayinlandi');
      return;
    }

    if (action == 'demote') {
      // Bosh adminni tushirsak — u trener bo'ladi, trenerni tushirsak — oddiy foydalanuvchi
      final toRole = person.isOwner ? 'admin' : 'user';
      final ok = await confirm(
        context,
        title: person.isOwner ? 'Bosh adminlikdan olinsinmi?' : 'Trenerlikdan olinsinmi?',
        message: person.isOwner
            ? '$name oddiy trener bo’lib qoladi: rol tayinlay olmaydi va akkaunt '
                'o’chira olmaydi. Shogirdlari o’zida qoladi.'
            : (count == 0
                ? '$name oddiy foydalanuvchiga aylanadi va trener paneliga kira olmaydi.'
                : '$name oddiy foydalanuvchiga aylanadi. Unga biriktirilgan $count ta '
                    'shogird trenersiz qoladi — ularni boshqa trenerga biriktirishingiz kerak.'),
        ok: 'Olish',
        destructive: true,
      );
      if (!ok) return;
      await Db.setRole(person.id, toRole);
      if (context.mounted) {
        showSnack(context, person.isOwner ? 'Bosh adminlikdan olindi' : 'Trenerlikdan olindi');
      }
      return;
    }

    final ok = await confirm(
      context,
      title: 'Akkaunt o’chirilsinmi?',
      message: '$name ilovaga kira olmaydi va ro’yxatlardan yo’qoladi. '
          'Bu amalni qaytarib bo’lmaydi.',
      ok: 'O’chirish',
      destructive: true,
    );
    if (!ok) return;
    await Db.deleteUser(person.id);
    if (context.mounted) showSnack(context, 'Akkaunt o’chirildi');
  }
}

/// Bitta trener/bosh admin qatori
class _StaffTile extends StatelessWidget {
  final AppUser person;
  final int clientCount;
  final VoidCallback onTap;
  final VoidCallback? onActions;
  const _StaffTile({
    required this.person,
    required this.clientCount,
    required this.onTap,
    this.onActions,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final name = person.name.isEmpty ? fmtPhone(person.phone) : person.name;
    return BentoTile(
      onTap: onTap,
      feature: person.isOwner,
      padding: const EdgeInsets.all(AppSpace.md),
      child: Row(children: [
        UserAvatar(name: name),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleMedium,
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Pill(
                text: person.isOwner ? 'Bosh admin' : 'Trener',
                color: person.isOwner ? AppColors.accent : AppColors.textMuted,
              ),
            ]),
            const SizedBox(height: 2),
            Text(
              clientCount == 0
                  ? 'Shogirdi yo’q'
                  : '$clientCount ta shogird  ·  ${fmtPhone(person.phone)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.bodySmall?.copyWith(
                color: AppColors.textMuted,
                fontFeatures: tabular,
              ),
            ),
          ]),
        ),
        if (onActions != null)
          IconButton(
            tooltip: 'Amallar',
            onPressed: onActions,
            icon: const Icon(Icons.more_horiz, size: 20),
          )
        else
          Padding(
            padding: const EdgeInsets.only(right: AppSpace.sm),
            child: Icon(Icons.chevron_right, size: 20, color: AppColors.textFaint),
          ),
      ]),
    );
  }
}

/// Trenerning shogirdlari ro'yxati
class TrainerDetail extends StatelessWidget {
  final AppUser trainer;
  final AppUser owner;
  const TrainerDetail({super.key, required this.trainer, required this.owner});

  @override
  Widget build(BuildContext context) {
    final name = trainer.name.isEmpty ? fmtPhone(trainer.phone) : trainer.name;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name),
            Text(
              trainer.isOwner ? 'Bosh admin' : 'Trener',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
      body: StreamBuilder<List<AppUser>>(
        stream: Db.clients(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final mine = snap.data!.where((c) => c.trainerId == trainer.id).toList()
            ..sort((a, b) => a.name.compareTo(b.name));
          if (mine.isEmpty) {
            return const EmptyState(
              icon: Icons.groups_outlined,
              title: 'Shogird biriktirilmagan',
              subtitle: 'Shogirdni "Mijozlar" bo’limidan tanlab, '
                  'shu trenerga biriktirishingiz mumkin.',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.xxl),
            children: [
              SectionHeader(
                'Shogirdlar',
                eyebrow: name,
                trailing: Pill(text: '${mine.length}', color: AppColors.accent),
              ),
              for (final c in mine)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.sm),
                  child: _ClientRow(
                    client: c,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ClientDetail(client: c, admin: owner),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Shogird qatori (xodimlar ekranida ishlatiladi)
class _ClientRow extends StatelessWidget {
  final AppUser client;
  final VoidCallback onTap;
  const _ClientRow({required this.client, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final u = client;
    final name = u.name.isEmpty ? fmtPhone(u.phone) : u.name;
    return BentoTile(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpace.md),
      child: Row(children: [
        UserAvatar(name: name, size: 38),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium),
            const SizedBox(height: 2),
            Text(
              u.profileDone
                  ? '${fmtNum(u.weight)} kg · ${u.targetKcal} kkal'
                  : 'Anketa to’ldirilmagan',
              style: t.bodySmall?.copyWith(
                color: AppColors.textMuted,
                fontFeatures: tabular,
              ),
            ),
          ]),
        ),
        if (u.planId == null)
          Pill(text: 'Rejasiz', color: AppColors.warning)
        else
          Pill(text: 'Reja bor', color: AppColors.success, icon: Icons.check_rounded),
      ]),
    );
  }
}

/// Trener qilish uchun foydalanuvchi tanlash varag'i
class _PickUserSheet extends StatefulWidget {
  final List<AppUser> users;
  const _PickUserSheet({required this.users});

  @override
  State<_PickUserSheet> createState() => _PickUserSheetState();
}

class _PickUserSheetState extends State<_PickUserSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final qDigits = q.replaceAll(RegExp(r'\D'), '');
    final list = widget.users
        .where((u) =>
            u.name.toLowerCase().contains(q) || (qDigits.isNotEmpty && u.phone.contains(qDigits)))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Text('Kimni trener qilamiz?', style: Theme.of(context).textTheme.titleLarge),
      ),
      const SizedBox(height: AppSpace.md),
      TextField(
        onChanged: (v) => setState(() => _q = v),
        decoration: const InputDecoration(
          hintText: 'Ism yoki telefon raqam',
          prefixIcon: Icon(Icons.search),
        ),
      ),
      const SizedBox(height: AppSpace.md),
      ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
        child: list.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(AppSpace.lg),
                child: Text('Hech narsa topilmadi', style: TextStyle(color: AppColors.textMuted)),
              )
            : ListView.separated(
                shrinkWrap: true,
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: AppSpace.sm),
                itemBuilder: (_, i) {
                  final u = list[i];
                  final name = u.name.isEmpty ? fmtPhone(u.phone) : u.name;
                  return BentoTile(
                    onTap: () => Navigator.pop(context, u),
                    padding: const EdgeInsets.all(AppSpace.md),
                    child: Row(children: [
                      UserAvatar(name: name, size: 36),
                      const SizedBox(width: AppSpace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium),
                            Text(
                              fmtPhone(u.phone),
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12.5,
                                fontFeatures: tabular,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 20, color: AppColors.textFaint),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }
}
