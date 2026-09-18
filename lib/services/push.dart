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

  /// Chiqishda — bu telefon endi shu akkaunt bildirishnomalarini olmasin
  static Future<void> unregister(String uid) async {
    final t = _token;
    if (t == null) return;
    try {
      await Db.removeFcmToken(uid, t);
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
    _token = null;
  }
}
