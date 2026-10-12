import 'package:flutter/material.dart';
import '../../l10n/tr.dart';
import '../../models/exercises.dart';
import '../../widgets/body_map.dart';
import '../../widgets/particle_body.dart';

/// Tana xaritasi (sinov versiyasi): mushak bosiladi — shu mushak mashqlari chiqadi; har mashq
/// yonida kichik tana shakli qaysi joy ishlashini ko'rsatadi.
///
/// Ko'rinish ataylab ilovaning qolgan qismidan boshqacha — zal egasi tanlagan "Dala" uslubi:
/// sof qora fon, bitta binafsha urg'u, sariq bosh harfli yorliqlar, kartochka va soyasiz.
/// Ranglar shu faylda — `AppColors` ga qo'shilmagan (faqat shu ekran).
class MusclesScreen extends StatefulWidget {
  const MusclesScreen({super.key});

  @override
  State<MusclesScreen> createState() => _MusclesScreenState();
}

const _violet = Color(0xFF8052FF);
const _amber = Color(0xFFFFB829);
const _white = Color(0xFFFFFFFF);
const _silver = Color(0xFFBDBDBD);
const _ash = Color(0xFF9A9A9A);

const _label = TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.6,
  color: _amber,
);

class _MusclesScreenState extends State<MusclesScreen> {
  /// Tana ko'rinishi: 0 — old, 4 — orqa (har qadam 45 gradus)
  int _angle = ParticleBody.front;
  String? _muscle;

  /// Ochilgan mashq (maslahati ko'rinadi)
  String? _open;

  /// [id] null — tanlov bekor qilinadi, butun tana ko'rinadi
  void _select(String? id) => setState(() {
        _open = null;
        if (id == null || id == _muscle) {
          _muscle = null;
          return;
        }
        _muscle = id;
        // mushak shu ko'rinishda bo'lmasa — old yoki orqa tomonga o'giriladi
        _angle = ParticleBody.angleFor(id, _angle);
      });

  /// Tana [by] qadam aylanadi (har qadam 45 gradus)
  void _rotate(int by) => setState(() => _angle = (_angle + by) % ParticleBody.views);

  void _face(int angle) => setState(() {
        _angle = angle;
        // tanlangan mushak bu tomonda bo'lmasa, o'zi boshqa tomonga o'girilib ketmasin
        if (_muscle != null && !ParticleBody.has(_muscle!, angle: angle)) {
          _muscle = null;
          _open = null;
        }
      });

