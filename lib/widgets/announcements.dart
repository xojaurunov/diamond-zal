import 'package:flutter/material.dart';
import '../l10n/tr.dart';
import '../models/announcement.dart';
import '../services/settings.dart';
import '../theme.dart';
import 'ui.dart';

/// Shogirdning "Bugun" ekrani tepasidagi zal e'lonlari: oxirgi 7 kundagilari, yopilganlari
/// qayta chiqmaydi (telefonda eslab qolinadi). E'lon yo'q bo'lsa — hech narsa ko'rinmaydi.
class AnnouncementBanner extends StatefulWidget {
  final Stream<List<Announcement>> stream;
  const AnnouncementBanner({super.key, required this.stream});

  @override
  State<AnnouncementBanner> createState() => _AnnouncementBannerState();
}

class _AnnouncementBannerState extends State<AnnouncementBanner> {
  final _hidden = AppSettings.hiddenAnnouncements;

  void _hide(String id) {
    setState(() => _hidden.add(id));
    AppSettings.hideAnnouncement(id);
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Announcement>>(
        stream: widget.stream,
        builder: (context, snap) {
          final list = [
            for (final a in snap.data ?? const <Announcement>[])
              if (a.isFresh() && !_hidden.contains(a.id)) a,
          ];
          if (list.isEmpty) return const SizedBox.shrink();
          final t = Theme.of(context).textTheme;
          return Column(children: [
            for (final a in list)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.sm),
                child: BentoTile(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.xs, AppSpace.md),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpace.sm),
                      child: Icon(Icons.campaign_outlined, color: AppColors.accent),
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: AppSpace.sm),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(trf("Zal e'loni · {0}", [a.dateLabel]),
                              style: t.labelMedium?.copyWith(color: AppColors.accent)),
                          const SizedBox(height: 4),
                          Text(a.text, style: t.bodyMedium),
                        ]),
                      ),
                    ),
                    IconButton(
                      tooltip: tr('Yopish'),
                      onPressed: () => _hide(a.id),
                      icon: Icon(Icons.close, size: 20, color: AppColors.textMuted),
                    ),
                  ]),
                ),
              ),
          ]);
        },
      );
}
