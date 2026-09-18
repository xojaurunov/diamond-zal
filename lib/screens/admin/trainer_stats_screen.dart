import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../models/stats.dart';
import '../../services/db.dart';
import '../../theme.dart';
import '../../widgets/ui.dart';
import 'clients_screen.dart';

/// "Trenerlar reytingi" — faqat bosh admin. Trenerlarni so'nggi 7 kun bo'yicha
/// solishtiradi: reja, chatga javob, shogirdlar rioyasi, natija. Kimga e'tibor kerakligini ko'rsatadi.
class TrainerStatsScreen extends StatefulWidget {
  final AppUser owner;
  const TrainerStatsScreen({super.key, required this.owner});

  @override
  State<TrainerStatsScreen> createState() => _TrainerStatsScreenState();
}

class _TrainerStatsScreenState extends State<TrainerStatsScreen> {
  late Future<List<TrainerStat>> _future = Db.trainerStats();

  Future<void> _reload() async {
    final f = Db.trainerStats();
    setState(() => _future = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trenerlar reytingi'),
        actions: [
          IconButton(tooltip: 'Yangilash', onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<List<TrainerStat>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: "Ma'lumotni yuklab bo'lmadi",
              subtitle: '${snap.error}',
              action: OutlinedButton(onPressed: _reload, child: const Text('Qayta urinish')),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());

          // Ball bo'yicha: yuqori ball tepada, shogirdi yo'qlar oxirida
          final stats = [...snap.data!]..sort((a, b) {
              final sa = a.score, sb = b.score;
              if (sa == null || sb == null) return sa == null ? (sb == null ? 0 : 1) : -1;
              return sb.compareTo(sa);
            });
          final rated = stats.where((s) => s.score != null).toList();

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding:
                  const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xs, AppSpace.lg, AppSpace.xxl),
              children: [
                Text(
                  "So'nggi $statsDays kun. Ball shogirdlarga reja berilgani, chatga javob, "
                  "shogirdlarning rejaga rioyasi va vazn natijasidan avtomatik hisoblanadi.",
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.textMuted, height: 1.4),
                ),
                if (rated.length > 1) ...[
                  const SizedBox(height: AppSpace.lg),
                  _Comparison(stats: rated),
                ],
                const SizedBox(height: AppSpace.lg),
                for (var i = 0; i < stats.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.sm),
                    child: FadeInUp(
                      index: i,
                      child: _TrainerCard(
                        rank: stats[i].score == null ? null : i + 1,
                        stat: stats[i],
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _TrainerStatDetail(stat: stats[i], owner: widget.owner),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

String _name(AppUser u) => u.name.isEmpty ? fmtPhone(u.phone) : u.name;

String _pct(double? v) => v == null ? '—' : '${(v * 100).round()}%';

Color _scoreColor(int? s) => s == null
    ? AppColors.textMuted
    : s >= 75
        ? AppColors.success
        : s >= 50
            ? AppColors.warning
            : AppColors.danger;

class _Stars extends StatelessWidget {
  final int? stars;
  const _Stars(this.stars);

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i <= (stars ?? 0) ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 16,
            color: i <= (stars ?? 0) ? AppColors.warning : AppColors.textFaint,
          ),
      ]);
}

/// Ko'rsatkichlar bo'yicha trenerlarni yonma-yon solishtirish
class _Comparison extends StatelessWidget {
  final List<TrainerStat> stats;
  const _Comparison({required this.stats});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final metrics = stats.first.parts.map((p) => p.$1).toList();
    return BentoTile(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Eyebrow('Solishtirish'),
        for (var m = 0; m < metrics.length; m++) ...[
          const SizedBox(height: AppSpace.md),
          Text(metrics[m], style: t.titleSmall),
          const SizedBox(height: AppSpace.xs),
          for (final s in stats)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: _Bar(label: _name(s.trainer), value: s.parts[m].$2),
            ),
        ],
      ]),
    );
  }
}

class _Bar extends StatelessWidget {
  final String label;
  final double? value;
  const _Bar({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final v = value;
    return Row(children: [
      SizedBox(
        width: 96,
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall),
      ),
      const SizedBox(width: AppSpace.sm),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: LinearProgressIndicator(
            value: v ?? 0,
            minHeight: 8,
            backgroundColor: AppColors.text.withValues(alpha: 0.08),
            color: _scoreColor(v == null ? null : (v * 100).round()),
          ),
        ),
      ),
      SizedBox(
        width: 44,
        child: Text(
          _pct(v),
          textAlign: TextAlign.right,
          style: t.bodySmall?.copyWith(fontFeatures: tabular, color: AppColors.textMuted),
        ),
      ),
    ]);
  }
}

