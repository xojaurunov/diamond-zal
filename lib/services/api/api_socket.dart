/// WebSocket — telefonda `dart:io`, brauzerda brauzerning o'zi (yangi paket kerak emas).
library;

export 'api_socket_io.dart' if (dart.library.js_interop) 'api_socket_web.dart';
