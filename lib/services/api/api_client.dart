import 'dart:convert';

import 'package:http/http.dart' as http;

/// Qobil servisi manzili. Qurishda beriladi: `--dart-define=API_URL=https://...`.
/// Bo'sh bo'lsa ilova avvalgidek Firebase bilan ishlaydi.
const apiUrl = String.fromEnvironment('API_URL');

/// Ilova Python servis bilan ishlayaptimi (aks holda Firebase)
const useApi = apiUrl != '';

/// Servis javobidagi xato (holat kodi va servis matni)
class ApiException implements Exception {
  final int status;
  final String message;
  const ApiException(this.status, this.message);

  @override
  String toString() => message;
}

/// Servisga HTTP so'rovlar. Token har so'rovga `Authorization: Bearer` bo'lib qo'shiladi;
/// 401 kelsa [onUnauthorized] chaqiriladi (muddati o'tgan / o'chirilgan akkaunt — chiqish).
class ApiClient {
  ApiClient(String base, {http.Client? client})
      : base = base.endsWith('/') ? base.substring(0, base.length - 1) : base,
        _http = client ?? http.Client();

  final String base;
  final http.Client _http;
  String? token;
  void Function()? onUnauthorized;

  /// WebSocket manzili (`http` -> `ws`, `https` -> `wss`). Token manzilda emas — servis jurnaliga
  /// tushmasin; ulangach birinchi xabar bilan yuboriladi ([ApiLive]).
  String get socketUrl => '${base.replaceFirst(RegExp('^http'), 'ws')}/ws';

  Future<dynamic> send(String method, String path, {Map<String, String>? query, Object? body}) async {
    final uri = Uri.parse('$base$path').replace(queryParameters: query);
    final req = http.Request(method, uri)..headers['content-type'] = 'application/json';
    if (token != null) req.headers['authorization'] = 'Bearer $token';
    if (body != null) req.body = jsonEncode(body);
    final res = await http.Response.fromStream(await _http.send(req));
    if (res.statusCode == 401 && token != null) onUnauthorized?.call();
    if (res.statusCode >= 400) {
      var message = 'xato ${res.statusCode}';
      try {
        message = (jsonDecode(res.body) as Map)['detail'].toString();
      } catch (_) {}
      throw ApiException(res.statusCode, message);
    }
    return res.body.isEmpty ? null : jsonDecode(res.body);
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) => send('GET', path, query: query);
  Future<dynamic> post(String path, Object body) => send('POST', path, body: body);
}