class _TrainerCard extends StatelessWidget {
  final int? rank;
  final TrainerStat stat;
  final VoidCallback onTap;
  const _TrainerCard({required this.rank, required this.stat, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final score = stat.score;
    final attention = stat.needAttention.length;
    return BentoTile(
      onTap: onTap,
      feature: rank == 1,
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          SizedBox(
            width: 28,
            child: Text(
              rank == null ? '–' : '$rank',
              style: t.titleMedium?.copyWith(color: AppColors.textMuted, fontFeatures: tabular),
            ),
          ),
          UserAvatar(name: _name(stat.trainer), size: 38),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_name(stat.trainer),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium),
              const SizedBox(height: 2),
              if (score == null)
                Text("Shogirdi yo'q — baho yo'q",
                    style: t.bodySmall?.copyWith(color: AppColors.textMuted))
              else
                _Stars(stat.stars),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              score == null ? '—' : '$score',
              style: t.headlineSmall?.copyWith(color: _scoreColor(score), fontFeatures: tabular),
            ),
            Text('/ 100', style: t.bodySmall?.copyWith(color: AppColors.textFaint)),
          ]),
        ]),
        if (score != null) ...[
          const SizedBox(height: AppSpace.md),
          Wrap(spacing: 6, runSpacing: 6, children: [
            Pill(
              text: '${stat.clients.length} shogird',
              color: AppColors.water,
              icon: Icons.groups_outlined,
            ),
            Pill(
              text: '${stat.messagesSent} xabar',
              color: AppColors.protein,
              icon: Icons.chat_bubble_outline,
            ),
            Pill(
              text: attention == 0 ? 'Hammasi joyida' : "$attention ta e'tibor kerak",
              color: attention == 0 ? AppColors.success : AppColors.warning,
              icon: attention == 0 ? Icons.check_rounded : Icons.priority_high_rounded,
            ),
            // bosh adminning qo'lda qo'ygan bahosi (bo'lsa)
            StreamBuilder<Map<String, TrainerRating>>(
              stream: Db.ratings(),
              builder: (context, snap) {
                final r = snap.data?[stat.trainer.id];
                if (r == null) return const SizedBox.shrink();
                return Pill(
                  text: 'Bahongiz: ${r.stars}/5',
                  color: AppColors.warning,
                  icon: Icons.star_rounded,
                );
              },
            ),
          ]),
        ],
      ]),
    );
  }
}

/// Bitta trener: ball tarkibi va e'tibor kerak bo'lgan shogirdlar
class _TrainerStatDetail extends StatelessWidget {
  final TrainerStat stat;
  final AppUser owner;
  const _TrainerStatDetail({required this.stat, required this.owner});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final score = stat.score;
    final attention = stat.needAttention;
    final ok = stat.clients.where((c) => c.attention.isEmpty).toList();
    return Scaffold(
      appBar: AppBar(title: Text(_name(stat.trainer))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xs, AppSpace.lg, AppSpace.xxl),
        children: [
          BentoTile(
            feature: true,
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Eyebrow('Umumiy ball', color: AppColors.textFaint),
                  const SizedBox(height: AppSpace.sm),
                  _Stars(stat.stars),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    "${stat.clients.length} shogird · $statsDays kunda ${stat.messagesSent} xabar yozgan",
                    style: t.bodySmall?.copyWith(color: AppColors.textMuted),
                  ),
                ]),
              ),
              Text(
                score == null ? '—' : '$score',
                style: t.displaySmall?.copyWith(color: _scoreColor(score), fontFeatures: tabular),
              ),
            ]),
          ),
          const SizedBox(height: AppSpace.md),
          _OwnerRatingCard(trainerId: stat.trainer.id),
          const SizedBox(height: AppSpace.md),
          BentoTile(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Eyebrow('Ball tarkibi'),
              for (final (label, value, weight) in stat.parts) ...[
                const SizedBox(height: AppSpace.md),
                Row(children: [
                  Expanded(child: Text(label, style: t.titleSmall)),
                  Text("og'irligi $weight%",
                      style: t.bodySmall?.copyWith(color: AppColors.textFaint)),
                ]),
                const SizedBox(height: AppSpace.xs),
                _Bar(label: _explain(label), value: value),
              ],
            ]),
          ),
          const SizedBox(height: AppSpace.xl),
          SectionHeader(
            "E'tibor kerak",
            eyebrow: 'Shogirdlar',
            trailing: Pill(
              text: '${attention.length}',
              color: attention.isEmpty ? AppColors.success : AppColors.warning,
            ),
          ),
          if (attention.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpace.lg),
              child: Center(child: Text('Hamma shogirdlarda hammasi joyida')),
            ),
          for (final c in attention) _ClientAttention(stat: c, owner: owner),
          if (ok.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xl),
            SectionHeader('Yaxshi',
                eyebrow: 'Shogirdlar',
                trailing: Pill(text: '${ok.length}', color: AppColors.success)),
            for (final c in ok) _ClientAttention(stat: c, owner: owner),
          ],
        ],
      ),
    );
  }

  static String _explain(String label) => switch (label) {
        'Reja berilgan' => 'shogirdlar',
        'Chatga javob' => 'yozganlar',
        'Shogirdlar rioyasi' => 'yedim belgisi',
        _ => 'maqsad tomon',
      };
}

