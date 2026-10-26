import 'package:flutter/material.dart';
import '../l10n/tr.dart';
import '../models/photo.dart';
import '../theme.dart';

/// "Oldin / keyin" solishtirish: ikki rasm ustma-ust, o'rtadagi chiziqni surib farq ko'riladi.
/// Qaysi ikkitasi — tepada tanlanadi (standart: birinchi va oxirgi).
class BeforeAfterPage extends StatefulWidget {
  final List<ProgressPhoto> photos;
  final String Function(ProgressPhoto) caption;
  const BeforeAfterPage({super.key, required this.photos, required this.caption});

  @override
  State<BeforeAfterPage> createState() => _BeforeAfterPageState();
}

class _BeforeAfterPageState extends State<BeforeAfterPage> {
  late int _before = 0;
  late int _after = widget.photos.length - 1;

  Widget _picker(String label, int value, ValueChanged<int> onPick) => Expanded(
        child: DropdownButtonFormField<int>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            for (var i = 0; i < widget.photos.length; i++)
              DropdownMenuItem(value: i, child: Text(widget.caption(widget.photos[i]), overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => v == null ? null : setState(() => onPick(v)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Solishtirish'))),
      body: ListView(padding: const EdgeInsets.all(AppSpace.lg), children: [
        Row(children: [
          _picker(tr('Oldin'), _before, (v) => _before = v),
          const SizedBox(width: AppSpace.sm),
          _picker(tr('Keyin'), _after, (v) => _after = v),
        ]),
        const SizedBox(height: AppSpace.md),
        BeforeAfterSlider(
          key: ValueKey('$_before-$_after'),
          before: widget.photos[_before],
          after: widget.photos[_after],
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          tr("Chiziqni chapga-o'ngga suring: chapda — oldin, o'ngda — keyin."),
          textAlign: TextAlign.center,
          style: t.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
      ]),
    );
  }
}

/// Ikki rasm ustma-ust: "keyin" to'liq, "oldin" chap qismda; chiziq surilsa chegara siljiydi
class BeforeAfterSlider extends StatefulWidget {
  final ProgressPhoto before, after;
  const BeforeAfterSlider({super.key, required this.before, required this.after});

  @override
  State<BeforeAfterSlider> createState() => _BeforeAfterSliderState();
}

class _BeforeAfterSliderState extends State<BeforeAfterSlider> {
  /// Chiziq joyi: 0 — chap chekka, 1 — o'ng chekka
  double _pos = 0.5;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: LayoutBuilder(builder: (context, box) {
          void move(double dx) => setState(() => _pos = (dx / box.maxWidth).clamp(0.0, 1.0));
          return GestureDetector(
            onHorizontalDragUpdate: (d) => move(d.localPosition.dx),
            onTapDown: (d) => move(d.localPosition.dx),
            child: Stack(fit: StackFit.expand, children: [
              Image.memory(widget.after.bytes, fit: BoxFit.cover, gaplessPlayback: true),
              ClipRect(
                child: Align(
                  key: const Key('oldin-qismi'),
                  alignment: Alignment.centerLeft,
                  widthFactor: _pos,
                  child: SizedBox(
                    width: box.maxWidth,
                    height: box.maxHeight,
                    child: Image.memory(widget.before.bytes, fit: BoxFit.cover, gaplessPlayback: true),
                  ),
                ),
              ),
              Positioned(
                left: box.maxWidth * _pos - 1.5,
                top: 0,
                bottom: 0,
                child: Container(width: 3, color: Colors.white),
              ),
              Positioned(
                left: box.maxWidth * _pos - 20,
                top: box.maxHeight / 2 - 20,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: const Icon(Icons.compare_arrows, color: Colors.black),
                ),
              ),
              Positioned(left: 10, top: 10, child: _label(tr('Oldin'))),
              Positioned(right: 10, top: 10, child: _label(tr('Keyin'))),
            ]),
          );
        }),
      ),
    );
  }

  static Widget _label(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}
