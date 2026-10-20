import 'dart:io';

/// Ochiq WebSocket: kelgan matnlar va yuborish
class ApiSocket {
  ApiSocket._(this._ws);
  final WebSocket _ws;

  Stream<String> get messages => _ws.where((m) => m is String).cast<String>();
  void send(String text) => _ws.add(text);
  Future<void> close() => _ws.close();
}

Future<ApiSocket> connectSocket(String url) async => ApiSocket._(await WebSocket.connect(url));
