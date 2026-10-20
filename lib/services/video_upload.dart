/// Mashq videosini yuklash va o'chirish — Cloudflare R2 (`cloudflare/video` Worker orqali).
/// Telefonda yuklash va o'chirish; brauzerda faqat o'chirish (trener paneli webda havola qo'yadi).
library;

export 'video_upload_common.dart';
export 'video_upload_io.dart' if (dart.library.js_interop) 'video_upload_web.dart';
