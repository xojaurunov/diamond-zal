import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotta_qani_diet/models/exercises.dart';
import 'package:kotta_qani_diet/models/lesson.dart';
import 'package:kotta_qani_diet/models/models.dart';
import 'package:kotta_qani_diet/models/video_link.dart';
import 'package:kotta_qani_diet/screens/admin/lessons_admin_screen.dart';
import 'package:kotta_qani_diet/screens/user/videos_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const r2 = 'https://qobil-video.qobilfitness.workers.dev/v/videos/123e4567-e89b-12d3-a456-426614174000.mp4';
const yt = 'https://youtu.be/dQw4w9WgXcQ';

Exercise ex(String name, String muscle, String video, {DateTime? at, String level = ''}) =>
    Exercise(name, muscle, '4 × 10', 'Sekin bajaring', id: name, video: video, level: level,
        createdAt: at ?? DateTime(2026, 1, 1), createdBy: 't1');

AppUser student({Map<String, List<String>> program = const {}}) =>
    AppUser(id: 's1', name: 'Shogird', email: '', gymDays: const [2, 4, 6], program: program);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Videolar — muqova va tasma', () {
    test("muqova: yuklangan video yonidagi .jpg, YouTube o'z muqovasi, boshqasi yo'q", () {
      expect(thumbOf(r2), r2.replaceFirst('.mp4', '.jpg'));
      expect(thumbOf(yt), 'https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg');
      expect(thumbOf('https://t.me/kanal/5'), isNull);
    });

    test("tasma: faqat videosi bor mashqlar va darslar; shogirdning o'z mashqi tepada", () {
      final a = ex('A mashq', 'chest', r2);
      final b = ex('B mashq', 'chest', yt);
      final noVideo = ex('Videosiz', 'chest', '');
      const lesson = Lesson(title: 'Ovqatlanish', category: 'ovqatlanish', url: r2, seconds: 125);
      final items = buildVideoItems(
          student(program: {'chest': [b.key]}), [a, b, noVideo], const [lesson]);
      expect(items.map((i) => i.title).toSet(), {'A mashq', 'B mashq', 'Ovqatlanish'});
      expect(items.first.title, 'B mashq');
      expect(items.first.mine, isTrue);
      expect(items.where((i) => i.title == 'Videosiz'), isEmpty);
      expect(items.firstWhere((i) => i.lesson != null).subtitle(), contains('2:05'));
    });

    test("trener uchun 'Siz uchun' belgisi yo'q", () {
      final trainer = AppUser(id: 't1', name: 'Trener', email: '', role: 'admin');
      final items = buildVideoItems(trainer, [ex('A mashq', 'chest', r2)], const []);
      expect(items.single.mine, isFalse);
    });

    test('davomiylik matni', () {
      expect(durationText(0), '');
      expect(durationText(65), '1:05');
      expect(durationText(240), '4:00');
    });
  });

  group('Videolar — ekran', () {
    Future<void> open(WidgetTester t, {List<Exercise> exercises = const [], List<Lesson> lessons = const []}) async {
      t.view.physicalSize = const Size(420, 4000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        home: VideosScreen(user: student(), custom: Stream.value(exercises), lessons: Stream.value(lessons)),
      ));
      await t.pump();
    }

    final exercises = [ex('Shtanga bilan jim', 'chest', r2), ex('Prisedanie', 'quads', yt)];
    const lessons = [Lesson(title: 'Nafas olish', category: 'nafas', url: r2, seconds: 90)];

    testWidgets("hamma videolar, filtr 'Darslar' va qidiruv", (t) async {
      await open(t, exercises: exercises, lessons: lessons);
      expect(find.text('Shtanga bilan jim'), findsOneWidget);
      expect(find.text('Prisedanie'), findsOneWidget);
      expect(find.text('Nafas olish'), findsOneWidget);
      await t.tap(find.text('Darslar'));
      await t.pump();
      expect(find.text('Shtanga bilan jim'), findsNothing);
      expect(find.text('Nafas olish'), findsOneWidget);
      await t.tap(find.text('Hammasi'));
      await t.pump();
      await t.enterText(find.byType(TextField), 'prised');
      await t.pump();
      expect(find.text('Prisedanie'), findsOneWidget);
      expect(find.text('Shtanga bilan jim'), findsNothing);
    });

    testWidgets("video yo'q — tushuntirish", (t) async {
      await open(t);
      expect(find.textContaining("Hali video yo'q"), findsOneWidget);
    });

    testWidgets('video sahifasi: tezlik tanlanadi, mashq izohi ko\'rinadi', (t) async {
      final played = <double>[];
      debugVideoPagePlayer = (url, speed) {
        played.add(speed);
        return const SizedBox(key: Key('pleyer'));
      };
      addTearDown(() => debugVideoPagePlayer = null);
      await open(t, exercises: exercises);
      await t.tap(find.text('Shtanga bilan jim'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('pleyer')), findsOneWidget);
      expect(find.text('Sekin bajaring'), findsOneWidget);
      await t.tap(find.text('0.5x'));
      await t.pump();
      expect(played.last, 0.5);
    });
  });

  group('Dars formasi', () {
    testWidgets("nomsiz va videosiz dars saqlanmaydi", (t) async {
      t.view.physicalSize = const Size(420, 3000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: LessonForm(adminId: 't1'))));
      await t.tap(find.text('Saqlash'));
      await t.pump();
      expect(find.text('Dars nomini yozing'), findsOneWidget);
      await t.enterText(find.byType(TextField).first, 'Ovqatlanish asoslari');
      await t.tap(find.text('Saqlash'));
      await t.pump();
      expect(find.text("Video yuklang yoki havola qo'ying"), findsOneWidget);
    });
  });
}
