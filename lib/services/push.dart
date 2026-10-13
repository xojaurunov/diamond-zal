import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'db.dart';
import 'notifications.dart';

/// Push (FCM) tokenini foydalanuvchi hujjatiga yozadi — server (Cloud Functions) shu token
/// orqali ilova yopiq bo'lsa ham chat va reja bildirishnomasini yuboradi.
/// Serverdagi funksiyalar joylanmagan bo'lsa (Blaze yo'q) token shunchaki saqlanib turadi.
class Push {
  static String? _token;

  static Future<void> register(String uid) async {
    if (!Notifications.supported) return;
    try {
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission();
      _token = await fm.getToken();
      if (_token != null) await Db.addFcmToken(uid, _token!);
      fm.onTokenRefresh.listen((t) {
        _token = t;
        Db.addFcmToken(uid, t);
      });
    } catch (e) {
      debugPrint('Push token olinmadi: $e');
    }
  }

  /// Chiqishda — bu telefon endi shu akkaunt bildirishnomalarini olmasin.
  /// Chiqishni ushlab turmaydi: token yozuvini o'chirish server javobini kutadi (tarmoq
  /// sekin bo'lsa uzoq) — [wait] dan oshsa kutilmaydi (yozuv navbatda qoladi). Telefondagi
  /// tokenni o'chirish ham tarmoq so'rovi — umuman kutilmaydi.
  static Future<void> unregister(String uid, {Duration wait = const Duration(milliseconds: 1500)}) async {
    final t = _token;
    if (t == null) return;
    _token = null;
    try {
      await Db.removeFcmToken(uid, t).timeout(wait);
    } catch (_) {}
    FirebaseMessaging.instance.deleteToken().catchError((_) {});
  }
}
