import 'package:firebase_auth/firebase_auth.dart';
import '../l10n/tr.dart';

/// Video serveri javobi (Worker): holat kodi -> trenerga tushunarli xabar
class VideoUploadError implements Exception {
  final int status;
  const VideoUploadError(this.status);

  /// Ilovaning o'z xatolari (server holat kodlari bilan to'qnashmaydi)
  static const tooLong = 1001, compressFailed = 1002;

  @override
  String toString() => switch (status) {
        401 => tr('Kirish muddati tugagan — ilovadan chiqib, qayta kiring'),
        403 => tr('Video faqat trener va bosh admin yuklaydi'),
        413 => tr('Video kichraytirilgandan keyin ham 80 MB dan katta — qisqaroq video tanlang'),
        tooLong => tr('Video 5 daqiqadan uzun — qisqaroq video tanlang'),
        compressFailed => tr("Videoni kichraytirib bo'lmadi — boshqa video tanlang"),
        415 => tr('Bu fayl video emas (mp4, mov, webm, 3gp)'),
        _ => trf('Video serveri xatosi ({0})', [status]),
      };
}

/// Hozirgi foydalanuvchining Firebase tokeni (Worker rolni shu bilan tekshiradi)
Future<String> videoAuthToken() async {
  final token = await FirebaseAuth.instance.currentUser?.getIdToken();
  if (token == null) throw const VideoUploadError(401);
  return token;
}
