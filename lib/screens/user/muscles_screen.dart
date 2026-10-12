import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/tr.dart';
import '../../models/exercises.dart';
import '../../models/gym.dart';
import '../../widgets/body_map.dart';
import '../../widgets/particle_body.dart';

/// Tana xaritasi (sinov versiyasi): bugun haftalik reja bo'yicha qaysi mushaklar ishlashini
/// va ularning mashqlarini ko'rsatadi. Mushak bosilsa — faqat o'shaning mashqlari.
/// Zal kunida "Mashg'ulotni boshlash" bosilgach — navbat rejimi: faqat navbatdagi mushak
/// yonadi va faqat uning mashqlari ochiq; hammasi "Bajardim" bo'lgach keyingi mushak ochiladi.
/// Reja bor shogird faqat shu mashg'ulotdagi mushaklarni tanlay oladi: boshqa mushaklar
/// bosilmaydi va ro'yxatda chiqmaydi (zal egasi qoidasi — mashg'ulotdan tashqari mashq yo'q).
/// Har mashq yonida kichik tana shakli qaysi joy ishlashini ko'rsatadi.
///
/// Ko'rinish ataylab ilovaning qolgan qismidan boshqacha — zal egasi tanlagan "Dala" uslubi:
/// sof qora fon, bitta binafsha urg'u, sariq bosh harfli yorliqlar, kartochka va soyasiz.
/// Ranglar shu faylda — `AppColors` ga qo'shilmagan (faqat shu ekran).
class MusclesScreen extends StatefulWidget {
  /// Shogird tanlagan zal kunlari (`AppUser.gymDays`); tanlanmagan bo'lsa — reja yo'q,
  /// hamma mushak erkin ko'riladi
  final List<int> gymDays;

  /// Trener bugunni "uyda mashq" deb belgilaganmi
  final bool homeToday;

  /// Orqaga: ekran "Zal" tabi ichida ko'rsatiladi (pastki menyu joyida qoladi), shuning
  /// uchun `Navigator.pop` emas
  final VoidCallback onBack;

  /// Trener qo'shgan mashqlar (`Db.customExercises()`); null — faqat namunaviy ro'yxat
  final Stream<List<Exercise>>? custom;

  /// Bugungi mashg'ulot holati (`Db.workout`); null — faqat ekran xotirasida
  final Stream<WorkoutProgress>? progress;

  /// "Mashg'ulotni boshlash" bosildi; mashq "Bajardim" belgilandi yoki belgi olindi
  final VoidCallback? onStart;
  final void Function(String key, bool done)? onDone;

  /// Bugungi hafta kuni (test uchun; odatda `DateTime.now().weekday`)
  final int? weekday;

  const MusclesScreen({
    super.key,
    required this.gymDays,
    required this.onBack,
    this.homeToday = false,
    this.custom,
    this.progress,
    this.onStart,
    this.onDone,
    this.weekday,
  });

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

const _lead = TextStyle(fontSize: 17, height: 1.5, fontWeight: FontWeight.w300, color: _silver);

class _MusclesScreenState extends State<MusclesScreen> {
  /// Tana ko'rinishi: 0 — old, 4 — orqa (har qadam 45 gradus)
  int _angle = ParticleBody.front;
  String? _muscle;

  /// Ochilgan mashq (maslahati ko'rinadi)
  String? _open;

  /// Trener qo'shgan mashqlar (oqimdan; kelmaguncha yoki xato bo'lsa — bo'sh)
  List<Exercise> _custom = const [];

  List<Exercise> _of(String id) => exercisesFor(id, _custom);