  @override
  Widget build(BuildContext context) {
    final muscle = _muscle == null ? null : muscleById(_muscle!);
    final list = _muscle == null ? const <Exercise>[] : exercisesFor(_muscle!);
    final wide = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 6, 24, 60),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
                tooltip: tr('Orqaga'),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back, color: _ash),
              ),
            ),
            const SizedBox(height: 12),
            Text(tr('MASHQLAR'), style: _label),
            const SizedBox(height: 12),
            Text(
              tr('Qaysi mushakni mashq qilamiz?'),
              style: TextStyle(
                fontSize: wide < 380 ? 34 : 40,
                height: 1.02,
                fontWeight: FontWeight.w400,
                letterSpacing: -1.4,
                color: _white,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              tr("Tanadagi mushakni bosing yoki pastdagi ro'yxatdan tanlang — shu joy uchun mashqlar chiqadi."),
              style: const TextStyle(fontSize: 17, height: 1.5, fontWeight: FontWeight.w300, color: _silver),
            ),
            const SizedBox(height: 30),
            // old / orqa — bitta to'ldirilgan tugma (ekranda yagona)
            Row(children: [
              _Side(
                text: tr('OLD'),
                active: _angle == ParticleBody.front,
                onTap: () => _face(ParticleBody.front),
              ),
              const SizedBox(width: 24),
              _Side(
                text: tr('ORQA'),
                active: _angle == ParticleBody.back,
                onTap: () => _face(ParticleBody.back),
              ),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _violet,
                  foregroundColor: _white,
                  shape: const StadiumBorder(),
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.4),
                ),
                onPressed: () => _rotate(1),
                child: Text(tr("O'GIRISH")),
              ),
            ]),
            const SizedBox(height: 18),
            // Tana mayda nuqtalardan yig'iladi; mushak tanlansa o'sha joyga yaqinlashadi.
            // Barmoq bilan surilsa yoki "O'GIRISH" bosilsa — 45 gradusdan aylanadi.
            Center(
              child: ParticleBody(
                angle: _angle,
                selected: _muscle,
                onTap: _select,
                onRotate: _rotate,
                width: wide < 380 ? 290 : 320,
                height: wide < 380 ? 520 : 574,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                tr('Surib aylantiring'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w300, color: _ash),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _muscle == null ? 0 : 1,
                child: _Side(
                  text: tr("TO'LIQ KO'RINISH"),
                  active: false,
                  onTap: () => _select(null),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Wrap(spacing: 18, runSpacing: 12, children: [
              for (final m in muscles)
                InkWell(
                  onTap: () => _select(m.id),
                  child: Text(
                    tr(m.name),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: m.id == _muscle ? FontWeight.w600 : FontWeight.w300,
                      color: m.id == _muscle ? _amber : _ash,
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 44),
            // Qismli chizma: har mushak alohida bo'lak — aniq bosiladi va aniq bo'yaladi
            // (nuqtali tanada mushak chegarasi taxminiy)
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              for (final back in [false, true])
                Column(children: [
                  BodyMap(back: back, primary: _muscle, onTap: _select, height: wide < 380 ? 270 : 310),
                  const SizedBox(height: 6),
                  Text(tr(back ? 'ORQA' : 'OLD'), style: _label.copyWith(color: _ash)),
                ]),
            ]),
            const SizedBox(height: 52),
            if (muscle == null)
              Text(
                tr('Hali mushak tanlanmagan.'),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w300, color: _ash),
              )
            else ...[
              Text(tr(muscle.name).toUpperCase(), style: _label),
              const SizedBox(height: 10),
              Text(
                trf('{0} ta mashq', [list.length]),
                style: const TextStyle(
                  fontSize: 30,
                  height: 1.05,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -1,
                  color: _white,
                ),
              ),
              const SizedBox(height: 30),
              for (final e in list)
                _ExerciseRow(
                  exercise: e,
                  open: _open == e.name,
                  onTap: () => setState(() => _open = _open == e.name ? null : e.name),
                ),
              const SizedBox(height: 18),
              Text(
                tr("Sinov versiyasi: mashqlar ro'yxati namunaviy — treneringiz bergan dastur ustun turadi."),
                style: const TextStyle(fontSize: 13, height: 1.5, fontWeight: FontWeight.w300, color: _ash),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Side extends StatelessWidget {
  final String text;
  final bool active;
  final VoidCallback onTap;
  const _Side({required this.text, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: active ? _white : _ash,
            ),
          ),
        ),
      );
}

/// Bitta mashq: nomi, yondashuv × takror, yonida qaysi mushak ishlashini ko'rsatuvchi kichik
/// tana shakli. Bosilsa — qisqa maslahat ochiladi.
class _ExerciseRow extends StatelessWidget {
  final Exercise exercise;
  final bool open;
  final VoidCallback onTap;
  const _ExerciseRow({required this.exercise, required this.open, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final e = exercise;
    // asosiy mushak qaysi tomonda yaxshiroq ko'rinsa, shakl o'sha tomondan ko'rsatiladi
    final back = BodyMap.backIsBetter(e.muscle);
    final also = [for (final id in e.also) muscleById(id)].whereType<Muscle>().toList();
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 36),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                tr(e.name),
                style: const TextStyle(
                  fontSize: 22,
                  height: 1.15,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -0.4,
                  color: _white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr(e.sets),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _violet),
              ),
              if (also.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  trf('Yordamchi: {0}', [also.map((m) => tr(m.name)).join(', ')]),
                  style: const TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w300, color: _ash),
                ),
              ],
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                alignment: Alignment.topLeft,
                child: open
                    ? Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const _VideoSlot(),
                          const SizedBox(height: 14),
                          Text(
                            tr(e.tip),
                            style: const TextStyle(
                              fontSize: 16,
                              height: 1.5,
                              fontWeight: FontWeight.w300,
                              color: _silver,
                            ),
                          ),
                        ]),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ]),
          ),
          const SizedBox(width: 18),
          BodyMap(back: back, primary: e.muscle, secondary: e.also.toSet(), height: 150),
        ]),
      ),
    );
  }
}

/// Mashq videosi o'rni. Hozircha video yo'q — trener tayyorlagach shu yerda ko'rinadi
/// (yozuv ilova tilida chiqadi).
class _VideoSlot extends StatelessWidget {
  const _VideoSlot();

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 16 / 9,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF0E0E0E),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.play_circle_outline, color: _violet, size: 34),
              const SizedBox(height: 10),
              Text(tr('VIDEO'), style: _label),
              const SizedBox(height: 6),
              Text(
                tr("Video hali tayyorlanmagan. Trener tayyorlab qo'ygach, shu yerda ko'rinadi."),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, height: 1.45, fontWeight: FontWeight.w300, color: _ash),
              ),
            ]),
          ),
        ),
      );
}
