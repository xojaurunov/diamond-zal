import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../l10n/tr.dart';
import '../../models/models.dart';
import '../../services/db.dart';
import '../../theme.dart';
import '../../widgets/gym_card.dart';
import '../../widgets/ui.dart';

/// QR davomat (trener va bosh admin): shogirdning "Zal kartasi" skanerlanadi — bugun keldi deb
/// belgilanadi. Kamera ochiq qoladi, ketma-ket bir nechta shogirdni skanerlash mumkin.
/// Ruxsat qoidada: trener — faqat o'z shogirdi, bosh admin — hammasi.
class QrScanScreen extends StatefulWidget {
  final AppUser admin;

  /// Test uchun: kamera o'rnida (skanerlangan matnni [onCode] ga beradi), shogirdni topish
  /// va belgilash (odatda — `MobileScanner` va `Db`)
  final Widget Function(void Function(String raw) onCode)? scanner;
  final Future<AppUser?> Function(String uid)? lookup;
  final Future<bool> Function(String uid)? alreadyMarked;
  final Future<void> Function(String uid)? mark;

  const QrScanScreen({
    super.key,
    required this.admin,
    this.scanner,
    this.lookup,
    this.alreadyMarked,
    this.mark,
  });

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

/// Oxirgi skanerlash natijasi: matn va rangi
typedef _Result = (String, Color, IconData);

class _QrScanScreenState extends State<QrScanScreen> {
  _Result? _result;

  /// Hozir tekshirilayotgan yoki yaqinda belgilangan kod — kamera bir kodni soniyasiga
  /// bir necha marta ko'radi, takror yozilmasin
  String? _last;
  DateTime _lastAt = DateTime(2000);
  bool _busy = false;

  Future<AppUser?> _lookup(String uid) => widget.lookup?.call(uid) ?? Db.user(uid).first;
  Future<bool> _already(String uid) =>
      widget.alreadyMarked?.call(uid) ?? Db.attendance(uid, todayKey()).first;
  Future<void> _mark(String uid) =>
      widget.mark?.call(uid) ?? Db.markAttendance(uid, todayKey(), true, widget.admin.id);

  Future<void> _onCode(String raw) async {
    final now = DateTime.now();
    if (_busy || (raw == _last && now.difference(_lastAt) < const Duration(seconds: 5))) return;
    _last = raw;
    _lastAt = now;
    final uid = attendanceUid(raw);
    if (uid == null) {
      _show((tr('Bu zal kartasi emas'), AppColors.warning, Icons.qr_code_2));
      return;
    }
    setState(() => _busy = true);
    try {
      final AppUser? user;
      try {
        user = await _lookup(uid);
      } on FirebaseException catch (e) {
        // trener begona shogirdning profilini o'qiy olmaydi (qoida)
        if (e.code == 'permission-denied') {
          _show((tr('Bu shogird sizniki emas'), AppColors.warning, Icons.block));
          return;
        }
        rethrow;
      }
      if (user == null || user.role != 'user') {
        _show((tr('Shogird topilmadi'), AppColors.warning, Icons.person_off_outlined));
        return;
      }
      if (!widget.admin.isOwner && user.trainerId != widget.admin.id) {
        _show((tr('Bu shogird sizniki emas'), AppColors.warning, Icons.block));
        return;
      }
      final name = user.name.isEmpty ? fmtPhone(user.phone) : user.name;
      if (await _already(uid)) {
        _show((trf('{0} — bugun allaqachon belgilangan', [name]), AppColors.success, Icons.check_circle));
        return;
      }
      await _mark(uid);
      HapticFeedback.mediumImpact();
      _show((trf('{0} — keldi', [name]), AppColors.success, Icons.check_circle));
    } catch (e) {
      _show((trf("Bo'lmadi: {0}", [e]), AppColors.danger, Icons.error_outline));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(_Result r) {
    if (mounted) setState(() => _result = r);
  }

  Widget _camera() => MobileScanner(
        controller: MobileScannerController(formats: const [BarcodeFormat.qrCode]),
        onDetect: (capture) {
          for (final b in capture.barcodes) {
            final raw = b.rawValue;
            if (raw != null) {
              _onCode(raw);
              return;
            }
          }
        },
        errorBuilder: (context, error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Text(
              tr("Kamera ochilmadi. Telefon sozlamalarida ilovaga kamera ruxsatini bering."),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = _result;
    return Scaffold(
      appBar: AppBar(title: Text(tr('QR skaner'))),
      body: Column(children: [
        Expanded(
          child: ClipRect(
            child: ColoredBox(
              color: Colors.black,
              child: (widget.scanner ?? (_) => _camera())(_onCode),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: r == null
              ? Text(
                  tr("Shogirdning \"Zal kartasi\" QR kodini ramkaga to'g'rilang."),
                  textAlign: TextAlign.center,
                  style: t.bodyMedium?.copyWith(color: AppColors.textMuted),
                )
              : Row(children: [
                  Icon(r.$3, color: r.$2, size: 32),
                  const SizedBox(width: AppSpace.md),
                  Expanded(child: Text(r.$1, style: t.titleMedium?.copyWith(color: r.$2))),
                  if (_busy) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                ]),
        ),
      ]),
    );
  }
}
