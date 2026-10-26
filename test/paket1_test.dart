import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotta_qani_diet/models/photo.dart';
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
}
