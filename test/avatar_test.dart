import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotta_qani_diet/models/models.dart';
import 'package:kotta_qani_diet/models/video_link.dart';
import 'package:kotta_qani_diet/services/video_upload.dart';
import 'package:kotta_qani_diet/widgets/ui.dart';

// ignore: subtype_of_sealed_class
/// Faqat `id` va `data()` kerak — `AppUser.fromDoc` shularni o'qiydi
class _Doc extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  @override
  final String id;
  final Map<String, dynamic> _data;
  _Doc(this.id, this._data);
  @override
  Map<String, dynamic> data() => _data;
}

const _uuid = '0b7c6a1e-2f3d-4c5b-8a9e-1f2a3b4c5d6e';
const _avatar = '$videoServer/v/avatars/abcDEF123/$_uuid.jpg';

void main() {
  group('profil rasmi', () {
    test("fromDoc photoUrl'ni o'qiydi, toMap unga tegmaydi", () {
      final u = AppUser.fromDoc(_Doc('abcDEF123', {'name': 'Ali', 'photoUrl': _avatar}));
      expect(u.photoUrl, _avatar);
      expect(u.toMap().containsKey('photoUrl'), isFalse,
          reason: "trener shogird profilini saqlaganda rasm o'chib ketmasin");
      expect(AppUser.fromDoc(_Doc('x', {'name': 'Vali'})).photoUrl, isNull);
      // boshqaning rasmini (boshqa uid papkasi) yoki begona havolani o'ziniki qilib ko'rsata olmaydi
      expect(AppUser.fromDoc(_Doc('boshqa1', {'name': 'X', 'photoUrl': _avatar})).photoUrl, isNull);
      expect(AppUser.fromDoc(_Doc('abcDEF123', {'photoUrl': 'https://evil.example.com/a.jpg'})).photoUrl, isNull);
      expect(isAvatarUrlOf(_avatar, 'abcDEF123'), isTrue);
      expect(isAvatarUrlOf(_avatar, 'abcDEF12'), isFalse, reason: "uid prefiksi emas — to'liq papka");
    });

    test("trener katalogi: TrainerInfo photoUrl'ni o'qiydi (faqat o'ziniki), toMap unga tegmaydi", () {
      final t = TrainerInfo.fromDoc(_Doc('abcDEF123', {'name': 'Qobil aka', 'photoUrl': _avatar}));
      expect(t.photoUrl, _avatar);
      expect(t.toMap().containsKey('photoUrl'), isFalse,
          reason: "trener ma'lumotini saqlaganda rasm o'chib ketmasin");
      expect(TrainerInfo.fromDoc(_Doc('boshqa1', {'name': 'X', 'photoUrl': _avatar})).photoUrl, isNull);
      expect(TrainerInfo.fromDoc(_Doc('abcDEF123', {'name': 'X'})).photoUrl, isNull);
    });

    test('isAvatarUrl: faqat o\'z serverimizdagi avatar', () {
      expect(isAvatarUrl(_avatar), isTrue);
      expect(isAvatarUrl('$videoServer/v/avatars/abc/$_uuid.png'), isTrue);
      expect(isAvatarUrl('$videoServer/v/avatars/abc/$_uuid.webp'), isTrue);
      expect(isAvatarUrl(null), isFalse);
      expect(isAvatarUrl(''), isFalse);
      // begona sayt, video, yo'l bilan o'ynash, noto'g'ri kengaytma
      expect(isAvatarUrl('https://evil.example.com/v/avatars/abc/$_uuid.jpg'), isFalse);
      expect(isAvatarUrl('$videoServer/v/videos/$_uuid.jpg'), isFalse);
      expect(isAvatarUrl('$videoServer/v/avatars/../videos/$_uuid.jpg'), isFalse);
      expect(isAvatarUrl('$videoServer/v/avatars/abc/$_uuid.svg'), isFalse);
      expect(isAvatarUrl('$_avatar?x=1'), isFalse);
    });

    test('avatarContentType', () {
      expect(avatarContentType('a.PNG'), 'image/png');
      expect(avatarContentType('a.webp'), 'image/webp');
      expect(avatarContentType('a.jpg'), 'image/jpeg');
      expect(avatarContentType('scaled_123'), 'image/jpeg');
    });

    Widget wrap(Widget w) => MaterialApp(home: Scaffold(body: Center(child: w)));

    testWidgets("rasm yo'q yoki begona havola — bosh harflar", (tester) async {
      await tester.pumpWidget(wrap(const UserAvatar(name: 'Ali Valiyev')));
      expect(find.text('AV'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      await tester.pumpWidget(
          wrap(const UserAvatar(name: 'Ali Valiyev', photoUrl: 'https://evil.example.com/a.jpg')));
      expect(find.text('AV'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets("o'z serverimizdagi avatar — rasm (bosh harflar emas)", (tester) async {
      await tester.pumpWidget(wrap(UserAvatar(name: 'Ali Valiyev', photoUrl: _avatar)));
      expect(find.text('AV'), findsNothing);
    });
  });
}
