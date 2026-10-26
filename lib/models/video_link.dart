// Mashq videosi havolasini tahlil qilish. Video fayl ilovada saqlanmaydi — trener havola
// qo'yadi; YouTube havolasi bo'lsa ilova ichida o'ynatiladi va muqova rasmi ko'rsatiladi.

/// YouTube video id'si ([url] YouTube havolasi bo'lmasa — null).
/// Tushunadi: `youtu.be/ID`, `youtube.com/watch?v=ID`, `/shorts/ID`, `/embed/ID`, `/live/ID`,
/// `m.youtube.com`, `music.youtube.com`, `youtube-nocookie.com`.
String? youtubeId(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null || !u.hasScheme) return null;
  final host = u.host.toLowerCase().replaceFirst(RegExp(r'^(www|m|music)\.'), '');
  final parts = u.pathSegments.where((p) => p.isNotEmpty).toList();
  String? id;
  if (host == 'youtu.be') {
    id = parts.isEmpty ? null : parts.first;
  } else if (host == 'youtube.com' || host == 'youtube-nocookie.com') {
    if (parts.isNotEmpty && parts.first == 'watch') {
      id = u.queryParameters['v'];
    } else if (parts.length >= 2 && const {'shorts', 'embed', 'live', 'v'}.contains(parts.first)) {
      id = parts[1];
    }
  }
  // YouTube id'si: 11 ta belgi (harf, raqam, - va _)
  return id != null && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id) ? id : null;
}

/// YouTube videosining muqova rasmi (kalit kerak emas); YouTube bo'lmasa — null
String? youtubeThumb(String url) {
  final id = youtubeId(url);
  return id == null ? null : 'https://img.youtube.com/vi/$id/hqdefault.jpg';
}

// ---------- yuklangan video (Cloudflare R2, `cloudflare/video` Worker) ----------

/// Video serveri manzili (Worker, `cloudflare/video`; Cloudflare akkaunti Xojaurunov, bucket `qobil-video`).
/// Qurishda almashtirish mumkin: `--dart-define=VIDEO_SERVER=https://...`; bo'sh — yuklash tugmasi yo'q.
const videoServer =
    String.fromEnvironment('VIDEO_SERVER', defaultValue: 'https://qobil-video.qobilfitness.workers.dev');

/// Yuklanadigan (kichraytirilgan) video hajmi chegarasi (Worker ham shuni tekshiradi)
const maxVideoBytes = 80 * 1024 * 1024;

/// Video davomiyligi chegarasi: 5 daqiqa + 30 soniya zaxira
const maxVideoSeconds = 330;

/// Shundan katta video yuklashdan oldin telefonda kichraytiriladi (kichigi — o'zicha, tez)
const compressAboveBytes = 20 * 1024 * 1024;

final _uploaded =
    RegExp(r'^https://[a-z0-9-]+\.[a-z0-9-]+\.workers\.dev/v/videos/[0-9a-f-]{36}\.(mp4|mov|webm|3gp)$');

/// Trener ilovadan yuklagan video havolasimi (Cloudflare Worker orqali R2'dagi fayl)
bool isUploadedVideo(String url) => _uploaded.hasMatch(url.trim());

/// Fayl nomidan video turi (Worker qabul qiladiganlari); boshqa tur — null
/// Shu ilovaning video serveridagi fayl — faqat shunga o'chirish so'rovi (kirish tokeni bilan) boradi.
/// Begona havolaga token yuborilmaydi.
bool isOwnVideo(String url) =>
    videoServer.isNotEmpty && isUploadedVideo(url) && url.trim().startsWith('$videoServer/v/videos/');

String? videoContentType(String fileName) => switch (fileName.split('.').last.toLowerCase()) {
      'mp4' || 'm4v' => 'video/mp4',
      'mov' => 'video/quicktime',
      'webm' => 'video/webm',
      '3gp' => 'video/3gpp',
      _ => null,
    };

/// Video muqovasi: yuklangan video — yonidagi `.jpg` (trener yuklaganda ilova o'zi qo'yadi;
/// eski videolarda bo'lmasligi mumkin), YouTube — o'z muqovasi; boshqa havola — null
String? thumbOf(String url) {
  final u = url.trim();
  if (isUploadedVideo(u)) return u.replaceFirst(RegExp(r'\.[a-z0-9]+$'), '.jpg');
  return youtubeThumb(u);
}
