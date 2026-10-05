import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Suv belgisi — [child] ustida xira, qiya takrorlanadigan matn (shogird ismi va telefoni).
/// Skrinshotni bloklamaydi, lekin tarqatilgan rasmda reja kimniki ekani ko'rinib turadi.
/// Bosish va aylantirishga xalaqit bermaydi.
class Watermark extends StatelessWidget {
  final String text;
  final Widget child;
  const Watermark({super.key, required this.text, required this.child});

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return child;
    final color = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.055);
    return Stack(children: [
      child,
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(painter: _WatermarkPainter(text.trim(), color)),
        ),
      ),
    ]);
  }
}

class _WatermarkPainter extends CustomPainter {
  final String text;
  final Color color;
  _WatermarkPainter(this.text, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final stepX = tp.width + 56;
    const stepY = 96.0;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    // burilgandan keyin ham butun ekran qoplansin — chegaradan kengroq chiziladi
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-math.pi / 7);
    final r = size.longestSide;
    var row = 0;
    for (var y = -r; y < r; y += stepY, row++) {
      // har ikkinchi qator yarim qadam surilgan — shaxmat tartibi
      for (var x = -r - (row.isOdd ? stepX / 2 : 0); x < r; x += stepX) {
        tp.paint(canvas, Offset(x, y));
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WatermarkPainter old) => old.text != text || old.color != color;
}
