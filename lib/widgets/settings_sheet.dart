import 'package:flutter/material.dart';
import '../services/notifications.dart';
import '../services/settings.dart';
import '../theme.dart';
import 'ui.dart';

/// Sozlamalar: ko'rinish (tema) va bildirishnomalar.
/// [student] — shogird uchun ovqat/vazn/reja eslatmalari ham ko'rsatiladi.
Future<void> showSettings(BuildContext context, {required bool student}) =>
    showSheet<void>(context, _SettingsSheet(student: student));

class _SettingsSheet extends StatefulWidget {
  final bool student;
  const _SettingsSheet({required this.student});

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  Future<void> _toggle(String key, bool v) async {
    await AppSettings.setNotif(key, v);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget sw(String key, bool value, String title, String sub) => SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: value,
          onChanged: (v) => _toggle(key, v),
          title: Text(title),
          subtitle: Text(sub, style: t.bodySmall?.copyWith(color: AppColors.textMuted)),
        );

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      child: ListView(shrinkWrap: true, children: [
        Text('Sozlamalar', style: t.titleLarge),
        const SizedBox(height: AppSpace.lg),
        const Eyebrow("Ko'rinish"),
        const SizedBox(height: AppSpace.sm),
        ValueListenableBuilder<ThemeMode>(
          valueListenable: AppSettings.themeMode,
          builder: (context, mode, _) => SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: Text("Qorong'i")),
              ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text("Yorug'")),
              ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.phone_android_outlined),
                  label: Text('Telefon')),
            ],
            selected: {mode},
            onSelectionChanged: (s) {
              // tema almashganda ilova qayta chiziladi — varaqni yopamiz
              Navigator.pop(context);
              AppSettings.setThemeMode(s.first);
            },
          ),
        ),
        const SizedBox(height: AppSpace.xl),
        const Eyebrow('Bildirishnomalar'),
        if (!Notifications.supported)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.sm),
            child: Text(
              "Bildirishnomalar telefondagi (Android) ilovada ishlaydi.",
              style: t.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ),
        if (widget.student) ...[
          sw('notif_meals', AppSettings.mealReminders, 'Ovqat vaqti eslatmasi',
              'Rejadagi har mahal vaqtida eslatadi'),
          sw('notif_weight', AppSettings.weighInReminder, 'Haftalik vazn eslatmasi',
              'Vazn kiritish kuni ertalab 08:00 da'),
          sw('notif_plan', AppSettings.planNotifications, 'Yangi reja',
              'Trener reja biriktirganda'),
        ],
        sw('notif_chat', AppSettings.chatNotifications, 'Yangi xabar',
            widget.student ? 'Trener yozganda' : 'Shogird yozganda'),
      ]),
    );
  }
}
