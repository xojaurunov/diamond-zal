import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';

/// `users/{uid}/photos/{id}` — shogirdning "oldin / keyin" rasmi.
/// Rasm siqilgan holda hujjatning o'zida saqlanadi (Cloud Storage Blaze tarifini talab qiladi).
class ProgressPhoto {
  /// Firestore hujjati 1 MB dan oshmasligi kerak — rasm uchun chegara (qoidalarda ham shu)
  static const maxBytes = 350 * 1024;

  final String id;
  final Uint8List bytes;
  final DateTime? takenAt;

  /// Rasm olingan paytdagi vazn (0 — noma'lum)
  final double weight;

  const ProgressPhoto({this.id = '', required this.bytes, this.takenAt, this.weight = 0});

  factory ProgressPhoto.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return ProgressPhoto(
      id: doc.id,
      bytes: (d['data'] as Blob?)?.bytes ?? Uint8List(0),
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
