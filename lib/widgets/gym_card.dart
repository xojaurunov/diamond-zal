import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../l10n/tr.dart';
import '../models/models.dart';
import '../theme.dart';
import 'ui.dart';

/// Zal kartasi QR matni: `qobil:a:<uid>`. Trener skanerlasa — shu shogird bugun keldi deb
/// belgilanadi. Ichida faqat uid: maxfiy narsa yo'q, belgilash ruxsati qoidada (o'z shogirdi).
String attendanceCode(String uid) => 'qobil:a:$uid';

/// Skanerlangan matndan uid; zal kartasi bo'lmasa — null
String? attendanceUid(String raw) =>
    RegExp(r'^qobil:a:([A-Za-z0-9_-]{6,128})$').firstMatch(raw.trim())?.group(1);

/// Shogirdning zal kartasi — pastdan chiquvchi varaqda, eshikda trenerga ko'rsatiladi
Future<void> showGymCard(BuildContext context, AppUser user) => showSheet<void>(
      context,
      GymCard(user: user),
    );

class GymCard extends StatelessWidget {
  final AppUser user;
  const GymCard({super.key, required this.user});

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text(tr('Zal kartasi'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpace.sm),
        Text(
          tr("Zalga kelganda trenerga ko'rsating — u skanerlaydi va davomat belgilanadi."),
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textMuted),
        ),
        const SizedBox(height: AppSpace.lg),
        Container(
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: QrImageView(data: attendanceCode(user.id), size: 220, backgroundColor: Colors.white),
        ),
        const SizedBox(height: AppSpace.md),
        Text(user.name, style: Theme.of(context).textTheme.titleMedium),
      ]);
}
