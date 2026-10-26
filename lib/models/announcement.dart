import 'package:cloud_firestore/cloud_firestore.dart';

/// `announcements/{id}` — zal e'loni: trener yoki bosh admin yozadi, hamma shogird
/// "Bugun" ekranining tepasida ko'radi. Tahrir yo'q — o'chirib, qayta yoziladi.
class Announcement {
  /// Matn chegarasi (qoidalarda ham shu)
  static const maxLength = 500;

  /// Shogird banner sifatida necha kun ko'radi
  static const showDays = 7;

  final String id;
  final String text;

  /// Server vaqti; yozilayotgan paytda (hali serverga yetmagan) — null
  final DateTime? createdAt;
  final String createdBy;

  const Announcement({this.id = '', required this.text, this.createdAt, this.createdBy = ''});

  factory Announcement.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return Announcement(
      id: doc.id,
      text: (d['text'] ?? '').toString(),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      createdBy: (d['createdBy'] ?? '').toString(),
    );
  }

  /// Bannerda ko'rinadimi: oxirgi [showDays] kun ichida yozilgan
  bool isFresh([DateTime? now]) {
    final at = createdAt;
    if (at == null) return true;
    return (now ?? DateTime.now()).difference(at) < const Duration(days: showDays);
  }

  /// Sana: "05.10.2026"
  String get dateLabel {
    final d = createdAt;
    if (d == null) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year}';
  }
}