  /// Mashg'ulot holati: bazadan keladi, bosilganda darhol shu yerda ham yangilanadi
  bool _started = false;
  Set<String> _done = {};
  StreamSubscription<WorkoutProgress>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.progress?.listen((p) {
      if (mounted) {
        setState(() {
          _started = p.started;
          _done = {...p.done};
        });
      }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// Navbat rejimi: bugun zal kuni va shogird mashg'ulotni boshlagan
  bool get _running => _gymToday && _started;

  /// Navbatdagi mushak (hammasi tugagan — null)
  String? get _active =>
      activeMuscle(_plan, _done, (m) => [for (final e in _of(m)) e.key]);

  void _start() {
    setState(() {
      _started = true;
      _muscle = null;
      _open = null;
    });
    widget.onStart?.call();
  }

  void _toggleDone(Exercise e) {
    final done = !_done.contains(e.key);
    setState(() {
      done ? _done.add(e.key) : _done.remove(e.key);
      _open = null;
    });
    widget.onDone?.call(e.key, done);
  }

  int get _today => widget.weekday ?? DateTime.now().weekday;
  bool get _hasPlan => validGymDays(widget.gymDays);

  /// Bugun zalga borish kunimi (uyda mashq kuni emas)
  bool get _gymToday => !widget.homeToday && musclesFor(widget.gymDays, _today).isNotEmpty;

  /// Ekranda mashqlari ko'rsatiladigan mashg'ulot kuni: bugun; dam olish yoki uy kunida —
  /// keyingi mashg'ulot (oldindan ko'rish uchun). Reja yo'q bo'lsa null.
  int? get _planDay {
    if (!_hasPlan) return null;
    return _gymToday ? _today : nextWorkout(widget.gymDays, _today)?.$1;
  }

  /// Shu mashg'ulotdagi mushaklar (reja yo'q bo'lsa bo'sh — hamma mushak erkin)
  List<String> get _plan => _planDay == null ? const [] : musclesFor(widget.gymDays, _planDay!);

  /// [id] null — tanlov bekor qilinadi, butun tana ko'rinadi
  void _select(String? id) {
    // reja bor — mashg'ulotdan tashqari mushak tanlanmaydi
    if (id != null && _hasPlan && !_plan.contains(id)) return;
    // navbat rejimida mushakni shogird tanlamaydi — navbat o'zi olib boradi
    if (_running) return;
    setState(() {
      _open = null;
      if (id == null || id == _muscle) {
        _muscle = null;
        return;
      }
      _muscle = id;
      // mushak shu ko'rinishda bo'lmasa — old yoki orqa tomonga o'giriladi
      _angle = ParticleBody.angleFor(id, _angle);
    });
  }

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

  /// Bugungi holat: sarlavha va izoh
  (String, String) get _status {
    final next = nextWorkout(widget.gymDays, _today);
    final after = next == null ? '' : trf('Keyingi: {0} — {1}', [tr(weekdayNames[next.$1] ?? ''), tr(next.$2)]);
    if (!_hasPlan) {
      return (
        tr('Zal kunlari tanlanmagan'),
        tr("Zal bo'limida kunlarni tanlang — bugungi mashqlar shu yerda chiqadi. Hozircha hamma mushak ochiq."),
      );
    }
    if (widget.homeToday) {
      return (tr('Uyda mashq'), '${tr('Uydagi mashqlar hali tayyor emas.')} $after');
    }
    if (_gymToday) return (tr(workoutFor(widget.gymDays, _today)!), tr('Bugun zalga borish kuni'));
    return (tr('Dam olish kuni'), after);
  }

  Widget _exercises(String id, {bool marking = false}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final e in _of(id))
          _ExerciseRow(
            exercise: e,
            open: _open == e.name,
            onTap: () => setState(() => _open = _open == e.name ? null : e.name),
            done: marking ? _done.contains(e.key) : null,
            onDone: marking ? () => _toggleDone(e) : null,
          ),
      ]);

  String _names(Iterable<String> ids) => ids.map((id) => tr(muscleById(id)!.name)).join(' → ');

  int _doneIn(String id) => _of(id).where((e) => _done.contains(e.key)).length;

  /// Navbat rejimi: tugagan mushaklar, navbatdagisi (mashqlari "Bajardim" bilan), keyingilar
  List<Widget> _workout() {
    final plan = _plan;
    final active = _active;
    final at = active == null ? plan.length : plan.indexOf(active);
    return [
      for (final id in plan.take(at))
        if (_of(id).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '✓ ${trf('{0} — tugadi', [tr(muscleById(id)!.name)])}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: _violet),
            ),
          ),
      if (active == null) ...[
        const SizedBox(height: 14),
        Text(tr("Bugungi mashg'ulot tugadi"), style: _count),
        const SizedBox(height: 12),
        Text(tr('Hamma mashq bajarildi. Barakalla!'), style: _lead),
      ] else ...[
        const SizedBox(height: 14),
        Text('${tr('Hozir')}: ${tr(muscleById(active)!.name)}'.toUpperCase(), style: _label),
        const SizedBox(height: 10),
        Text(trf('{0} / {1} bajarildi', [_doneIn(active), _of(active).length]), style: _count),
        const SizedBox(height: 30),
        _exercises(active, marking: true),
        if (at + 1 < plan.length)
          Text(
            trf('Navbatda: {0}', [_names(plan.skip(at + 1))]),
            style: _lead.copyWith(color: _ash),
          ),
      ],
    ];
  }

