import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'api_firestore.dart';

/// Servis rejimidagi kirish. Token telefonda saqlanadi (30 kun); xatolar Firebase kodlari bilan
/// (`invalid-credential`, `email-already-in-use` …) — kirish ekranidagi xabarlar o'zgarmaydi.
class ApiAuth {
  ApiAuth._(this.client) {
    client.onUnauthorized = () => unawaited(signOut());
  }

  static final ApiAuth instance = ApiAuth._(ApiClient(apiUrl));
  static final ApiFirestore firestore = ApiFirestore(instance.client);

  static const _tokenKey = 'api_token', _uidKey = 'api_uid';

  final ApiClient client;
  final _changes = StreamController<String?>.broadcast();
  String? _uid;
  bool _loaded = false;

  String? get uid => _uid;

  /// Kirgan foydalanuvchi uid'i (chiqsa — null); birinchi qiymat saqlangan tokendan
  Stream<String?> changes() async* {
    if (!_loaded) await _load();
    yield _uid;
    yield* _changes.stream;
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    client.token = p.getString(_tokenKey);
    _uid = client.token == null ? null : p.getString(_uidKey);
    _loaded = true;
  }

  Future<void> _set(String? token, String? uid) async {
    final p = await SharedPreferences.getInstance();
    if (token == null) {
      await p.remove(_tokenKey);
      await p.remove(_uidKey);
    } else {
      await p.setString(_tokenKey, token);
      await p.setString(_uidKey, uid!);
    }
    client.token = token;
    _uid = uid;
    _loaded = true;
    _changes.add(uid);
  }

  /// Servis xatosi -> Firebase xato kodi
  static FirebaseAuthException authError(Object e,
      {String unauthorized = 'invalid-credential', String forbidden = 'wrong-password'}) {
    if (e is ApiException) {
      return FirebaseAuthException(
        code: switch (e.status) {
          401 => unauthorized,
          // hozirgi parol noto'g'ri (servis 401 bermaydi — u "chiqish" degani)
          403 => forbidden,
          409 => 'email-already-in-use',
          429 => 'too-many-requests',
          400 when e.message.contains('parol') => 'weak-password',
          400 => 'invalid-email',
          _ => 'unknown',
        },
        message: e.message,
      );
    }
    return FirebaseAuthException(code: 'network-request-failed', message: '$e');
  }

  Future<String> _session(String path, Map<String, String> body, {String unauthorized = 'invalid-credential'}) async {
    try {
      final res = await client.post(path, body) as Map;
      await _set(res['token'] as String, res['uid'] as String);
      return res['uid'] as String;
    } catch (e) {
      throw authError(e, unauthorized: unauthorized);
    }
  }

  Future<String> signIn(String phone, String password) =>
      _session('/auth/login', {'phone': phone, 'password': password});

  /// Yangi akkaunt; profil hujjatini chaqiruvchi yozadi (Firebase'dagidek)
  Future<String> register(String phone, String password) =>
      _session('/auth/register', {'phone': phone, 'password': password});

  Future<void> signOut() async {
    await firestore.live.close();
    await _set(null, null);
  }

  Future<void> changePassword(String current, String next) async {
    try {
      await client.post('/auth/password', {'current': current, 'next': next});
    } catch (e) {
      throw authError(e, unauthorized: 'wrong-password');
    }
  }

  Future<void> deleteOwnLogin(String password) async {
    try {
      await client.post('/auth/delete', {'current': password});
    } catch (e) {
      throw authError(e, unauthorized: 'wrong-password');
    }
    await signOut();
  }

  /// Bosh admin xodim akkaunti ochadi (profil — rol 'user'), uid qaytaradi
  Future<String> createStaff(String name, String phone, String password) async {
    try {
      final res = await client.post('/auth/staff', {'name': name, 'phone': phone, 'password': password}) as Map;
      return res['uid'] as String;
    } catch (e) {
      throw authError(e, forbidden: 'operation-not-allowed');
    }
  }
}
