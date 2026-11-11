import 'dart:typed_data';

import '../models/photo.dart';
import 'video_upload.dart';

/// R2'dagi progress rasmlari xotirada (ilova ochiq turganda): bir rasm bir marta yuklanadi.
/// Diskka yozilmaydi — tana rasmi telefonda fayl bo'lib qolmasin.
class ProgressPhotoCache {
  static final _byKey = <String, Future<Uint8List>>{};

  /// Testlar uchun almashtiriladi (tarmoqsiz)
  static Future<Uint8List> Function(String uid, String id) loader = fetchProgressPhoto;

  /// Yuklangan yoki ko'chirilgan rasm — qayta yuklab olmaslik uchun
  static void put(String key, Uint8List bytes) => _byKey[key] = Future.value(bytes);

  /// Rasm baytlari: eski shakl — hujjatdan, yangisi — serverdan (xato bo'lsa keyingi safar qayta urinadi)
  static Future<Uint8List> load(ProgressPhoto p) {
    if (!p.isRemote) return Future.value(p.bytes);
    return _byKey[p.key] ??= loader(p.uid, p.id).catchError((Object e) {
      _byKey.remove(p.key);
      throw e;
    });
  }

  static void clear() => _byKey.clear();
}
