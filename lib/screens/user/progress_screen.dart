import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/models.dart';
import '../../services/db.dart';
import '../../theme.dart';
import '../../widgets/ui.dart';

class ProgressScreen extends StatelessWidget {
  final AppUser user;
  final bool readOnly;
  const ProgressScreen({super.key, required this.user, this.readOnly = false});

  /// Vazn haftada faqat 1 marta kiritiladi — erta kiritib bo'lmaydi:
  /// kunlik tebranish (1–2 kg) grafikni chalg'itadi.
  Future<void> _add(BuildContext context, WeightLog? lastLog) async {
    if (!WeightLog.canAdd(lastLog)) {
      final left = WeightLog.daysLeft(lastLog);
      showSnack(
        context,
        "Vazn haftada 1 marta kiritiladi. Keyingi o'lchov "
        "${left == 1 ? 'ertaga' : '$left kundan keyin'}.",
      );
      return;
    }
    final c = TextEditingController(text: user.weight > 0 ? fmtNum(user.weight) : '');
    // Ekran o'rtasidagi pop-up emas — pastdan chiquvchi varaq (bosh barmoq zonasi)
    final w = await showSheet<double>(
      context,
      Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Bugungi vazn', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpace.xs),
            Text(
              'Haftada 1 marta — ertalab, nahorga tortiling',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: AppSpace.lg),
            TextField(
              controller: c,
              autofocus: true,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, fontFeatures: tabular),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(suffixText: 'kg'),
            ),
            const SizedBox(height: AppSpace.lg),
            FilledButton(
              onPressed: () => Navigator.pop(context, double.tryParse(c.text.replaceAll(',', '.'))),
              child: const Text('Saqlash'),
            ),
          ]),
    );
    if (w == null) return;
    if (w < 30 || w > 300) {
      if (context.mounted) showSnack(context, "Vazn 30–300 kg oralig'ida bo'lishi kerak");
      return;
    }
    await Db.addWeight(user.id, w);
    if (context.mounted) showSnack(context, 'Saqlandi: ${fmtNum(w)} kg');
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return StreamBuilder<List<WeightLog>>(
      stream: Db.weights(user.id),
      builder: (context, snap) {
        final all = snap.data;
        final lastLog = (all == null || all.isEmpty) ? null : all.last;
        // O'lchov muddati kelganda tugma urg'uli; kelmaguncha — o'chiq, necha kun qolgani yoziladi
        final due = WeightLog.canAdd(lastLog);
        final left = WeightLog.daysLeft(lastLog);
        return Scaffold(
          appBar: readOnly ? null : AppBar(title: const Text('Progress')),
          floatingActionButton: readOnly
              ? null
              : FloatingActionButton.extended(
                  // ma'lumot yuklanmaguncha o'chirilgan — aks holda haftalik
                  // tekshiruv lastLog'siz o'tkazib yuborilardi
                  onPressed: snap.hasData ? () => _add(context, lastLog) : null,
                  backgroundColor: due ? AppColors.accent : AppColors.card,
                  foregroundColor: due ? AppColors.onAccent : AppColors.textMuted,
                  icon: Icon(due ? Icons.add : Icons.lock_clock_outlined),
                  label: Text(due
                      ? 'Vazn kiritish'
                      : (left == 1 ? 'Vazn: ertaga' : 'Vazn: $left kundan keyin')),
                ),
          body: Builder(
            builder: (context) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final logs = snap.data!;
              if (logs.isEmpty) {
                return EmptyState(
                  icon: Icons.monitor_weight_outlined,
                  title: 'Hali vazn kiritilmagan',
                  subtitle: readOnly
                      ? null
                      : "Haftada 1 marta, ertalab nahorga tortilib, vazningizni kiriting. "
                          "Har kuni o'lchash shart emas — vazn kun davomida 1–2 kg tebranadi.",
                );
              }
              final first = logs.first.weight, last = logs.last.weight;
              final diff = last - first;
              final weights = logs.map((e) => e.weight);
              final minY = (weights.reduce((a, b) => a < b ? a : b) - 2).floorToDouble();
              final maxY = (weights.reduce((a, b) => a > b ? a : b) + 2).ceilToDouble();

              return ListView(
                padding:
                    EdgeInsets.fromLTRB(AppSpace.lg, readOnly ? 0 : AppSpace.sm, AppSpace.lg, 96),
                children: [
                  // Bosh ko'rsatkich — umumiy o'zgarish, ink fonda yirik raqam
                  FadeInUp(
                      child: _ChangePanel(diff: diff, from: first, to: last, gain: user.isGain)),
                  const SizedBox(height: AppSpace.md),
                  if (!readOnly) ...[
                    FadeInUp(index: 1, child: _WeeklyCard(last: logs.last)),
                    const SizedBox(height: AppSpace.md),
                  ],
                  FadeInUp(
                    index: 2,
                    child: Row(children: [
                      Expanded(
                        child: StatTile(
                          icon: Icons.flag_outlined,
                          label: "Boshlang'ich",
                          value: '${fmtNum(first)} kg',
                          color: s.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: AppSpace.md),
                      Expanded(
                        child: StatTile(
                          icon: Icons.monitor_weight_outlined,
                          label: 'Hozir',
                          value: '${fmtNum(last)} kg',
                          color: AppColors.water,
                        ),
                      ),
                      const SizedBox(width: AppSpace.md),
                      Expanded(
                        child: StatTile(
                          icon: Icons.event_repeat_outlined,
                          label: "O'lchov",
                          value: '${logs.length}',
                          color: AppColors.protein,
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: AppSpace.md),
                  BentoTile(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpace.md, AppSpace.lg, AppSpace.xl, AppSpace.md),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Padding(
                        padding: const EdgeInsets.only(left: AppSpace.sm, bottom: AppSpace.lg),
                        child: Eyebrow('Vazn dinamikasi', color: s.onSurfaceVariant),
                      ),
                      SizedBox(
                        height: 220,
                        child: LineChart(LineChartData(
                          minY: minY,
                          maxY: maxY,
                          borderData: FlBorderData(show: false),
                          gridData: FlGridData(
                            drawVerticalLine: false,
                            getDrawingHorizontalLine: (_) => FlLine(
                              color: s.outlineVariant.withValues(alpha: 0.5),
                              strokeWidth: 1,
                              dashArray: const [4, 4],
                            ),
                          ),
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles:
                                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            bottomTitles:
                                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 36,
                                getTitlesWidget: (v, meta) => Text(
                                  v.toStringAsFixed(0),
                                  style: t.bodySmall?.copyWith(color: s.onSurfaceVariant),
                                ),
                              ),
                            ),
                          ),
                          lineTouchData: LineTouchData(
                            touchTooltipData: LineTouchTooltipData(
                              getTooltipColor: (_) => s.inverseSurface,
                              getTooltipItems: (spots) => spots
                                  .map((sp) => LineTooltipItem(
                                        '${fmtNum(sp.y)} kg\n',
                                        TextStyle(
                                            color: s.onInverseSurface, fontWeight: FontWeight.w700),
                                        children: [
                                          TextSpan(
                                            text:
                                                DateFormat('dd.MM').format(logs[sp.x.toInt()].date),
                                            style: TextStyle(
                                              color: s.onInverseSurface.withValues(alpha: 0.7),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w400,
                                            ),
                                          ),
                                        ],
                                      ))
                                  .toList(),
                            ),
                          ),
                          lineBarsData: [
                            LineChartBarData(
                              spots: [
                                for (var i = 0; i < logs.length; i++)
                                  FlSpot(i.toDouble(), logs[i].weight),
                              ],
                              isCurved: true,
                              preventCurveOverShooting: true,
                              color: s.primary,
                              barWidth: 3,
                              isStrokeCapRound: true,
                              dotData: FlDotData(
                                getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                                  radius: 4,
                                  color: s.surface,
                                  strokeWidth: 2.5,
                                  strokeColor: s.primary,
                                ),
                              ),
                              belowBarData: BarAreaData(
                                show: true,
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    s.primary.withValues(alpha: 0.25),
                                    s.primary.withValues(alpha: 0.0),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )),
                      ),
                    ]),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  const SectionHeader('Tarix', eyebrow: "O'lchovlar"),
                  BentoTile(
                    padding: EdgeInsets.zero,
                    child: Column(children: [
                      for (var i = logs.length - 1; i >= 0; i--) ...[
                        _HistoryRow(log: logs[i], prev: i > 0 ? logs[i - 1] : null),
                        if (i > 0) const Divider(indent: AppSpace.lg, endIndent: AppSpace.lg),
                      ],
                    ]),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// Haftalik o'lchov holati: keyingi o'lchovgacha necha kun qolgani.
/// Vazn haftada 1 marta kiritiladi — kunlik tebranish (1–2 kg) natijani buzadi.
class _WeeklyCard extends StatelessWidget {
  final WeightLog last;
  const _WeeklyCard({required this.last});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final days = WeightLog.daysSince(last.date);
    final left = WeightLog.daysLeft(last);
    final due = left <= 0;

    final (String title, String sub, Color color, IconData icon) = due
        ? (
            'Vaznni kiritish vaqti keldi',
            days == 7 ? "Oxirgi o'lchovdan 7 kun o'tdi" : "Oxirgi o'lchovdan $days kun o'tdi",
            AppColors.warning,
            Icons.notifications_active_outlined,
          )
        : (
            left == 1 ? 'Keyingi o’lchov ertaga' : 'Keyingi o’lchov $left kundan keyin',
            'Haftada faqat 1 marta — ungacha vaznni o’zgartirib bo’lmaydi',
            AppColors.success,
            Icons.event_available_outlined,
          );

    return BentoTile(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Row(children: [
        IconBadge(icon, color: color, size: 38),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: t.titleMedium),
            const SizedBox(height: 2),
            Text(sub, style: t.bodySmall?.copyWith(color: s.onSurfaceVariant)),
          ]),
        ),
      ]),
    );
  }
}

/// Umumiy o'zgarish — ink fonda yirik editorial raqam
class _ChangePanel extends StatelessWidget {
  final double diff, from, to;

  /// Massa nabor maqsadida vazn oshishi — yaxshi natija (urg'u rangi), ozishda — kamayishi
  final bool gain;
  const _ChangePanel({
    required this.diff,
    required this.from,
    required this.to,
    this.gain = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final good = diff == 0 || (gain ? diff > 0 : diff < 0);
    final accent = good ? AppColors.accent : AppColors.warning;
    final sign = diff > 0 ? '+' : (diff < 0 ? '−' : '');
    return BentoTile(
      feature: true,
      padding: const EdgeInsets.all(AppSpace.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Eyebrow('Umumiy o’zgarish', color: AppColors.textFaint),
          const Spacer(),
          Icon(
            diff == 0
                ? Icons.trending_flat_rounded
                : (diff < 0 ? Icons.trending_down_rounded : Icons.trending_up_rounded),
            color: accent,
            size: 20,
          ),
        ]),
        const SizedBox(height: AppSpace.md),
        Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$sign${diff.abs().toStringAsFixed(1)}',
                style: t.displaySmall?.copyWith(color: accent, fontFeatures: tabular),
              ),
              const SizedBox(width: AppSpace.sm),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('kg', style: t.titleMedium?.copyWith(color: AppColors.textFaint)),
              ),
            ]),
        const SizedBox(height: AppSpace.sm),
        Text(
          '${fmtNum(from)} kg dan ${fmtNum(to)} kg gacha',
          style: t.bodySmall?.copyWith(
            color: AppColors.textMuted,
            fontFeatures: tabular,
          ),
        ),
      ]),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final WeightLog log;
  final WeightLog? prev;
  const _HistoryRow({required this.log, this.prev});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final d = prev == null ? null : log.weight - prev!.weight;
    return ListTile(
      title: Text('${fmtNum(log.weight)} kg', style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(DateFormat('dd.MM.yyyy, HH:mm').format(log.date)),
      trailing: d == null
          ? Pill(text: 'Start', color: s.outline)
          : Pill(
              text: '${d > 0 ? '+' : ''}${d.toStringAsFixed(1)}',
              color: d <= 0 ? AppColors.success : AppColors.warning,
              icon: d <= 0 ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
            ),
    );
  }
}
