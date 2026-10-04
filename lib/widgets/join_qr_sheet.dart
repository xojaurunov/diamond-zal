import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../theme.dart';
import 'ui.dart';

/// Ilovaga ro'yxatdan o'tish havolasi — zal eshigiga chop etib osish uchun.
const joinUrl = 'https://kotta-qani-09111753.web.app/ilova/';

/// QR kod — pastdan chiquvchi varaqda (bosh admin/trener uchun)
Future<void> showJoinQr(BuildContext context) => showSheet<void>(
      context,
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Ro\'yxatdan o\'tish QR kodi', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpace.sm),
        Text(
          'Mijoz shu kodni skanerlasa, ilovaga ro\'yxatdan o\'tish sahifasi ochiladi.',
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
          child: QrImageView(data: joinUrl, size: 220, backgroundColor: Colors.white),
        ),
        const SizedBox(height: AppSpace.lg),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(const ClipboardData(text: joinUrl));
              if (context.mounted) showSnack(context, 'Havola nusxalandi');
            },
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Havolani nusxalash'),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
      ]),
    );
