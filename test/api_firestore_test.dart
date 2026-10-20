import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kotta_qani_diet/services/api/api_auth.dart';
import 'package:kotta_qani_diet/services/api/api_client.dart';
import 'package:kotta_qani_diet/services/api/api_firestore.dart';

/// Servisning soxta javoblari; so'rovlar [sent] ga yoziladi
class FakeServer {
  final sent = <http.Request>[];
  final routes = <String, Object? Function(http.Request)>{};

  late final client = MockClient((req) async {
    sent.add(req);
    final key = '${req.method} ${req.url.path}';
    final handler = routes[key];
    if (handler == null) return http.Response('{"detail":"yo\'q"}', 404);
    final res = handler(req);
    if (res is http.Response) return res;
    return http.Response(jsonEncode(res), 200, headers: {'content-type': 'application/json'});
  });

  ApiFirestore firestore() => ApiFirestore(ApiClient('http://servis', client: client)..token = 't');
}

Map<String, dynamic> body(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;

void main() {
  group('ApiFirestore — o\'qish', () {
    test('hujjat: vaqt va bayt turlari tiklanadi; id va yo\'l', () async {
      final s = FakeServer();
      s.routes['GET /doc/users/u1/photos/r1'] = (_) => {
            'doc': {
              'id': 'r1',
              'path': 'users/u1/photos/r1',
              'data': {
                'takenAt': {r'$t': '2026-10-20T08:00:00Z'},
                'data': {r'$b': base64Encode([1, 2, 3])},
                'weight': 80.5,
              },
            }
          };
      final d = await s.firestore().collection('users').doc('u1').collection('photos').doc('r1').get();
      expect(d.exists, isTrue);
      expect(d.id, 'r1');
      final data = d.data()!;
      expect(data['takenAt'], Timestamp.fromDate(DateTime.utc(2026, 10, 20, 8)));
      expect((data['data'] as Blob).bytes, Uint8List.fromList([1, 2, 3]));
      expect(data['weight'], 80.5);
    });

    test('yo\'q (yoki ruxsatsiz) hujjat — exists false, data() null', () async {
      final s = FakeServer();
      s.routes['GET /doc/users/u2'] = (_) => {'doc': null};
      final d = await s.firestore().doc('users/u2').get();
      expect(d.exists, isFalse);
      expect(d.data(), isNull);
    });

    test('so\'rov: where / in / orderBy / limit servisga to\'g\'ri boradi', () async {
      final s = FakeServer();
      s.routes['GET /col/orders'] = (_) => {
            'docs': [
              {'id': 'o1', 'path': 'orders/o1', 'data': {'status': 'new'}}
            ]
          };
      final r = await s
          .firestore()
          .collection('orders')
          .where('trainerId', isEqualTo: 't1')
          .where('status', whereIn: ['new', 'given'])
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get();
      expect(r.docs.single.id, 'o1');
      expect(r.docs.single.data()['status'], 'new');
      final q = jsonDecode(s.sent.single.url.queryParameters['q']!);
      expect(q, {
        'where': [
          ['trainerId', '==', 't1'],
          ['status', 'in', ['new', 'given']],
        ],
        'orderBy': [
          ['createdAt', 'desc']
        ],
        'limit': 20,
      });
    });

    test('to\'plam guruhi — /group', () async {
      final s = FakeServer();
      s.routes['GET /group/subscriptions'] = (_) => {'docs': []};
      await s.firestore().collectionGroup('subscriptions').get();
      expect(s.sent.single.url.path, '/group/subscriptions');
    });
  });

  group('ApiFirestore — yozish', () {
    test('set merge, maydon amallari, vaqt va bayt yuboriladi', () async {
      final s = FakeServer();
      s.routes['PUT /doc/users/u1/days/2026-10-20'] = (_) => {'ok': true};
      await s.firestore().doc('users/u1/days/2026-10-20').set({
        'done': const ApiFieldValue({r'$op': 'arrayUnion', 'values': [0]}),
        'at': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
        'pic': Blob(Uint8List.fromList([9])),
      }, SetOptions(merge: true));
      expect(body(s.sent.single), {
        'data': {
          'done': {r'$op': 'arrayUnion', 'values': [0]},
          'at': {r'$t': '2026-01-01T00:00:00.000Z'},
          'pic': {r'$b': base64Encode([9])},
        },
        'merge': true,
      });
    });

    test('update — PATCH, nuqtali kalit o\'zgarmaydi', () async {
      final s = FakeServer();
      s.routes['PATCH /doc/users/u1'] = (_) => {'ok': true};
      await s.firestore().doc('users/u1').update({'program.chest': ['A']});
      expect(body(s.sent.single), {
        'data': {
          'program.chest': ['A']
        }
      });
    });

    test('add — servis bergan id bilan hujjat; doc() — mijozda 20 belgili id', () async {
      final s = FakeServer();
      s.routes['POST /col/chats/u1/messages'] = (_) => {'id': 'm1'};
      final ref = await s.firestore().collection('chats').doc('u1').collection('messages').add({'text': 'salom'});
      expect(ref.path, 'chats/u1/messages/m1');
      final auto = s.firestore().collection('users').doc('u1').collection('weights').doc();
      expect(auto.id.length, 20);
    });

    test('batch — bitta so\'rovda, tartib saqlanadi', () async {
      final s = FakeServer();
      s.routes['POST /batch'] = (_) => {'ids': [null, null]};
      final fs = s.firestore();
      final user = fs.collection('users').doc('u1');
      final b = fs.batch()
        ..set(user.collection('weights').doc('w1'), {'weight': 70})
        ..update(user, {'weight': 70});
      await b.commit();
      final ops = body(s.sent.single)['ops'] as List;
      expect(ops.map((o) => o['op']), ['set', 'update']);
      expect(ops.first['path'], 'users/u1/weights/w1');
    });

    test('tranzaksiya: o\'qish darhol, yozuv oxirida batch', () async {
      final s = FakeServer();
      s.routes['GET /doc/shop/p1'] = (_) => {
            'doc': {'id': 'p1', 'path': 'shop/p1', 'data': {'stock': 5}}
          };
      s.routes['POST /batch'] = (_) => {'ids': [null]};
      final fs = s.firestore();
      await fs.runTransaction((tx) async {
        final d = await tx.get(fs.doc('shop/p1'));
        tx.update(fs.doc('shop/p1'), {'stock': (d.data()!['stock'] as int) - 1});
      });
      expect(s.sent.map((r) => r.method), ['GET', 'POST']);
      expect((body(s.sent.last)['ops'] as List).single['data'], {'stock': 4});
    });
  });

  group('ApiFirestore — jonli', () {
    test('snapshots: avval oladi, o\'z to\'plami signalida qayta oladi, begonasida yo\'q', () async {
      final s = FakeServer();
      var n = 0;
      s.routes['GET /col/chats/u1/messages'] = (_) {
        n++; // har so'rovda bitta xabar ko'payadi
        return {
          'docs': [
            for (var i = 0; i < n; i++) {'id': 'm$i', 'path': 'chats/u1/messages/m$i', 'data': {'text': '$i'}}
          ]
        };
      };
      // tokensiz — haqiqiy WebSocket'ga ulanishga urinmaydi, signal debugEmit bilan
      final fs = ApiFirestore(ApiClient('http://servis', client: s.client));
      final sizes = <int>[];
      final sub = fs.collection('chats').doc('u1').collection('messages').snapshots().listen((q) => sizes.add(q.docs.length));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      fs.live.debugEmit('orders');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      fs.live.debugEmit('messages');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await sub.cancel();
      expect(sizes, [1, 2], reason: 'begona to\'plam signalida qayta olinmadi');
    });
  });

  group('ApiAuth — xato kodlari (ekran xabarlari o\'zgarmaydi)', () {
    test('servis holati -> Firebase kodi', () {
      expect(ApiAuth.authError(const ApiException(401, 'x')).code, 'invalid-credential');
      expect(ApiAuth.authError(const ApiException(403, 'x')).code, 'wrong-password');
      expect(ApiAuth.authError(const ApiException(403, 'x'), forbidden: 'operation-not-allowed').code,
          'operation-not-allowed');
      expect(ApiAuth.authError(const ApiException(409, 'x')).code, 'email-already-in-use');
      expect(ApiAuth.authError(const ApiException(429, 'x')).code, 'too-many-requests');
      expect(ApiAuth.authError(const ApiException(400, 'parol kamida 6 belgi')).code, 'weak-password');
      expect(ApiAuth.authError(TimeoutException('x')).code, 'network-request-failed');
    });

    test('401 — chiqish chaqiriladi (muddati o\'tgan token)', () async {
      var out = 0;
      final c = ApiClient('http://servis',
          client: MockClient((_) async => http.Response('{"detail":"kirish kerak"}', 401)))
        ..token = 't'
        ..onUnauthorized = () => out++;
      await expectLater(c.get('/doc/users/u1'), throwsA(isA<ApiException>()));
      expect(out, 1);
    });
  });
}
