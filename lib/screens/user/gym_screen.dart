import 'package:flutter/material.dart';
import '../../models/gym.dart';
import '../../models/models.dart';
import '../../services/db.dart';
import '../../theme.dart';
import '../../widgets/ui.dart';

/// Shogird: Zal bo'limi — 3 ta mashg'ulot kunini tanlaydi, bugungi mashg'ulotni ko'radi.
/// Mashqlarni belgilash yo'q (mashqlar ro'yxati hali ishlab chiqilmoqda).
class GymScreen extends StatelessWidget {
  final AppUser user;
  const GymScreen({super.key, required this.user});

  Future<void> _chooseDays(BuildContext context) async {
    final days = await showSheet<List<int>>(context, _DaysPicker(initial: user.gymDays));
    if (days == null) return;
    try {
      await Db.setGymDays(user.id, days);
      if (context.mounted) showSnack(context, 'Zal kunlari saqlandi');
    } catch (e) {
      if (context.mounted) showSnack(context, "Saqlab bo'lmadi: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final today = DateTime.now().weekday;
    final days = user.gymDays;
    final hasDays = validGymDays(days);
    final isHome = user.homeWorkoutDate == todayKey();
    final todayWorkout = workoutFor(days, today);
    final next = nextWorkout(days, today);

    return Scaffold(
      appBar: AppBar(title: const Text('Zal')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xs, AppSpace.lg, AppSpace.xxl),
        children: [
          if (!hasDays)
            BentoTile(
              feature: true,
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Haftasiga 3 kun mashg\'ulot', style: t.titleLarge),
                const SizedBox(height: AppSpace.sm),
                Text(
                  "O'zingizga qulay variantni tanlang: Seshanba, Payshanba, Shanba yoki "
                  "Dushanba, Chorshanba, Juma.",
                  style: t.bodyMedium?.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: AppSpace.lg),
                FilledButton.icon(
                  onPressed: () => _chooseDays(context),
                  icon: const Icon(Icons.event_available_outlined),
                  label: const Text('Kunlarni tanlash'),
                ),
              ]),
            )
          else ...[
            // Bugun
            BentoTile(
              feature: true,
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Eyebrow('Bugun · ${weekdayNames[today]}'),
                const SizedBox(height: AppSpace.sm),
                if (isHome) ...[
                  Row(children: [
                    Icon(Icons.home_outlined, color: AppColors.accent),
                    const SizedBox(width: AppSpace.sm),
                    Text('Uyda mashq', style: t.headlineSmall),
                  ]),
                  const SizedBox(height: AppSpace.xs),
                  Text("Trener bugun uyda mashq qilishingizni belgiladi.",
                      style: t.bodyMedium?.copyWith(color: AppColors.textMuted)),
                ] else if (todayWorkout != null) ...[
                  Text(todayWorkout, style: t.headlineSmall),
                  const SizedBox(height: AppSpace.xs),
                  Text('Bugun zalga borish kuni',
                      style: t.bodyMedium?.copyWith(color: AppColors.textMuted)),
                ] else ...[
                  Text('Dam olish kuni', style: t.headlineSmall),
                  if (next != null) ...[
                    const SizedBox(height: AppSpace.xs),
                    Text('Keyingi: ${weekdayNames[next.$1]} — ${next.$2}',
                        style: t.bodyMedium?.copyWith(color: AppColors.textMuted)),
                  ],
                ],
              ]),
            ),
            const SizedBox(height: AppSpace.xl),
            SectionHeader(
              'Mening jadvalim',
              eyebrow: 'Haftasiga 3 kun',
              trailing: TextButton.icon(
                onPressed: () => _chooseDays(context),
                icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                label: const Text("O'zgartirish"),
              ),
            ),
            for (final d in ([...days]..sort()))
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: BentoTile(
                  padding: const EdgeInsets.all(AppSpace.md),
                  child: Row(children: [
                    SizedBox(
                      width: 96,
                      child: Text(weekdayNames[d]!,
                          style:
                              t.titleMedium?.copyWith(color: d == today ? AppColors.accent : null)),
                    ),
                    Expanded(child: Text(workoutFor(days, d)!, style: t.bodyMedium)),
                  ]),
                ),
              ),
          ],
          const SizedBox(height: AppSpace.xl),
          const SectionHeader('Mashqlar', eyebrow: 'Tez orada'),
          BentoTile(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Row(children: [
              Icon(Icons.construction_outlined, color: AppColors.warning),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Text(
                  "Bu bo'limda tuzatish ishlari olib borilmoqda — har bir mashg'ulot mashqlari "
                  "tez orada qo'shiladi.",
                  style: t.bodyMedium,
                ),
              ),
            ]),
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            "Bugun zalga kela olmasangiz — 'Trener' bo'limida \"bugun kelolmayman\" deb yozing, "
            "trener uyda mashq belgilaydi.",
            style: t.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// 3 kun tanlash: toq kunlar / juft kunlar / o'zim tanlayman
class _DaysPicker extends StatefulWidget {
  final List<int> initial;
  const _DaysPicker({required this.initial});

  @override
  State<_DaysPicker> createState() => _DaysPickerState();
}

class _DaysPickerState extends State<_DaysPicker> {
  late final Set<int> _sel = {...widget.initial};

  bool _same(List<int> preset) => _sel.length == 3 && preset.every(_sel.contains);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget preset(String title, List<int> days) => Card(
          child: ListTile(
            leading: Icon(
              _same(days) ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: _same(days) ? AppColors.accent : AppColors.textMuted,
            ),
            title: Text(title),
            subtitle: Text(days.map((d) => weekdayNames[d]).join(', ')),
            onTap: () => setState(() => _sel
              ..clear()
              ..addAll(days)),
          ),
        );

    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Zal kunlari', style: t.titleLarge),
          const SizedBox(height: AppSpace.xs),
          Text(
              "Haftasiga 3 kun. Mashg'ulotlar kunlar tartibida: 1) ${workoutGroups[0]}, "
              "2) ${workoutGroups[1]}, 3) ${workoutGroups[2]}.",
              style: t.bodySmall?.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: AppSpace.md),
          preset('1-variant', evenDays),
          preset('2-variant', oddDays),
          const SizedBox(height: AppSpace.lg),
          FilledButton(
            onPressed: _same(evenDays) || _same(oddDays)
                ? () => Navigator.pop(context, _sel.toList())
                : null,
            child: const Text('Saqlash'),
          ),
        ]);
  }
}
