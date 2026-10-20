import 'dart:convert';
import 'dart:io';

import '../models/video_link.dart';
import 'video_upload_common.dart';

/// Telefonda yuklash mumkin (server manzili qurishda berilgan bo'lsa)
bool get canUploadVideo => videoServer.isNotEmpty;

/// Faylni yuklaydi, R2 havolasini qaytaradi. [onProgress] — 0..1.
Future<String> uploadVideo(String path, String fileName, {void Function(double)? onProgress}) async {
  final type = videoContentType(fileName);
  if (type == null) throw const VideoUploadError(415);
  final file = File(path);
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