  /// Mashqlar qismi: tanlangan mushak yoki butun mashg'ulot
  List<Widget> _body() {
    if (_running) return _workout();
    final plan = _plan;
    final m = _muscle;
    if (m != null) {
      final muscle = muscleById(m)!;
      final head = [
        Text(tr(muscle.name).toUpperCase(), style: _label),
        const SizedBox(height: 10),
      ];
      return [
        ...head,
        Text(trf('{0} ta mashq', [_of(m).length]), style: _count),
        const SizedBox(height: 30),
        _exercises(m),
      ];
    }
    if (plan.isEmpty) {
      return [Text(tr('Hali mushak tanlanmagan.'), style: _lead.copyWith(color: _ash))];
    }
    return [
      Text(
        (_gymToday ? tr('Bugungi mashqlar') : tr("Keyingi mashg'ulot mashqlari")).toUpperCase(),
        style: _label,
      ),
      const SizedBox(height: 10),
      Text(
        trf('{0} ta mashq', [plan.fold<int>(0, (n, id) => n + _of(id).length)]),
        style: _count,
      ),
      if (_gymToday) ...[
        const SizedBox(height: 20),
        Text(trf('Tartib: {0}', [_names(plan)]), style: _lead),
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: _violet,
            foregroundColor: _white,
            shape: const StadiumBorder(),
            minimumSize: const Size(double.infinity, 52),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.4),
          ),
          onPressed: _start,
          child: Text(tr("Mashg'ulotni boshlash")),
        ),
      ],
      const SizedBox(height: 34),
      for (final id in plan) ...[
        Text(tr(muscleById(id)!.name).toUpperCase(), style: _label.copyWith(color: _violet)),
        const SizedBox(height: 18),
        _exercises(id),
        const SizedBox(height: 10),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Exercise>>(
        stream: widget.custom,
        builder: (context, snap) {
          _custom = snap.data ?? const [];
          return _page(context);
        },
      );

  Widget _page(BuildContext context) {
    final wide = MediaQuery.of(context).size.width;
    // navbat rejimida faqat navbatdagi mushak yonadi (tugagan va keyingilar — yo'q)
    final active = _running ? _active : null;
    final plan = _running ? {if (active != null) active} : _plan.toSet();
    final (title, note) = _status;
    // yaqinda yangi mashq qo'shilgan mushaklar — ro'yxatda belgi bilan
    final fresh = {
      for (final e in _custom)
        if (e.isNew()) e.muscle,
    };

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onBack();
      },
      child: Scaffold(
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
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back, color: _ash),
                ),
              ),
              const SizedBox(height: 12),
              Text(trf('Bugun · {0}', [tr(weekdayNames[_today] ?? '')]).toUpperCase(), style: _label),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: wide < 380 ? 30 : 36,
                  height: 1.05,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -1.2,
                  color: _white,
                ),
              ),
              if (note.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(note.trim(), style: _lead),
              ],
              const SizedBox(height: 14),
              // zal egasi so'rovi: hamma ko'rsin — uy mashqlari hali yo'q
              Text(
                tr('Hozircha faqat zaldagi mashqlar. Uydagi mashqlar hali tayyor emas.'),
                style: const TextStyle(fontSize: 14, height: 1.45, fontWeight: FontWeight.w400, color: _amber),
              ),
              const SizedBox(height: 26),
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
              // Hech narsa tanlanmaganda bugungi mashg'ulot mushaklari yonib turadi.
              // Barmoq bilan surilsa yoki "O'GIRISH" bosilsa — 45 gradusdan aylanadi.
              Center(
                child: ParticleBody(
                  angle: _angle,
                  selected: _running ? null : _muscle,
                  today: plan,
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
                  opacity: _muscle == null || _running ? 0 : 1,
                  child: _Side(
                    text: tr("TO'LIQ KO'RINISH"),
                    active: false,
                    onTap: () => _select(null),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              // mushaklar ro'yxati: reja bor bo'lsa — faqat shu mashg'ulotdagilar
              Wrap(spacing: 18, runSpacing: 12, children: [
                for (final m in muscles)
                  if (!_hasPlan || _plan.contains(m.id))
                    InkWell(
                      onTap: () => _select(m.id),
                      child: Text(
                        fresh.contains(m.id) ? '${tr(m.name)} · ${tr('yangi')}' : tr(m.name),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: m.id == (_running ? active : _muscle) ? FontWeight.w600 : FontWeight.w300,
                          color: m.id == (_running ? active : _muscle)
                              ? _amber
                              : _running
                                  ? (active == null || _plan.indexOf(m.id) < _plan.indexOf(active) ? _violet : _ash)
                                  : plan.contains(m.id)
                                      ? _white
                                      : _ash,
                        ),
                      ),
                    ),
              ]),
              const SizedBox(height: 44),
              // Qismli chizma: har mushak alohida bo'lak — aniq bosiladi va aniq bo'yaladi
              // (nuqtali tanada mushak chegarasi taxminiy). Bugungi mushaklar och binafsha.
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                for (final back in [false, true])
                  Column(children: [
                    BodyMap(
                      back: back,
                      primary: _running ? active : _muscle,
                      secondary: _running ? const {} : plan,
                      onTap: _select,
                      height: wide < 380 ? 270 : 310,
                    ),
                    const SizedBox(height: 6),
                    Text(tr(back ? 'ORQA' : 'OLD'), style: _label.copyWith(color: _ash)),
                  ]),
              ]),
              const SizedBox(height: 52),
              ..._body(),
              const SizedBox(height: 18),
              Text(
                tr("Sinov versiyasi: mashqlar ro'yxati namunaviy — treneringiz bergan dastur ustun turadi."),
                style: const TextStyle(fontSize: 13, height: 1.5, fontWeight: FontWeight.w300, color: _ash),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _count = TextStyle(
  fontSize: 30,
  height: 1.05,
  fontWeight: FontWeight.w400,
  letterSpacing: -1,
  color: _white,
);

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

  /// Navbat rejimida: bajarilganmi (null — belgi ko'rsatilmaydi) va belgini almashtirish
  final bool? done;
  final VoidCallback? onDone;
  const _ExerciseRow({
    required this.exercise,
    required this.open,
    required this.onTap,
    this.done,
    this.onDone,
  });

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
              if (e.isNew()) ...[
                Text(tr('Yangi').toUpperCase(), style: _label),
                const SizedBox(height: 6),
              ],
              Text(
                // trener yozgan matnning tarjimasi yo'q — tr() uni o'zgartirmay qaytaradi
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
              if (e.sets.isNotEmpty)
                Text(
                  tr(e.sets),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _violet),
                ),
              if (done != null) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: done! ? _violet : _white,
                    side: BorderSide(color: done! ? _violet : _ash),
                    shape: const StadiumBorder(),
                    minimumSize: const Size(0, 40),
                  ),
                  onPressed: onDone,
                  icon: Icon(done! ? Icons.check_circle : Icons.radio_button_unchecked, size: 18),
                  label: Text(done! ? tr('Bajarildi') : tr('Bajardim')),
                ),
              ],
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
                          _VideoSlot(url: e.video),
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

