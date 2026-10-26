import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/tr.dart';
import '../../models/lesson.dart';
import '../../models/models.dart';
import '../../models/video_link.dart';
import '../../services/db.dart';
import '../../services/video_upload.dart';
import '../../theme.dart';
import '../../widgets/ui.dart';
import '../user/videos_screen.dart';

/// Trener / bosh admin: video darslar (mashqqa bog'liq bo'lmagan videolar) — qo'shish, tahrirlash,
/// o'chirish. Shogird ularni "Videolar" bo'limida ko'radi. "Hamma videolar" — shogird ko'radigan tasma.
class LessonsAdminScreen extends StatefulWidget {
  final AppUser admin;
  const LessonsAdminScreen({super.key, required this.admin});

  @override
  State<LessonsAdminScreen> createState() => _LessonsAdminScreenState();
}

class _LessonsAdminScreenState extends State<LessonsAdminScreen> {
  late final _lessons = Db.lessons();

  Future<void> _edit([Lesson? l]) async {
    final saved = await showSheet<bool>(context, LessonForm(adminId: widget.admin.id, existing: l));
    if (saved == true && mounted) showSnack(context, tr('Dars saqlandi'));
  }

  Future<void> _delete(Lesson l) async {
    final ok = await confirm(context,
        title: tr("Darsni o'chirish"),
        message: trf("\"{0}\" o'chiriladi — video ham.", [l.title]),
        ok: tr("O'chirish"),
        destructive: true);
    if (!ok) return;
    try {
      await Db.deleteLesson(l.id);
      if (isUploadedVideo(l.url)) unawaited(deleteVideo(l.url).catchError((_) {}));
      if (mounted) showSnack(context, tr("Dars o'chirildi"));
    } catch (e) {
      if (mounted) showSnack(context, trf("O'chirib bo'lmadi: {0}", [e]));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Video darslar')), actions: [
        TextButton.icon(
          onPressed: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => VideosScreen(user: widget.admin))),
          icon: const Icon(Icons.video_library_outlined),
          label: Text(tr('Hamma videolar')),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _edit,
        icon: const Icon(Icons.add),
        label: Text(tr("Dars qo'shish")),
      ),
      body: StreamBuilder<List<Lesson>>(
        stream: _lessons,
        builder: (context, snap) {
          if (!snap.hasData && !snap.hasError) return const Center(child: CircularProgressIndicator());
          final all = snap.data ?? const [];
          return ListView(
            padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xs, AppSpace.lg, 96),
            children: [
              Text(
                tr("Mashq videolari mashqning o'zida (Mashqlar). Bu yerda — ovqatlanish, texnika, "
                    "nafas, motivatsiya darslari. Shogird ularni \"Videolar\" bo'limida ko'radi."),
                style: t.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: AppSpace.md),
              if (all.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppSpace.xl),
                  child: Text(tr("Hali dars yo'q."),
                      textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: AppColors.textMuted)),
                ),
              for (final l in all)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.ondemand_video_outlined),
                  title: Text(l.title),
                  subtitle: Text([
                    tr(lessonCategories[l.category] ?? ''),
                    if (l.seconds > 0) durationText(l.seconds),
                  ].join(' · ')),
                  onTap: () => _edit(l),
                  trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(l)),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Dars formasi: nomi, turi, izohi, video (telefonda yuklash yoki havola)
class LessonForm extends StatefulWidget {
  final String adminId;
  final Lesson? existing;
  const LessonForm({super.key, required this.adminId, this.existing});

  @override
  State<LessonForm> createState() => _LessonFormState();
}

class _LessonFormState extends State<LessonForm> {
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _desc = TextEditingController(text: widget.existing?.description);
  late final _url = TextEditingController(text: widget.existing?.url);
  late String _category = widget.existing?.category ?? 'texnika';
  late int _seconds = widget.existing?.seconds ?? 0;
  final _uploads = <String>{};
  double? _progress;
  bool _compressing = false, _busy = false, _saved = false;
  String? _error;

