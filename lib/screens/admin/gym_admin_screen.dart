import 'package:flutter/material.dart';
import '../../models/gym.dart';
import '../../models/models.dart';
import '../../services/db.dart';
import '../../theme.dart';
import '../../widgets/ui.dart';

/// Trener: Zal bo'limi — shogirdlar kimda qaysi kun, bugun kim keladi, kim uyda.
/// "Uyda mashq" faqat shogird bugun chatda kela olmasligini yozgan bo'lsa belgilanadi.
class GymAdminScreen extends StatefulWidget {
  final AppUser admin;
  const GymAdminScreen({super.key, required this.admin});

  @override
  State<GymAdminScreen> createState() => _GymAdminScreenState();
}

class _GymAdminScreenState extends State<GymAdminScreen> {
  late final _stream = widget.admin.isOwner ? Db.clients() : Db.clientsOf(widget.admin.id);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final today = DateTime.now().weekday;
    final todayKeyStr = todayKey();
    return StreamBuilder<List<AppUser>>(
      stream: _stream,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final all = [...snap.data!]..sort((a, b) => a.name.compareTo(b.name));
        final home = all.where((u) => u.homeWorkoutDate == todayKeyStr).toList();
        final coming = all
            .where((u) => workoutFor(u.gymDays, today) != null && u.homeWorkoutDate != todayKeyStr)
            .toList();
        final noDays = all.where((u) => !validGymDays(u.gymDays)).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xs, AppSpace.lg, AppSpace.xxl),
          children: [
            Text('Bugun · ${weekdayNames[today]}', style: t.titleLarge),
            const SizedBox(height: AppSpace.md),
            SectionHeader('Bugun zalga keladi',
                trailing: Pill(text: '${coming.length}', color: AppColors.accent)),
            if (coming.isEmpty) _empty(context, "Bugun hech kimning mashg'uloti yo'q"),
            for (final u in coming) _ClientGymTile(client: u, today: today),
            const SizedBox(height: AppSpace.lg),
            SectionHeader('Bugun uyda',
                trailing: Pill(text: '${home.length}', color: AppColors.water)),
            if (home.isEmpty) _empty(context, "Hech kim uyda mashq qilmaydi"),
            for (final u in home) _ClientGymTile(client: u, today: today),
            const SizedBox(height: AppSpace.lg),
            const SectionHeader('Hamma shogirdlar jadvali'),
            for (final u in all) _ClientGymTile(client: u, today: today, showWeek: true),
            if (noDays.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.sm),
                child: Text(
                  "${noDays.length} ta shogird hali zal kunlarini tanlamagan.",
                  style: t.bodySmall?.copyWith(color: AppColors.warning),
                ),
              ),
            const SizedBox(height: AppSpace.xl),
            BentoTile(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Row(children: [
                Icon(Icons.construction_outlined, color: AppColors.warning),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Text(
                    "Mashqlar hozir qo'shilmoqda — har bir mashg'ulotning mashqlari ro'yxati "
                    "ishlab chiqilmoqda.",
                    style: t.bodyMedium,
                  ),
                ),
              ]),
            ),
          ],
        );
      },
    );
  }

  Widget _empty(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm, left: 4),
        child: Text(text, style: TextStyle(color: AppColors.textMuted)),
      );
}

class _ClientGymTile extends StatelessWidget {
  final AppUser client;
  final int today;
  final bool showWeek;
  const _ClientGymTile({required this.client, required this.today, this.showWeek = false});

  Future<void> _toggleHome(BuildContext context, bool isHome) async {
    try {
      await Db.setHomeWorkout(client.id, isHome ? null : todayKey());
      if (context.mounted) {
        showSnack(context, isHome ? 'Uyda mashq bekor qilindi' : 'Bugun uyda mashq belgilandi');
      }
    } catch (e) {
      if (context.mounted) showSnack(context, "Bo'lmadi: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final u = client;
    final name = u.name.isEmpty ? fmtPhone(u.phone) : u.name;
    final days = [...u.gymDays]..sort();
    final isHome = u.homeWorkoutDate == todayKey();
    final todayWorkout = workoutFor(u.gymDays, today);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: BentoTile(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            UserAvatar(name: name, size: 38),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  !validGymDays(days)
                      ? 'Kunlar tanlanmagan'
                      : isHome
                          ? 'Bugun uyda mashq'
                          : (todayWorkout ?? 'Bugun dam olish'),
                  style: t.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
              ]),
            ),
          ]),
          if (showWeek && validGymDays(days)) ...[
            const SizedBox(height: AppSpace.sm),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final d in days)
                Pill(
                  text: '${weekdayShort[d]} · ${workoutGroups[days.indexOf(d)].split(' ').first}',
                  color: d == today ? AppColors.accent : AppColors.textMuted,
                ),
            ]),
          ],
          // Uyda mashq — faqat bugun mashg'ulot kuni bo'lsa va shogird chatda
          // bugun kela olmasligini yozgan bo'lsa (yoki allaqachon belgilangan bo'lsa bekor qilish)
          if (!showWeek && (todayWorkout != null || isHome))
            StreamBuilder<List<(String, ChatMessage)>>(
              stream: Db.messageEvents(u.id),
              builder: (context, snap) {
                final now = DateTime.now();
                final wrote = (snap.data ?? []).any((e) {
                  final m = e.$2;
                  return m.senderId == u.id &&
                      m.createdAt.year == now.year &&
                      m.createdAt.month == now.month &&
                      m.createdAt.day == now.day &&
                      saysCantCome(m.text);
                });
                return Padding(
                  padding: const EdgeInsets.only(top: AppSpace.sm),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        isHome
                            ? 'Uyda mashq belgilangan'
                            : wrote
                                ? 'Chatda bugun kela olmasligini yozdi'
                                : 'Chatda "bugun kelolmayman" deb yozsa, uyda mashq belgilash mumkin',
                        style: t.bodySmall?.copyWith(
                            color: wrote || isHome ? AppColors.warning : AppColors.textFaint),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                      onPressed: isHome || wrote ? () => _toggleHome(context, isHome) : null,
                      icon: Icon(isHome ? Icons.close : Icons.home_outlined, size: 18),
                      label: Text(isHome ? 'Bekor' : 'Uyda mashq'),
                    ),
                  ]),
                );
              },
            ),
        ]),
      ),
    );
  }
}