/// Mashq videosi o'rni. Trener havola qo'ygan bo'lsa — havola va "nusxalash" tugmasi
/// (ilovada havola ochadigan kutubxona yo'q; shogird nusxalab brauzerda ochadi).
/// Havola yo'q — "video hali tayyorlanmagan" yozuvi (ilova tilida).
class _VideoSlot extends StatelessWidget {
  final String url;
  const _VideoSlot({this.url = ''});

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        // balandlik matnga qarab o'sadi (tor ekranda havola va tugma sig'masdi)
        constraints: const BoxConstraints(minHeight: 150, minWidth: double.infinity),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF0E0E0E),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.play_circle_outline, color: _violet, size: 34),
              const SizedBox(height: 10),
              Text(tr('VIDEO'), style: _label),
              const SizedBox(height: 6),
              if (url.isEmpty)
                Text(
                  tr("Video hali tayyorlanmagan. Trener tayyorlab qo'ygach, shu yerda ko'rinadi."),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, height: 1.45, fontWeight: FontWeight.w300, color: _ash),
                )
              else ...[
                Text(
                  url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w300, color: _silver),
                ),
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: url));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(tr('Havola nusxalandi'))));
                    }
                  },
                  child: Text(tr('Havolani nusxalash'), style: const TextStyle(color: _violet)),
                ),
              ],
            ]),
          ),
        ),
      );
}