  @override
  void dispose() {
    if (_progress != null) unawaited(cancelVideoUpload());
    if (!_saved) {
      for (final u in _uploads) {
        unawaited(deleteVideo(u).catchError((_) {}));
      }
    }
    _title.dispose();
    _desc.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _upload() async {
    final file = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (file == null || !mounted) return;
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      final up = await uploadVideo(file.path, file.name, onCompress: (p) {
        if (mounted) {
          setState(() {
            _compressing = true;
            _progress = p;
          });
        }
      }, onProgress: (p) {
        if (mounted) {
          setState(() {
            _compressing = false;
            _progress = p;
          });
        }
      });
      _uploads.add(up.url);
      if (mounted) {
        setState(() {
          _url.text = up.url;
          _seconds = up.seconds;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = trf('Video yuklanmadi: {0}', [e]));
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim(), url = _url.text.trim();
    if (title.isEmpty) return setState(() => _error = tr('Dars nomini yozing'));
    if (!RegExp(r'^https?://\S+$').hasMatch(url)) return setState(() => _error = tr('Video yuklang yoki havola qo\'ying'));
    setState(() {
      _busy = true;
      _error = null;
    });
    final old = widget.existing;
    try {
      await Db.saveLesson(Lesson(
        id: old?.id ?? '',
        title: title,
        category: _category,
        description: _desc.text.trim(),
        url: url,
        seconds: _seconds,
        // tahrirda birinchi muallif va vaqt saqlanadi (qoida ham shuni talab qiladi)
        createdAt: old?.createdAt ?? DateTime.now(),
        createdBy: old?.createdBy ?? widget.adminId,
      ));
      _saved = true;
      for (final u in {..._uploads, if (old != null) old.url}) {
        if (u != url && isUploadedVideo(u)) unawaited(deleteVideo(u).catchError((_) {}));
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = trf("Saqlab bo'lmadi: {0}", [e]);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final uploaded = isUploadedVideo(_url.text);
    return SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.existing == null ? tr("Dars qo'shish") : tr('Darsni tahrirlash'), style: t.titleLarge),
        const SizedBox(height: AppSpace.md),
        TextField(
          controller: _title,
          maxLength: 80,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: tr('Dars nomi')),
        ),
        Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xs, children: [
          for (final c in lessonCategories.entries)
            ChoiceChip(label: Text(tr(c.value)), selected: _category == c.key, onSelected: (_) => setState(() => _category = c.key)),
        ]),
        const SizedBox(height: AppSpace.sm),
        TextField(
          controller: _desc,
          maxLength: 500,
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: tr('Qisqa izoh (ixtiyoriy)')),
        ),
        TextField(
          controller: _url,
          maxLength: 300,
          readOnly: uploaded,
          keyboardType: TextInputType.url,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: uploaded ? tr('Yuklangan video') : tr('Video havolasi (yoki yuklang)'),
            hintText: 'https://',
          ),
        ),
        if (_progress != null) ...[
          LinearProgressIndicator(value: _progress),
          const SizedBox(height: 4),
          Text(
            _compressing
                ? trf('Video kichraytirilmoqda… {0}% (ilovani yopmang)', [((_progress ?? 0) * 100).round()])
                : trf('Video yuklanmoqda… {0}%', [((_progress ?? 0) * 100).round()]),
            style: t.bodySmall,
          ),
        ] else
          Wrap(spacing: AppSpace.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (canUploadVideo)
              OutlinedButton.icon(
                onPressed: _busy ? null : _upload,
                icon: const Icon(Icons.upload),
                label: Text(tr('Video yuklash')),
              ),
            if (uploaded)
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _url.text = '';
                          _seconds = 0;
                        }),
                icon: const Icon(Icons.delete_outline),
                label: Text(tr("Videoni o'chirish")),
              ),
            if (canUploadVideo)
              Text(tr("5 daqiqagacha — ilova o'zi kichraytiradi"),
                  style: t.bodySmall?.copyWith(color: AppColors.textMuted)),
          ]),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.sm),
            child: Text(_error!, style: t.bodyMedium?.copyWith(color: AppColors.danger)),
          ),
        const SizedBox(height: AppSpace.md),
        FilledButton(
          onPressed: _busy || _progress != null ? null : _save,
          child: Text(_busy ? tr('Saqlanmoqda…') : tr('Saqlash')),
        ),
      ]),
    );
  }
}
