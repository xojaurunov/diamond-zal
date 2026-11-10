import 'package:cloud_firestore/cloud_firestore.dart';

/// Dars turlari (kalit — bazada, qiymat — ekranda, tarjima qilinadi)
const lessonCategories = {
  'texnika': 'Texnika',
  'ovqatlanish': 'Ovqatlanish',
  'nafas': "Nafas va cho'zilish",
  'motivatsiya': 'Motivatsiya',
  'boshqa': 'Boshqa',
};

/// Trener darsi (`videos/{id}`) — mashqqa bog'liq bo'lmagan video: ovqatlanish, texnika, motivatsiya…
/// Mashq videolari o'z mashqida turadi (`Exercise.video`); "Videolar" bo'limi ikkalasini birga ko'rsatadi.
class Lesson {
  final String id;
  final String title;
  final String category;
  final String description;
  final String url;

  /// Davomiyligi, soniya (noma'lum — 0)
  final int seconds;
  final DateTime? createdAt;
  final String createdBy;

  const Lesson({
    this.id = '',
    required this.title,
    required this.category,
    this.description = '',
    required this.url,
    this.seconds = 0,
    this.createdAt,
    this.createdBy = '',
  });

  /// Oxirgi 7 kunda qo'shilgan — "YANGI"
  bool isNew([DateTime? now]) =>
      createdAt != null && (now ?? DateTime.now()).difference(createdAt!) < const Duration(days: 7);

  factory Lesson.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    final at = d['createdAt'];
    return Lesson(
      id: doc.id,
      title: (d['title'] ?? '').toString(),
      category: (d['category'] ?? 'boshqa').toString(),
      description: (d['description'] ?? '').toString(),
      url: (d['url'] ?? '').toString(),
      seconds: (d['seconds'] as num?)?.toInt() ?? 0,
      createdAt: at is int ? DateTime.fromMillisecondsSinceEpoch(at) : null,
      createdBy: (d['createdBy'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'category': category,
        'description': description,
        'url': url,
        'seconds': seconds,
        'createdAt': (createdAt ?? DateTime.now()).millisecondsSinceEpoch,
        'createdBy': createdBy,
      };
}

/// "3:05" ko'rinishida (0 — bo'sh)
String durationText(int seconds) =>
    seconds <= 0 ? '' : '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
