import 'package:flutter/material.dart';
import '../../l10n/tr.dart';
import '../../models/announcement.dart';
import '../../models/models.dart';
import '../../services/db.dart';
import '../../theme.dart';
import '../../widgets/ui.dart';

/// Zal e'lonlari (trener va bosh admin): yangi e'lon yozish va o'chirish.
/// Shogirdlar "Bugun" ekranining tepasida 7 kun ko'radi. Tahrir yo'q — o'chirib, qayta yoziladi.
class AnnouncementsAdminScreen extends StatefulWidget {
  final AppUser admin;

  /// Test uchun: e'lonlar oqimi va yozish/o'chirish (odatda — `Db`)
  final Stream<List<Announcement>>? stream;
  final Future<void> Function(String text)? onAdd;
  final Future<void> Function(String id)? onDelete;

  const AnnouncementsAdminScreen({super.key, required this.admin, this.stream, this.onAdd, this.onDelete});

  @override
  State<AnnouncementsAdminScreen> createState() => _AnnouncementsAdminScreenState();
}

class _AnnouncementsAdminScreenState extends State<AnnouncementsAdminScreen> {
  final _text = TextEditingController();
  late final _stream = widget.stream ?? Db.announcements();
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final text = _text.text.trim();
    if (text.isEmpty) {
      showSnack(context, tr("E'lon matnini yozing"));
      return;
    }
    setState(() => _busy = true);
    try {
      await (widget.onAdd ?? (t) => Db.addAnnouncement(t, widget.admin.id))(text);
      _text.clear();
      if (mounted) showSnack(context, tr("E'lon qilindi"));
    } catch (e) {
      if (mounted) showSnack(context, trf("Bo'lmadi: {0}", [e]));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Announcement a) async {
    final ok = await confirm(
      context,
      title: tr("E'lonni o'chirish"),
      message: a.text,
      ok: tr("O'chirish"),
      destructive: true,
    );
    if (!ok) return;
    try {
      await (widget.onDelete ?? Db.deleteAnnouncement)(a.id);
    } catch (e) {
      if (mounted) showSnack(context, trf("Bo'lmadi: {0}", [e]));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr("E'lonlar"))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xs, AppSpace.lg, AppSpace.xxl),
        children: [
          Text(
            tr("Shogirdlar e'lonni \"Bugun\" ekranining tepasida 7 kun ko'radi."),
            style: t.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: _text,
            minLines: 2,
            maxLines: 6,
            maxLength: Announcement.maxLength,
            decoration: InputDecoration(hintText: tr("Masalan: Ertaga zal 10:00 da ochiladi")),
          ),
          const SizedBox(height: AppSpace.sm),
          FilledButton.icon(
            onPressed: _busy ? null : _add,
            icon: const Icon(Icons.campaign_outlined),
            label: Text(tr("E'lon qilish")),
          ),
          const SizedBox(height: AppSpace.xl),
          SectionHeader(tr("Oxirgi e'lonlar")),
          StreamBuilder<List<Announcement>>(
            stream: _stream,
            builder: (context, snap) {
              if (snap.hasError) return Text(trf("Bo'lmadi: {0}", [snap.error]));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final list = snap.data!;
              if (list.isEmpty) {
                return Text(tr("Hali e'lon yo'q"), style: TextStyle(color: AppColors.textMuted));
              }
              return Column(children: [
                for (final a in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.sm),
                    child: BentoTile(
                      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.xs, AppSpace.md),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: AppSpace.sm),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(
                                a.isFresh() ? a.dateLabel : trf("{0} · ko'rinmaydi (7 kundan eski)", [a.dateLabel]),
                                style: t.labelMedium?.copyWith(color: AppColors.textMuted),
                              ),
                              const SizedBox(height: 4),
                              Text(a.text, style: t.bodyMedium),
                            ]),
                          ),
                        ),
                        // o'chirish — muallif yoki bosh admin (qoida ham shunday)
                        if (widget.admin.isOwner || a.createdBy == widget.admin.id)
                          IconButton(
                            tooltip: tr("O'chirish"),
                            onPressed: () => _delete(a),
                            icon: Icon(Icons.delete_outline, color: AppColors.textMuted),
                          ),
                      ]),
                    ),
                  ),
              ]);
            },
          ),
        ],
      ),
    );
  }
}
