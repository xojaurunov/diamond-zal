import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/tr.dart';
import '../../models/exercises.dart';
import '../../models/gym.dart';
import '../../models/lesson.dart';
import '../../models/models.dart';
import '../../models/video_link.dart';
import '../../services/db.dart';
import '../../theme.dart';
import '../../widgets/food_image.dart';
import '../../widgets/youtube_embed_io.dart'
    if (dart.library.js_interop) '../../widgets/youtube_embed_web.dart';

/// "Videolar" — zalning ichki video bo'limi: mashq videolari va trener darslari bitta joyda.
/// Izoh, layk, yuklab olish yo'q (zal egasi qarori) — shogird mashqni tanlab, ko'rib, bajaradi.
class VideosScreen extends StatefulWidget {
  final AppUser user;

  /// Testda bazasiz berish uchun (berilmasa — bazadan)
  final Stream<List<Exercise>>? custom;
  final Stream<List<Lesson>>? lessons;
  const VideosScreen({super.key, required this.user, this.custom, this.lessons});

  @override
  State<VideosScreen> createState() => _VideosScreenState();
}

/// Tasmadagi bitta video: mashq videosi yoki trener darsi
class VideoItem {
  final String title;
  final String url;
  final Exercise? exercise;
  final Lesson? lesson;

  /// Shogirdning o'z dasturidagi mashq ("Siz uchun")
  final bool mine;
  const VideoItem({required this.title, required this.url, this.exercise, this.lesson, this.mine = false});

  bool get isNew => exercise?.isNew() ?? lesson?.isNew() ?? false;
  String? get muscle => exercise?.muscle;

  /// Kartochka ostidagi qisqa matn: mushak · yondashuv yoki dars turi · davomiyligi
  String subtitle() => exercise != null
      ? [tr(muscleById(exercise!.muscle)?.name ?? ''), if (exercise!.sets.isNotEmpty) tr(exercise!.sets)].join(' · ')
      : [tr(lessonCategories[lesson!.category] ?? ''), if (lesson!.seconds > 0) durationText(lesson!.seconds)]
          .join(' · ');
}

/// Tasma: shogird uchun o'z mashqlari tepada, keyin yangilari
List<VideoItem> buildVideoItems(AppUser user, List<Exercise> custom, List<Lesson> lessons) {
  final staff = user.isAdmin;
  final items = <VideoItem>[
    for (final e in allExercises(custom))
      if (e.video.trim().isNotEmpty)
        VideoItem(
          title: tr(e.name),
          url: e.video.trim(),
          exercise: e,
          mine: !staff && exercisesForStudent(e.muscle, custom, user.program).any((x) => x.key == e.key),
        ),
    for (final l in lessons)
      if (l.url.trim().isNotEmpty) VideoItem(title: l.title, url: l.url.trim(), lesson: l),
  ];
  items.sort((a, b) {
    if (a.mine != b.mine) return a.mine ? -1 : 1;
    if (a.isNew != b.isNew) return a.isNew ? -1 : 1;
    return a.title.compareTo(b.title);
  });
  return items;
}

class _VideosScreenState extends State<VideosScreen> {
  late final _custom = widget.custom ?? Db.customExercises();
  late final _lessons = widget.lessons ?? Db.lessons();
  final _search = TextEditingController();

  /// Filtr: 'all' | 'today' | 'lessons' | mushak id
  String _filter = 'all';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<VideoItem> _apply(List<VideoItem> all) {
    final q = _search.text.trim().toLowerCase();
    final today = musclesFor(widget.user.gymDays, DateTime.now().weekday);
    return [
      for (final i in all)
        if ((switch (_filter) {
              'all' => true,
              'today' => i.muscle != null && today.contains(i.muscle),
              'lessons' => i.lesson != null,
              final m => i.muscle == m,
            }) &&
            (q.isEmpty || i.title.toLowerCase().contains(q) || i.subtitle().toLowerCase().contains(q)))
          i,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Videolar'))),
      body: StreamBuilder<List<Exercise>>(
        stream: _custom,
        builder: (context, ex) => StreamBuilder<List<Lesson>>(
          stream: _lessons,
          builder: (context, ls) {
            if (!ex.hasData && !ex.hasError) return const Center(child: CircularProgressIndicator());
            final all = buildVideoItems(widget.user, ex.data ?? const [], ls.data ?? const []);
            final shown = _apply(all);
            final withVideo = {for (final i in all) i.muscle}.whereType<String>().toSet();
            final hasToday = validGymDays(widget.user.gymDays) &&
                musclesFor(widget.user.gymDays, DateTime.now().weekday).isNotEmpty;
            final chips = <(String, String)>[
              ('all', tr('Hammasi')),
              if (hasToday) ('today', tr('Bugun')),
              if (all.any((i) => i.lesson != null)) ('lessons', tr('Darslar')),
              for (final m in muscles)
                if (withVideo.contains(m.id)) (m.id, tr(m.name)),
            ];
            return ListView(
              padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xs, AppSpace.lg, AppSpace.xxl),
              children: [
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr('Qidirish')),
                ),
                const SizedBox(height: AppSpace.sm),
                SizedBox(
                  height: 40,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final (k, label) in chips)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpace.xs),
                        child: ChoiceChip(
                            label: Text(label), selected: _filter == k, onSelected: (_) => setState(() => _filter = k)),
                      ),
                  ]),
                ),
                const SizedBox(height: AppSpace.md),
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(AppSpace.xl),
                    child: Text(
                      all.isEmpty
                          ? tr("Hali video yo'q. Trener mashqlarga video qo'shgach, shu yerda ko'rinadi.")
                          : tr("Bu bo'limda video topilmadi."),
                      textAlign: TextAlign.center,
                      style: t.bodyMedium?.copyWith(color: AppColors.textMuted),
                    ),
                  ),
                for (final i in shown) VideoCard(item: i),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Testda muqova rasmini tarmoqsiz almashtirish uchun
