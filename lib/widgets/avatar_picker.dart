import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../l10n/tr.dart';
import '../models/models.dart';
import '../models/video_link.dart';
import '../services/db.dart';
import '../services/video_upload.dart';
import 'ui.dart';

/// Server qabul qiladigan eng katta rasm (Worker `MAX_AVATAR_BYTES` bilan bir xil)
const maxAvatarBytes = 512 * 1024;

enum _AvatarAction { camera, gallery, remove }

/// Profil rasmini qo'yish / almashtirish / olib tashlash — har qanday rol, faqat o'ziga.
/// Rasm R2'ga (`/avatar`) yuklanadi, bazaga faqat havola yoziladi.
Future<void> changeAvatar(BuildContext context, AppUser me) async {
  final has = isAvatarUrl(me.photoUrl);
  final action = await showModalBottomSheet<_AvatarAction>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // brauzerda kamera yo'q — faqat fayl tanlash
        if (!kIsWeb)
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(tr('Kamera')),
            onTap: () => Navigator.pop(ctx, _AvatarAction.camera),
          ),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: Text(tr('Galereya')),
          onTap: () => Navigator.pop(ctx, _AvatarAction.gallery),
        ),
        if (has)
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(tr('Rasmni olib tashlash')),
            onTap: () => Navigator.pop(ctx, _AvatarAction.remove),
          ),
      ]),
    ),
  );
  if (action == null || !context.mounted) return;

  if (action == _AvatarAction.remove) {
    await _busy(context, () async {
      await deleteAvatar();
      await Db.setPhotoUrl(me.id, null);
    }, done: tr('Rasm olib tashlandi'));
    return;
  }

  final XFile? file;
  try {
    // kvadrat avatar uchun 512 px yetarli; siqilgan JPEG odatda 50–150 KB
    file = await ImagePicker().pickImage(
      source: action == _AvatarAction.camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
      preferredCameraDevice: CameraDevice.front,
    );
  } catch (e) {
    if (context.mounted) showSnack(context, trf("Bo'lmadi: {0}", [e]));
    return;
  }
  if (file == null || !context.mounted) return;
  final bytes = await file.readAsBytes();
  if (!context.mounted) return;
  if (bytes.length > maxAvatarBytes) {
    showSnack(context, trf('Rasm juda katta ({0} KB). Boshqasini tanlang.', [bytes.length ~/ 1024]));
    return;
  }
  // server faqat JPEG/PNG/WebP qabul qiladi; boshqa (image/jpg, heic …) — fayl nomidan
  const accepted = {'image/jpeg', 'image/png', 'image/webp'};
  final mime = file.mimeType?.toLowerCase();
  final type = mime != null && accepted.contains(mime) ? mime : avatarContentType(file.name);
  await _busy(context, () async {
    final url = await uploadAvatar(bytes, type);
    await Db.setPhotoUrl(me.id, url);
  }, done: tr('Rasm saqlandi'));
}

/// Ish tugaguncha aylanuvchi belgi; xato bo'lsa — xabar
Future<void> _busy(BuildContext context, Future<void> Function() work, {required String done}) async {
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(canPop: false, child: Center(child: CircularProgressIndicator())),
  );
  try {
    await work();
    nav.pop();
    if (context.mounted) showSnack(context, done);
  } catch (e) {
    nav.pop();
    if (context.mounted) showSnack(context, trf("Bo'lmadi: {0}", [e]));
  }
}

/// O'z avatari: bosilsa rasm qo'yish oynasi ochiladi; burchakda kichik kamera belgisi
class MyAvatar extends StatelessWidget {
  final AppUser me;
  final double size;

  /// Rasm yo'q bo'lganda ko'rinadigan o'z bosh harf bloki (berilmasa — [UserAvatar] uslubi)
  final Widget? placeholder;
  const MyAvatar({super.key, required this.me, this.size = 44, this.placeholder});

  @override
  Widget build(BuildContext context) {
    final badge = (size * 0.36).clamp(14.0, 22.0);
    return Semantics(
      button: true,
      label: tr('Profil rasmi'),
      child: GestureDetector(
        onTap: () => changeAvatar(context, me),
        child: Stack(clipBehavior: Clip.none, children: [
          if (placeholder != null && !isAvatarUrl(me.photoUrl))
            placeholder!
          else
            UserAvatar(name: me.name, size: size, photoUrl: me.photoUrl),
          Positioned(
            right: -3,
            bottom: -3,
            child: Container(
              width: badge,
              height: badge,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.photo_camera_outlined, size: badge * 0.66),
            ),
          ),
        ]),
      ),
    );
  }
}
