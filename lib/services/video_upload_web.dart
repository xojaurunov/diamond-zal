import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import '../models/video_link.dart';
import 'video_upload_common.dart';

/// Brauzerda yuklash yo'q — trener paneli webda video havolasi qo'yadi
bool get canUploadVideo => false;

Future<String> uploadVideo(String path, String fileName, {void Function(double)? onProgress}) =>
    throw UnsupportedError('video yuklash faqat telefonda');

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
