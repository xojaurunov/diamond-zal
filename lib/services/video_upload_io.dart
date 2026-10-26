import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:video_compress/video_compress.dart';

import '../models/video_link.dart';
import 'video_upload_common.dart';

/// Telefonda yuklash mumkin (server manzili qurishda berilgan bo'lsa)
bool get canUploadVideo => videoServer.isNotEmpty;

/// Kichraytirish sifatlari — birinchisidan boshlab; natija [maxVideoBytes] dan katta bo'lsa keyingisi
const _qualities = [VideoQuality.Res1280x720Quality, VideoQuality.Res960x540Quality, VideoQuality.Res640x480Quality];

/// Videoni yuklaydi, R2 havolasi va davomiyligini qaytaradi. [compressAboveBytes] dan katta video avval
/// telefonda kichraytiriladi (asl fayl galereyada o'zgarmay qoladi). Keyin muqova (birinchi kadr) qo'yiladi.
/// [onCompress], [onProgress] — 0..1.
Future<UploadedVideo> uploadVideo(String path, String fileName,
    {void Function(double)? onProgress, void Function(double)? onCompress}) async {
  if (videoContentType(fileName) == null) throw const VideoUploadError(415);
  final info = await VideoCompress.getMediaInfo(path);
  final seconds = ((info.duration ?? 0) / 1000).round();
  if (seconds > maxVideoSeconds) throw const VideoUploadError(VideoUploadError.tooLong);
  var file = File(path);
  var name = fileName;
  var compressed = false;
  try {
    if (await file.length() > compressAboveBytes) {
      for (final quality in _qualities) {
        final out = await _compress(path, quality, onCompress);
        if (out == null) throw const VideoUploadError(VideoUploadError.compressFailed);
        file = out;
        name = 'video.mp4';
        compressed = true;
        if (await file.length() <= maxVideoBytes) break;
      }
    }
    final url = await _send(file, name, onProgress);
    // muqova — kichraytirilgan fayldan (kichik va tez); bo'lmasa video muqovasiz ham ishlaydi
    await _sendThumb(file.path, url);
    return UploadedVideo(url, seconds);
  } finally {
    // kichraytirilgan vaqtinchalik fayllar telefonda joy egallamasin
    if (compressed) unawaited(VideoCompress.deleteAllCache().then((_) {}, onError: (_) {}));
  }
}

/// Muqova: birinchi kadr JPEG (512 KB gacha) video yonidagi `.jpg` ga. Xatosi yuklashni to'xtatmaydi.
Future<void> _sendThumb(String videoPath, String videoUrl) async {
  try {
    Uint8List? jpg;
    for (final q in [70, 45, 25]) {
      jpg = await VideoCompress.getByteThumbnail(videoPath, quality: q, position: -1);
      if (jpg != null && jpg.length <= 500 * 1024) break;
    }
    if (jpg == null || jpg.length > 500 * 1024) return;
    final token = await videoAuthToken();
    final client = HttpClient();
    try {
      final req = await client.putUrl(Uri.parse(thumbOf(videoUrl)!));
      req.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
        ..set(HttpHeaders.contentTypeHeader, 'image/jpeg');
      req.contentLength = jpg.length;
      req.add(jpg);
      await (await req.close()).drain<void>();
    } finally {
      client.close();
    }
  } catch (_) {}
}

/// Yarim yo'lda to'xtatish (forma yopilganda)
Future<void> cancelVideoUpload() async {
  try {
    await VideoCompress.cancelCompression();
  } catch (_) {}
}

Future<File?> _compress(String path, VideoQuality quality, void Function(double)? onCompress) async {
  final sub = VideoCompress.compressProgress$.subscribe((p) => onCompress?.call((p / 100).clamp(0.0, 1.0)));
  try {
    final out = await VideoCompress.compressVideo(path, quality: quality, deleteOrigin: false, includeAudio: true);
    return out?.file;
  } catch (_) {
    return null;
  } finally {
    sub.unsubscribe();
  }
}

Future<String> _send(File file, String fileName, void Function(double)? onProgress) async {
  final type = videoContentType(fileName);
  if (type == null) throw const VideoUploadError(415);
  final size = await file.length();
  if (size > maxVideoBytes) throw const VideoUploadError(413);
  final token = await videoAuthToken();
  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.parse('$videoServer/upload'));
    req.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
      ..set(HttpHeaders.contentTypeHeader, type);
    req.contentLength = size;
    var sent = 0;
    await req.addStream(file.openRead().map((chunk) {
      sent += chunk.length;
      onProgress?.call(sent / size);
      return chunk;
    }));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) throw VideoUploadError(res.statusCode);
    return (jsonDecode(body) as Map<String, dynamic>)['url'] as String;
  } finally {
    client.close();
  }
}

/// R2'dan o'chiradi (yuklangan video bo'lmasa — hech narsa qilmaydi)
Future<void> deleteVideo(String url) async {
  if (!isOwnVideo(url)) return; // begona havolaga token yuborilmaydi
  final token = await videoAuthToken();
  final client = HttpClient();
  try {
    final req = await client.deleteUrl(Uri.parse(url.trim()));
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    final res = await req.close();
    await res.drain<void>();
    if (res.statusCode != 204 && res.statusCode != 404) throw VideoUploadError(res.statusCode);
  } finally {
    client.close();
  }
}
