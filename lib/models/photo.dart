import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';

/// `users/{uid}/photos/{id}` — shogirdning "oldin / keyin" rasmi.
/// Ikki shakl: eski — rasm siqilgan holda hujjatning o'zida (`data`, 350 KB gacha);
/// yangi (11-noy) — rasm Cloudflare R2'da, hujjatda faqat kalit (`key`). Yangi rasmni Worker
/// faqat ko'rish huquqi borga beradi (ommaviy havola yo'q).
class ProgressPhoto {
  /// Firestore hujjati 1 MB dan oshmasligi kerak — eski shakl uchun chegara (qoidalarda ham shu)
  static const maxBytes = 350 * 1024;

  /// R2'ga yuklanadigan rasm chegarasi (Worker `MAX_PHOTO_BYTES` bilan bir xil)
  static const maxRemoteBytes = 1024 * 1024;

  final String id;

  /// Egasi (hujjat yo'li `users/{uid}/photos/{id}` dan)
  final String uid;

  /// Eski shakl — rasmning o'zi; yangi shaklda bo'sh
  final Uint8List bytes;

  /// Yangi shakl — R2 kaliti (`photos/<uid>/<uuid>.jpg`); eski shaklda bo'sh
  final String key;
  final DateTime? takenAt;

  /// Rasm olingan paytdagi vazn (0 — noma'lum)
  final double weight;

  ProgressPhoto({
    this.id = '',
    this.uid = '',
    Uint8List? bytes,
    this.key = '',
    this.takenAt,
    this.weight = 0,
  }) : bytes = bytes ?? Uint8List(0);

  /// Rasm R2'da (serverdan yuklab ko'rsatiladi)
  bool get isRemote => key.isNotEmpty;

  /// Eski shakl — R2'ga ko'chirilishi kerak
  bool get needsMigration => !isRemote && bytes.isNotEmpty;

  factory ProgressPhoto.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return ProgressPhoto(
      id: doc.id,
      uid: doc.reference.parent.parent?.id ?? '',
      bytes: (d['data'] as Blob?)?.bytes,
      key: (d['key'] ?? '') as String,
      takenAt: (d['takenAt'] as Timestamp?)?.toDate(),
      weight: ((d['weight'] ?? 0) as num).toDouble(),
    );
  }

  /// Sana: "05.10.2026"
  String get dateLabel {
    final d = takenAt;
    if (d == null) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year}';
  }
}

/// Rasm turi baytlaridan: JPEG / WebP (R2 qabul qiladi), boshqasi — null
String? photoContentType(Uint8List b) {
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'image/jpeg';
  if (b.length >= 12 &&
      String.fromCharCodes(b.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(b.sublist(8, 12)) == 'WEBP') {
    return 'image/webp';
  }
  return null;
}
