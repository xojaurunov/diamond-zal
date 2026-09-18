import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Telefon/brauzerda saqlanadigan shaxsiy sozlamalar: ko'rinish (tema) va bildirishnomalar.
/// Hisobga bog'lanmagan — har qurilmada o'z tanlovi.
class AppSettings {
  static SharedPreferences? _p;

  /// Ko'rinish: qorong'i (asosiy), yorug' yoki telefon sozlamasiga qarab
  static final themeMode = ValueNotifier<ThemeMode>(ThemeMode.dark);

  /// Bildirishnoma sozlamalari o'zgarganda oshadi (eslatmalarni qayta rejalashtirish uchun)
  static final notifChanged = ValueNotifier<int>(0);

  static Future<void> init() async {
    try {
      _p = await SharedPreferences.getInstance();
    } catch (_) {
      _p = null; // saqlab bo'lmasa ham ilova standart sozlamalar bilan ishlayveradi
    }
    themeMode.value = switch (_p?.getString('theme')) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
  }

  static Future<void> setThemeMode(ThemeMode m) async {
    themeMode.value = m;
    await _p?.setString('theme', m.name);
  }

  // ---------- bildirishnomalar (hammasi standart holatda yoqilgan) ----------
  static bool get mealReminders => _p?.getBool('notif_meals') ?? true;
  static bool get weighInReminder => _p?.getBool('notif_weight') ?? true;
  static bool get chatNotifications => _p?.getBool('notif_chat') ?? true;
  static bool get planNotifications => _p?.getBool('notif_plan') ?? true;

  static Future<void> setNotif(String key, bool v) async {
    await _p?.setBool(key, v);
    notifChanged.value++;
  }
}
