import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotta_qani_diet/models/gym.dart';
import 'package:kotta_qani_diet/models/photo.dart';
import 'package:kotta_qani_diet/screens/user/muscles_screen.dart';
import 'package:kotta_qani_diet/widgets/before_after.dart';

/// 1×1 PNG — test rasmi
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
      expect(find.text('90 kg'), findsOneWidget, reason: 'oldin — birinchi rasm');
      expect(find.text('79 kg'), findsOneWidget, reason: 'keyin — oxirgi rasm');
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
    testWidgets("'Bajardim' — 90 s hisob; tanlov, o'tkazish, tugashi", (t) async {
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
      expect(find.text('1:00'), findsOneWidget, reason: 'boshqa vaqt — qaytadan');
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
}
