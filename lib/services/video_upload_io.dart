import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:video_compress/video_compress.dart';

import '../models/video_link.dart';
import 'video_upload_common.dart';

/// Telefonda yuklash mumkin (server manzili qurishda berilgan bo'lsa)
bool get canUploadVideo => videoServer.isNotEmpty;

/// Kichraytirish sifatlari — birinchisidan boshlab; natija [maxVideoBytes] dan katta bo'lsa keyingisi
const _qualities = [VideoQuality.Res1280x720Quality, VideoQuality.Res960x540Quality, VideoQuality.Res640x480Quality];

/// Videoni yuklaydi, R2 havolasini qaytaradi. [compressAboveBytes] dan katta video avval telefonda
/// kichraytiriladi (asl fayl galereyada o'zgarmay qoladi). [onCompress], [onProgress] — 0..1.
Future<String> uploadVideo(String path, String fileName,
    {void Function(double)? onProgress, void Function(double)? onCompress}) async {
  if (videoContentType(fileName) == null) throw const VideoUploadError(415);
  final info = await VideoCompress.getMediaInfo(path);
  if ((info.duration ?? 0) / 1000 > maxVideoSeconds) throw const VideoUploadError(VideoUploadError.tooLong);
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
    return await _send(file, name, onProgress);
  } finally {
    // kichraytirilgan vaqtinchalik fayllar telefonda joy egallamasin
    if (compressed) unawaited(VideoCompress.deleteAllCache().then((_) {}, onError: (_) {}));
  }
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
