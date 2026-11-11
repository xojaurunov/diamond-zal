import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import '../models/video_link.dart';
import 'video_upload_common.dart';

/// Brauzerda yuklash yo'q — trener paneli webda video havolasi qo'yadi
bool get canUploadVideo => false;

Future<UploadedVideo> uploadVideo(String path, String fileName,
        {void Function(double)? onProgress, void Function(double)? onCompress}) =>
    throw UnsupportedError('video yuklash faqat telefonda');

Future<void> cancelVideoUpload() async {}

/// R2'dan o'chiradi (mashq webda o'chirilganda ham fayl qolib ketmasin)
Future<void> deleteVideo(String url) async {
  if (!isOwnVideo(url)) return; // begona havolaga token yuborilmaydi
  final token = await videoAuthToken();
  final init = JSObject()
    ..setProperty('method'.toJS, 'DELETE'.toJS)
    ..setProperty('headers'.toJS, JSObject()..setProperty('authorization'.toJS, 'Bearer $token'.toJS));
  final res = await (globalContext.callMethod<JSPromise<JSObject>>('fetch'.toJS, url.trim().toJS, init)).toDart;
  final status = (res.getProperty<JSNumber>('status'.toJS)).toDartInt;
  if (status != 204 && status != 404) throw VideoUploadError(status);
}

/// Profil rasmini yuklaydi (eskisi serverda o'chadi), havolasini qaytaradi
Future<String> uploadAvatar(Uint8List bytes, String contentType) async {
  final token = await videoAuthToken();
  final init = JSObject()
    ..setProperty('method'.toJS, 'POST'.toJS)
    ..setProperty(
        'headers'.toJS,
        JSObject()
          ..setProperty('authorization'.toJS, 'Bearer $token'.toJS)
          ..setProperty('content-type'.toJS, contentType.toJS))
    ..setProperty('body'.toJS, bytes.toJS);
  final res =
      await (globalContext.callMethod<JSPromise<JSObject>>('fetch'.toJS, '$videoServer/avatar'.toJS, init)).toDart;
  final status = (res.getProperty<JSNumber>('status'.toJS)).toDartInt;
  if (status != 200) throw AvatarUploadError(status);
  final body = await res.callMethod<JSPromise<JSObject>>('json'.toJS).toDart;
  return (body.getProperty<JSString>('url'.toJS)).toDart;
}

/// O'z profil rasmini serverdan o'chiradi
Future<void> deleteAvatar() async {
  final token = await videoAuthToken();
  final init = JSObject()
    ..setProperty('method'.toJS, 'DELETE'.toJS)
    ..setProperty('headers'.toJS, JSObject()..setProperty('authorization'.toJS, 'Bearer $token'.toJS));
  final res =
      await (globalContext.callMethod<JSPromise<JSObject>>('fetch'.toJS, '$videoServer/avatar'.toJS, init)).toDart;
  final status = (res.getProperty<JSNumber>('status'.toJS)).toDartInt;
  if (status != 204) throw AvatarUploadError(status);
}

/// "Oldin / keyin" rasmini R2'ga yuklaydi (faqat o'ziga), kalitini qaytaradi
Future<String> uploadProgressPhoto(Uint8List bytes, String contentType) async {
  final token = await videoAuthToken();
  final init = JSObject()
    ..setProperty('method'.toJS, 'POST'.toJS)
    ..setProperty(
        'headers'.toJS,
        JSObject()
          ..setProperty('authorization'.toJS, 'Bearer $token'.toJS)
          ..setProperty('content-type'.toJS, contentType.toJS))
    ..setProperty('body'.toJS, bytes.toJS);
  final res =
      await (globalContext.callMethod<JSPromise<JSObject>>('fetch'.toJS, '$videoServer/photo'.toJS, init)).toDart;
  final status = (res.getProperty<JSNumber>('status'.toJS)).toDartInt;
  if (status != 200) throw AvatarUploadError(status);
  final body = await res.callMethod<JSPromise<JSObject>>('json'.toJS).toDart;
  return (body.getProperty<JSString>('key'.toJS)).toDart;
}

/// Progress rasmini serverdan oladi — Worker ruxsatni Firestore qoidalari bilan tekshiradi
Future<Uint8List> fetchProgressPhoto(String uid, String id) async {
  final token = await videoAuthToken();
  final init = JSObject()
    ..setProperty('headers'.toJS, JSObject()..setProperty('authorization'.toJS, 'Bearer $token'.toJS));
  final res = await (globalContext.callMethod<JSPromise<JSObject>>(
          'fetch'.toJS, '$videoServer/p/$uid/$id'.toJS, init))
      .toDart;
  final status = (res.getProperty<JSNumber>('status'.toJS)).toDartInt;
  if (status != 200) throw AvatarUploadError(status);
  final buf = await res.callMethod<JSPromise<JSArrayBuffer>>('arrayBuffer'.toJS).toDart;
  return buf.toDart.asUint8List();
}

/// O'z progress rasmini R2'dan o'chiradi (yo'q bo'lsa — xato emas)
Future<void> deleteProgressPhoto(String key) async {
  final token = await videoAuthToken();
  final init = JSObject()
    ..setProperty('method'.toJS, 'DELETE'.toJS)
    ..setProperty('headers'.toJS, JSObject()..setProperty('authorization'.toJS, 'Bearer $token'.toJS));
  final res = await (globalContext.callMethod<JSPromise<JSObject>>(
          'fetch'.toJS, '$videoServer/photo/${Uri.encodeComponent(key)}'.toJS, init))
      .toDart;
  final status = (res.getProperty<JSNumber>('status'.toJS)).toDartInt;
  if (status != 204 && status != 404) throw AvatarUploadError(status);
}
