import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Ochiq WebSocket (brauzer): kelgan matnlar va yuborish
class ApiSocket {
  ApiSocket._(this._ws, this._messages);
  final JSObject _ws;
  final StreamController<String> _messages;

  Stream<String> get messages => _messages.stream;
  void send(String text) => _ws.callMethod('send'.toJS, text.toJS);
  Future<void> close() async {
    _ws.callMethod('close'.toJS);
    await _messages.close();
  }
}

Future<ApiSocket> connectSocket(String url) {
  final ws = (globalContext['WebSocket'] as JSFunction).callAsConstructor<JSObject>(url.toJS);
  final messages = StreamController<String>();
  final opened = Completer<ApiSocket>();
  ws['onopen'] = ((JSAny _) {
    if (!opened.isCompleted) opened.complete(ApiSocket._(ws, messages));
  }).toJS;
  ws['onmessage'] = ((JSObject e) {
    final data = e['data'].dartify();
    if (data is String) messages.add(data);
  }).toJS;
  ws['onclose'] = ((JSAny _) {
    if (!opened.isCompleted) opened.completeError(StateError('websocket ulanmadi'));
    if (!messages.isClosed) messages.close();
  }).toJS;
  return opened.future;
}