@visibleForTesting
Widget Function(String url)? debugVideoCardThumb;

/// Video kartochkasi: muqova (16:9), davomiyligi, "YANGI" / "Siz uchun", nomi
class VideoCard extends StatelessWidget {
  final VideoItem item;
  const VideoCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final thumb = thumbOf(item.url);
    final placeholder = Container(
      color: AppColors.cardHigh,
      alignment: Alignment.center,
      child: Icon(Icons.play_circle_outline, size: 48, color: AppColors.textMuted),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VideoPage(item: item))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(fit: StackFit.expand, children: [
                if (thumb == null)
                  placeholder
                else
                  debugVideoCardThumb?.call(thumb) ?? netImage(thumb, errorBuilder: (_, __, ___) => placeholder),
                Center(
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(color: Color(0x99000000), shape: BoxShape.circle),
                    child: const Icon(Icons.play_arrow, color: Colors.white, size: 32),
                  ),
                ),
                Positioned(
                  left: 8,
                  top: 8,
                  child: Row(children: [
                    if (item.mine) _badge(tr('Siz uchun'), AppColors.accent),
                    if (item.isNew) _badge(tr('YANGI'), const Color(0xFFE5484D)),
                  ]),
                ),
                if (item.lesson != null && item.lesson!.seconds > 0)
                  Positioned(right: 8, bottom: 8, child: _badge(durationText(item.lesson!.seconds), const Color(0xCC000000))),
              ]),
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(item.title, style: t.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
          Text(item.subtitle(), style: t.bodySmall?.copyWith(color: AppColors.textMuted)),
        ]),
      ),
    );
  }

  static Widget _badge(String text, Color color) => Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

/// Testda pleyerni (WebView) almashtirish uchun
@visibleForTesting
Widget Function(String url, double speed)? debugVideoPagePlayer;

/// Video sahifasi: pleyer (to'liq ekran, surish, tezlik), mashq bo'lsa — yondashuv va qanday bajarish
class VideoPage extends StatefulWidget {
  final VideoItem item;
  const VideoPage({super.key, required this.item});

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  double _speed = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _wifiHint());
  }

  /// Birinchi marta: video mobil internetni ko'p yeydi — bir martalik eslatma
  Future<void> _wifiHint() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (p.getBool('video_wifi_hint') == true || !mounted) return;
      await p.setBool('video_wifi_hint', true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr("Video internetni ko'p sarflaydi (4 daqiqa ≈ 45 MB) — Wi‑Fi'da ko'rish tavsiya etiladi.")),
        ));
      }
    } catch (_) {}
  }

  Widget _player(String url) {
    if (debugVideoPagePlayer != null) return debugVideoPagePlayer!(url, _speed);
    if (isUploadedVideo(url)) return videoEmbed(url, speed: _speed);
    final id = youtubeId(url);
    if (id != null) return youtubeEmbed(id);
    return Center(
      child: OutlinedButton.icon(
        onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        icon: const Icon(Icons.open_in_new),
        label: Text(tr("Videoni ko'rish")),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final i = widget.item;
    final e = i.exercise;
    return Scaffold(
      appBar: AppBar(title: Text(i.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: ListView(children: [
        AspectRatio(aspectRatio: 16 / 9, child: ColoredBox(color: Colors.black, child: _player(i.url))),
        if (isUploadedVideo(i.url))
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, 0),
            child: Wrap(spacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(tr('Tezlik:'), style: t.bodySmall),
              for (final s in const [0.5, 0.75, 1.0])
                ChoiceChip(
                  label: Text('${s == 1 ? '1' : s}x'),
                  selected: _speed == s,
                  onSelected: (_) => setState(() => _speed = s),
                ),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(i.title, style: t.titleLarge),
            const SizedBox(height: 4),
            Text(i.subtitle(), style: t.bodyMedium?.copyWith(color: AppColors.textMuted)),
            if (e != null && e.tip.isNotEmpty) ...[
              const SizedBox(height: AppSpace.md),
              Text(tr('Qanday bajariladi'), style: t.titleSmall),
              const SizedBox(height: 4),
              Text(tr(e.tip), style: t.bodyMedium?.copyWith(height: 1.5)),
            ],
            if (e != null && e.also.isNotEmpty) ...[
              const SizedBox(height: AppSpace.sm),
              Text(
                trf('Yordamchi: {0}', [e.also.map((m) => tr(muscleById(m)?.name ?? m)).join(', ')]),
                style: t.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ],
            if (i.lesson != null && i.lesson!.description.isNotEmpty) ...[
              const SizedBox(height: AppSpace.md),
              Text(i.lesson!.description, style: t.bodyMedium?.copyWith(height: 1.5)),
            ],
          ]),
        ),
      ]),
    );
  }
}