class _ClientAttention extends StatelessWidget {
  final ClientStat stat;
  final AppUser owner;
  const _ClientAttention({required this.stat, required this.owner});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = stat.client;
    final reasons = stat.attention;
    final a = stat.adherence;
    final d = stat.weightChange;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: BentoTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ClientDetail(client: c, admin: owner)),
        ),
        padding: const EdgeInsets.all(AppSpace.md),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          UserAvatar(name: _name(c), size: 38),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(_name(c),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium),
                ),
                if (c.goal.isNotEmpty) ...[
                  const SizedBox(width: AppSpace.sm),
                  GoalPill(user: c),
                ],
              ]),
              const SizedBox(height: 2),
              Text(
                'Rioya ${_pct(a)}'
                '${d == null ? '' : ' · vazn ${d > 0 ? '+' : ''}${fmtNum(double.parse(d.toStringAsFixed(1)))} kg'}',
                style: t.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: tabular),
              ),
              if (reasons.isNotEmpty) ...[
                const SizedBox(height: AppSpace.sm),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final r in reasons) Pill(text: r, color: AppColors.warning),
                ]),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Bosh adminning o'z bahosi (1–5 yulduz + izoh). Avtomatik balldan alohida;
/// faqat bosh admin ko'radi — trener bilmaydi.
class _OwnerRatingCard extends StatefulWidget {
  final String trainerId;
  const _OwnerRatingCard({required this.trainerId});

  @override
  State<_OwnerRatingCard> createState() => _OwnerRatingCardState();
}

class _OwnerRatingCardState extends State<_OwnerRatingCard> {
  late final _stream = Db.ratings();
  final _comment = TextEditingController();
  int? _stars; // null — hali tahrirlanmagan (bazadagi qiymat ko'rsatiladi)
  bool _loaded = false, _saving = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _save(int stars) async {
    setState(() => _saving = true);
    try {
      await Db.saveRating(widget.trainerId, stars, _comment.text.trim());
      if (mounted) showSnack(context, 'Baho saqlandi');
    } catch (e) {
      if (mounted) showSnack(context, "Saqlab bo'lmadi: $e");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return StreamBuilder<Map<String, TrainerRating>>(
      stream: _stream,
      builder: (context, snap) {
        final saved = snap.data?[widget.trainerId];
        if (snap.hasData && !_loaded) {
          _loaded = true;
          _comment.text = saved?.comment ?? '';
        }
        final stars = _stars ?? saved?.stars ?? 0;
        return BentoTile(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Eyebrow('Sizning bahoingiz'),
            const SizedBox(height: AppSpace.xs),
            Text(
              "Faqat siz ko'rasiz — trener bu bahoni ko'rmaydi.",
              style: t.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpace.sm),
            Row(children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  tooltip: '$i yulduz',
                  onPressed: () => setState(() => _stars = i),
                  icon: Icon(
                    i <= stars ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 32,
                    color: i <= stars ? AppColors.warning : AppColors.textFaint,
                  ),
                ),
            ]),
            TextField(
              controller: _comment,
              maxLength: 500,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Izoh (ixtiyoriy)'),
            ),
            if (saved?.updatedAt != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: Text(
                  'Oxirgi baho: ${uzDate(saved!.updatedAt!)}',
                  style: t.bodySmall?.copyWith(color: AppColors.textFaint),
                ),
              ),
            FilledButton(
              onPressed: stars == 0 || _saving ? null : () => _save(stars),
              child: const Text('Bahoni saqlash'),
            ),
          ]),
        );
      },
    );
  }
}
