import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotta_qani_diet/models/announcement.dart';
import 'package:kotta_qani_diet/models/exercises.dart';
import 'package:kotta_qani_diet/models/gym.dart';
import 'package:kotta_qani_diet/models/models.dart';
import 'package:kotta_qani_diet/models/photo.dart';
import 'package:kotta_qani_diet/screens/admin/announcements_admin_screen.dart';
import 'package:kotta_qani_diet/screens/user/muscles_screen.dart';
import 'package:kotta_qani_diet/widgets/announcements.dart';
import 'package:kotta_qani_diet/widgets/before_after.dart';

/// 1Г—1 PNG вЂ” test rasmi
final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');

void main() {
  group('Oldin / keyin slayderi', () {
    final photos = [
      ProgressPhoto(id: 'a', bytes: _png, takenAt: DateTime(2026, 1, 5), weight: 90),
      ProgressPhoto(id: 'b', bytes: _png, takenAt: DateTime(2026, 3, 5), weight: 84),
      ProgressPhoto(id: 'c', bytes: _png, takenAt: DateTime(2026, 6, 5), weight: 79),
    ];

    testWidgets("standart: birinchi va oxirgi; chiziq surilsa 'oldin' qismi o'zgaradi", (t) async {
      t.view.physicalSize = const Size(420, 1200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        home: BeforeAfterPage(photos: photos, caption: (p) => '${p.weight.round()} kg'),
      ));
      expect(find.text('90 kg'), findsOneWidget, reason: 'oldin вЂ” birinchi rasm');
      expect(find.text('79 kg'), findsOneWidget, reason: 'keyin вЂ” oxirgi rasm');
      Align clip() => t.widget<Align>(find.byKey(const Key('oldin-qismi')));
      expect(clip().widthFactor, 0.5);
      final box = t.getRect(find.byType(BeforeAfterSlider));
      await t.tapAt(Offset(box.left + box.width * 0.2, box.center.dy));
      await t.pump();
      expect(clip().widthFactor, closeTo(0.2, 0.02));
      await t.drag(find.byType(BeforeAfterSlider), const Offset(200, 0));
      await t.pump();
      expect(clip().widthFactor, greaterThan(0.5));
    });
  });

  group('Dam olish taymeri', () {
    testWidgets("'Bajardim' вЂ” 90 s hisob; tanlov, o'tkazish, tugashi", (t) async {
      t.view.physicalSize = const Size(420, 7000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        home: MusclesScreen(gymDays: evenDays, weekday: DateTime.tuesday, onBack: () {}),
      ));
      await t.pump(const Duration(seconds: 3));
      await t.tap(find.text("Mashg'ulotni boshlash"));
      await t.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('dam-olish')), findsNothing, reason: 'hali hech narsa bajarilmadi');

      await t.tap(find.text('Bajardim').first);
      await t.pump();
      expect(find.text('1:30'), findsOneWidget, reason: 'standart 90 s');
      await t.pump(const Duration(seconds: 5));
      expect(find.text('1:25'), findsOneWidget);

      await t.tap(find.text('60 s'));
      await t.pump();
      expect(find.text('1:00'), findsOneWidget, reason: 'boshqa vaqt вЂ” qaytadan');
      await t.pump(const Duration(seconds: 61));
      expect(find.byKey(const Key('dam-olish')), findsNothing, reason: 'vaqt tugadi');

      await t.tap(find.text('Bajardim').first);
      await t.pump();
      expect(find.text('1:00'), findsOneWidget, reason: 'tanlangan vaqt eslab qolindi');
      // belgi olinsa hisob ham yo'qoladi
      await t.tap(find.text('Bajarildi').first);
      await t.pump();
      expect(find.byKey(const Key('dam-olish')), findsNothing);

      await t.tap(find.text('Bajardim').first);
      await t.pump();
      await t.tap(find.text("O'tkazib yuborish"));
      await t.pump();
      expect(find.byKey(const Key('dam-olish')), findsNothing);
    });
  });

  group("Mashg'ulotdan keyingi fikr", () {
    testWidgets('tugagach Oson / To-g-ri / Qiyin; tanlov uzatiladi', (t) async {
      t.view.physicalSize = const Size(420, 7000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final plan = musclesFor(evenDays, DateTime.tuesday);
      final all = {
        for (final m in plan)
          for (final e in exercisesFor(m)) e.key
      };
      final feels = <String>[];
      await t.pumpWidget(MaterialApp(
        home: MusclesScreen(
          gymDays: evenDays,
          weekday: DateTime.tuesday,
          onBack: () {},
          progress: Stream.value(WorkoutProgress(started: true, done: all)),
          onFeel: feels.add,
        ),
      ));
      await t.pump(const Duration(seconds: 3));
      expect(find.text("BUGUNGI MASHG'ULOT QANDAY BO'LDI?"), findsOneWidget);
      expect(find.textContaining('Rahmat!'), findsNothing);
      await t.tap(find.text('Qiyin'));
      await t.pump();
      expect(feels, ['hard']);
      expect(find.textContaining('Rahmat!'), findsOneWidget);
    });

    testWidgets("bazada fikr bor вЂ” tanlangan ko'rinadi", (t) async {
      t.view.physicalSize = const Size(420, 7000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final all = {
        for (final m in musclesFor(evenDays, DateTime.tuesday))
          for (final e in exercisesFor(m)) e.key
      };
      await t.pumpWidget(MaterialApp(
        home: MusclesScreen(
          gymDays: evenDays,
          weekday: DateTime.tuesday,
          onBack: () {},
          progress: Stream.value(WorkoutProgress(started: true, done: all, feel: 'easy')),
        ),
      ));
      await t.pump(const Duration(seconds: 3));
      final chip = t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Oson'));
      expect(chip.selected, isTrue);
      expect(find.textContaining('Rahmat!'), findsOneWidget);
    });
  });

  group("Zal e'lonlari", () {
    final now = DateTime.now();
    final list = [
      Announcement(id: 'n', text: 'Ertaga zal 10:00 da', createdAt: now.subtract(const Duration(hours: 2)), createdBy: 't1'),
      Announcement(id: 'o', text: 'Eski xabar', createdAt: now.subtract(const Duration(days: 9)), createdBy: 'owner'),
    ];

    test('7 kundan eskisi bannerda chiqmaydi', () {
      expect(list[0].isFresh(now), isTrue);
      expect(list[1].isFresh(now), isFalse);
      expect(const Announcement(text: 'yozilmoqda').isFresh(now), isTrue, reason: 'server vaqti hali kelmagan');
    });

    testWidgets('banner: yangisi ko-rinadi, yopilsa yo-qoladi', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: AnnouncementBanner(stream: Stream.value(list))),
      ));
      await t.pump();
      expect(find.text('Ertaga zal 10:00 da'), findsOneWidget);
      expect(find.text('Eski xabar'), findsNothing);
      await t.tap(find.byTooltip('Yopish'));
      await t.pump();
      expect(find.text('Ertaga zal 10:00 da'), findsNothing);
    });

    testWidgets("trener: yozadi; o'chirish faqat o'z e'lonida", (t) async {
      t.view.physicalSize = const Size(420, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final added = <String>[];
      await t.pumpWidget(MaterialApp(
        home: AnnouncementsAdminScreen(
          admin: AppUser(id: 't1', name: 'Trener', email: '', role: 'admin'),
          stream: Stream.value(list),
          onAdd: (text) async => added.add(text),
          onDelete: (_) async {},
        ),
      ));
      await t.pump();
      expect(find.textContaining('7 kundan eski'), findsOneWidget);
      expect(find.byTooltip("O'chirish"), findsOneWidget, reason: "begona e'lonni trener o'chirmaydi");
      await t.tap(find.text("E'lon qilish"));
      await t.pump();
      expect(added, isEmpty, reason: "bo'sh matn yuborilmaydi");
      await t.enterText(find.byType(TextField), '  Shanba kuni dam  ');
      await t.tap(find.text("E'lon qilish"));
      await t.pump();
      expect(added, ['Shanba kuni dam']);
    });
  });
}
