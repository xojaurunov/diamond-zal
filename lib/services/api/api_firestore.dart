// Firestore klasslari `@sealed` (tavsiya, til taqiqi emas) — servis rejimida ularni aynan takrorlash
// shart: `db.dart` va modellar shu turlar bilan ishlaydi. Firebase rejimida bu fayl ishlatilmaydi.
// ignore_for_file: subtype_of_sealed_class
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'api_client.dart';
import 'api_socket.dart';

/// Qobil servisi uchun Firestore'ga o'xshash mijoz. `db.dart` dagi chaqiruvlar (collection, doc,
/// where, orderBy, limit, get, snapshots, set, update, delete, add, batch, runTransaction) shu bilan
/// o'zgarishsiz ishlaydi. Ishlatilmaydigan a'zolar `noSuchMethod` bilan — chaqirilsa xato beradi.
///
/// Turlar: `Timestamp`/`DateTime` <-> `{"$t": ...}`, `Blob` <-> `{"$b": ...}`; maydon amallari — [Fv].
class ApiFirestore implements FirebaseFirestore {
  ApiFirestore(this.client);

  final ApiClient client;
  late final ApiLive live = ApiLive(client);

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      ApiCollectionRef(this, _clean(collectionPath));

  @override
  DocumentReference<Map<String, dynamic>> doc(String documentPath) => ApiDocRef(this, _clean(documentPath));

  @override
  Query<Map<String, dynamic>> collectionGroup(String collectionPath) =>
      ApiQuery(this, collectionPath, group: true);

  @override
  WriteBatch batch() => ApiBatch(this);

  @override
  Future<T> runTransaction<T>(TransactionHandler<T> transactionHandler,
      {Duration timeout = const Duration(seconds: 30), int maxAttempts = 5}) async {
    final tx = ApiTransaction(this);
    final result = await transactionHandler(tx);
    await tx.commit();
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('ApiFirestore: ${invocation.memberName}');

  static String _clean(String path) => path.split('/').where((p) => p.isNotEmpty).join('/');
}

/// Servisga yuboriladigan maydon amali (serverTimestamp, delete, arrayUnion, arrayRemove)
class ApiFieldValue {
  final Map<String, Object?> json;
  const ApiFieldValue(this.json);
}

/// Firestore yoki servis — `FieldValue` o'rniga ishlatiladi (`db.dart`)
class Fv {
  static Object serverTimestamp() =>
      useApi ? const ApiFieldValue({r'$op': 'serverTimestamp'}) : FieldValue.serverTimestamp();
  static Object delete() => useApi ? const ApiFieldValue({r'$op': 'delete'}) : FieldValue.delete();
  static Object arrayUnion(List<Object?> values) =>
      useApi ? ApiFieldValue({r'$op': 'arrayUnion', 'values': encodeValue(values)}) : FieldValue.arrayUnion(values);
  static Object arrayRemove(List<Object?> values) =>
      useApi ? ApiFieldValue({r'$op': 'arrayRemove', 'values': encodeValue(values)}) : FieldValue.arrayRemove(values);
}

/// Dart qiymati -> servis JSON
Object? encodeValue(Object? v) {
  if (v is ApiFieldValue) return v.json;
  if (v is Timestamp) return {r'$t': v.toDate().toUtc().toIso8601String()};
  if (v is DateTime) return {r'$t': v.toUtc().toIso8601String()};
  if (v is Blob) return {r'$b': base64Encode(v.bytes)};
  if (v is Map) return {for (final e in v.entries) e.key.toString(): encodeValue(e.value)};
  if (v is Iterable) return [for (final x in v) encodeValue(x)];
  return v;
}

/// Servis JSON -> Dart qiymati (`Timestamp`, `Blob`)
Object? decodeValue(Object? v) {
  if (v is Map) {
    if (v.length == 1 && v.containsKey(r'$t')) return Timestamp.fromDate(DateTime.parse(v[r'$t'] as String));
    if (v.length == 1 && v.containsKey(r'$b')) return Blob(base64Decode(v[r'$b'] as String));
    return <String, dynamic>{for (final e in v.entries) e.key.toString(): decodeValue(e.value)};
  }
  if (v is List) return [for (final x in v) decodeValue(x)];
  return v;
}

Map<String, dynamic> _encodeData(Map<Object?, Object?> data) =>
    {for (final e in data.entries) e.key.toString(): encodeValue(e.value)};

final _rnd = Random.secure();

/// Firestore'dagidek 20 belgili id (hujjat mijozda nomlanadi — batch'da kerak)
String autoId() {
  const abc = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  return String.fromCharCodes(Iterable.generate(20, (_) => abc.codeUnitAt(_rnd.nextInt(abc.length))));
}

/// Jonli yangilanish: servis WebSocket orqali o'zgargan to'plam nomini yuboradi; obunachilar
/// o'z so'rovini qayta oladi. Uzilsa qayta ulanadi; ulanganda hamma qayta oladi ('*').
class ApiLive {
  ApiLive(this.client);

  final ApiClient client;
  final _events = StreamController<String>.broadcast();
  ApiSocket? _socket;
  bool _connecting = false;
  int _listeners = 0;
  Timer? _ping;

  /// WebSocket ishlamasa ham ochiq ro'yxatlar eskirib qolmasin — har 30 soniyada qayta olish
  Timer? _fallback;

  Stream<String> get events => _events.stream;

  /// Testda signal yuborish (WebSocket'siz)
  @visibleForTesting
  void debugEmit(String collection) => _events.add(collection);

  void acquire() {
    _listeners++;
    _fallback ??= Timer.periodic(const Duration(seconds: 30), (_) {
      if (_socket == null) _events.add('*');
    });
    _ensure();
  }

  /// O'zimiz yozgan to'plam — signal kutmasdan qayta olinadi (Firestore'dagi kabi darhol ko'rinadi)
  void local(String collection) => _events.add(collection);

  void release() {
    _listeners--;
    if (_listeners <= 0) {
      _listeners = 0;
      close();
    }
  }

  Future<void> close() async {
    _fallback?.cancel();
    _fallback = null;
    _ping?.cancel();
    final s = _socket;
    _socket = null;
    await s?.close();
  }

  Future<void> _ensure() async {
    if (_socket != null || _connecting || client.token == null || _listeners == 0) return;
    _connecting = true;
    try {
      final s = await connectSocket(client.socketUrl);
      s.send(jsonEncode({'token': client.token}));
      _socket = s;
      _events.add('*');
      _ping = Timer.periodic(const Duration(seconds: 25), (_) => s.send('ping'));
      s.messages.listen((m) {
        try {
          _events.add((jsonDecode(m) as Map)['c'] as String);
        } catch (_) {}
      }, onDone: _lost, onError: (_) => _lost(), cancelOnError: true);
    } catch (_) {
      _socket = null;
      Timer(const Duration(seconds: 5), _ensure);
    } finally {
      _connecting = false;
    }
  }

  void _lost() {
    _ping?.cancel();
    _socket = null;
    if (_listeners > 0) Timer(const Duration(seconds: 3), _ensure);
  }
}

/// Ma'lumotni bir so'rov bilan oluvchi va o'zgarishda qayta oluvchi oqim (Firestore `snapshots()`).
Stream<T> _liveStream<T>(ApiFirestore fs, String collection, Future<T> Function() fetch, String Function(T) key) {
  late StreamController<T> c;
  StreamSubscription<String>? sub;
  Timer? debounce;
  String? last;
  Future<void> load() async {
    try {
      final v = await fetch();
      final k = key(v);
      if (k != last && !c.isClosed) {
        last = k;
        c.add(v);
      }
    } catch (e, s) {
      if (!c.isClosed) c.addError(e, s);
    }
  }

  c = StreamController<T>(
    onListen: () {
      fs.live.acquire();
      sub = fs.live.events.listen((name) {
        if (name != '*' && name != collection) return;
        debounce?.cancel();
        debounce = Timer(const Duration(milliseconds: 250), load);
      });
      load();
    },
    onCancel: () async {
      debounce?.cancel();
      await sub?.cancel();
      fs.live.release();
    },
  );
  return c.stream;
}

class ApiQuery implements Query<Map<String, dynamic>> {
  ApiQuery(this.fs, this.path, {this.group = false, this.filters = const [], this.orders = const [], this.max});

  final ApiFirestore fs;

  /// To'plam yo'li (yoki guruh nomi)
  final String path;
  final bool group;
  final List<List<Object?>> filters;
  final List<List<Object?>> orders;
  final int? max;

  /// Jonli signal nomi — yo'lning oxirgi qismi (`users/u1/days` -> `days`)
  String get _collectionName => path.split('/').last;

  ApiQuery _copy({List<List<Object?>>? filters, List<List<Object?>>? orders, int? max}) =>
      ApiQuery(fs, path, group: group, filters: filters ?? this.filters, orders: orders ?? this.orders,
          max: max ?? this.max);

  @override
  FirebaseFirestore get firestore => fs;

  @override
  Query<Map<String, dynamic>> where(Object field,
      {Object? isEqualTo,
      Object? isNotEqualTo,
      Object? isLessThan,
      Object? isLessThanOrEqualTo,
      Object? isGreaterThan,
      Object? isGreaterThanOrEqualTo,
      Object? arrayContains,
      Iterable<Object?>? arrayContainsAny,
      Iterable<Object?>? whereIn,
      Iterable<Object?>? whereNotIn,
      bool? isNull}) {
    final f = field.toString();
    final add = <List<Object?>>[
      if (isEqualTo != null) [f, '==', encodeValue(isEqualTo)],
      if (isNotEqualTo != null) [f, '!=', encodeValue(isNotEqualTo)],
      if (isLessThan != null) [f, '<', encodeValue(isLessThan)],
      if (isLessThanOrEqualTo != null) [f, '<=', encodeValue(isLessThanOrEqualTo)],
      if (isGreaterThan != null) [f, '>', encodeValue(isGreaterThan)],
      if (isGreaterThanOrEqualTo != null) [f, '>=', encodeValue(isGreaterThanOrEqualTo)],
      if (arrayContains != null) [f, 'array-contains', encodeValue(arrayContains)],
      if (whereIn != null) [f, 'in', encodeValue(whereIn.toList())],
      if (isNull != null) [f, isNull ? '==' : '!=', null],
    ];
    if (arrayContainsAny != null || whereNotIn != null) {
      throw UnimplementedError('ApiQuery: arrayContainsAny / whereNotIn');
    }
    return _copy(filters: [...filters, ...add]);
  }

  @override
  Query<Map<String, dynamic>> orderBy(Object field, {bool descending = false}) =>
      _copy(orders: [...orders, [field.toString(), descending ? 'desc' : 'asc']]);

  @override
  Query<Map<String, dynamic>> limit(int limit) => _copy(max: limit);

  Map<String, String> get _query => {
        'q': jsonEncode({
          if (filters.isNotEmpty) 'where': filters,
          if (orders.isNotEmpty) 'orderBy': orders,
          if (max != null) 'limit': max,
        })
      };

  Future<ApiQuerySnapshot> _fetch() async {
    final res = await fs.client.get(group ? '/group/$path' : '/col/$path', query: _query) as Map;
    return ApiQuerySnapshot([
      for (final d in res['docs'] as List) ApiDocSnapshot.fromJson(fs, d as Map),
    ]);
  }

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) => _fetch();

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots(
          {bool includeMetadataChanges = false, ListenSource source = ListenSource.defaultSource}) =>
      _liveStream<QuerySnapshot<Map<String, dynamic>>>(
          fs, _collectionName, _fetch, (s) => jsonEncode((s as ApiQuerySnapshot).raw));

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('ApiQuery: ${invocation.memberName}');
}

class ApiCollectionRef extends ApiQuery implements CollectionReference<Map<String, dynamic>> {
  ApiCollectionRef(super.fs, super.path);

  @override
  String get id => path.split('/').last;

  @override
  DocumentReference<Map<String, dynamic>>? get parent {
    final parts = path.split('/');
    return parts.length < 3 ? null : ApiDocRef(fs, parts.sublist(0, parts.length - 1).join('/'));
  }

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) => ApiDocRef(fs, '${this.path}/${path ?? autoId()}');

  @override
  Future<DocumentReference<Map<String, dynamic>>> add(Map<String, dynamic> data) async {
    final res = await fs.client.post('/col/$path', {'data': _encodeData(data)}) as Map;
    fs.live.local(id);
    return ApiDocRef(fs, '$path/${res['id']}');
  }
}

class ApiDocRef implements DocumentReference<Map<String, dynamic>> {
  ApiDocRef(this.fs, this.path);

  final ApiFirestore fs;
  @override
  final String path;

  @override
  FirebaseFirestore get firestore => fs;

  @override
  String get id => path.split('/').last;

  @override
  CollectionReference<Map<String, dynamic>> get parent =>
      ApiCollectionRef(fs, path.substring(0, path.lastIndexOf('/')));

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      ApiCollectionRef(fs, '$path/$collectionPath');

  Future<ApiDocSnapshot> _fetch() async {
    final res = await fs.client.get('/doc/$path') as Map;
    final d = res['doc'];
    return d == null ? ApiDocSnapshot(fs, path, null) : ApiDocSnapshot.fromJson(fs, d as Map);
  }

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) => _fetch();

  @override
  Stream<DocumentSnapshot<Map<String, dynamic>>> snapshots(
          {bool includeMetadataChanges = false, ListenSource source = ListenSource.defaultSource}) =>
      _liveStream<DocumentSnapshot<Map<String, dynamic>>>(
          fs, parent.id, _fetch, (s) => jsonEncode((s as ApiDocSnapshot).raw));

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    await fs.client.send('PUT', '/doc/$path', body: {'data': _encodeData(data), 'merge': options?.merge ?? false});
    fs.live.local(parent.id);
  }

  @override
  Future<void> update(Map<Object, Object?> data) async {
    await fs.client.send('PATCH', '/doc/$path', body: {'data': _encodeData(data)});
    fs.live.local(parent.id);
  }

  @override
  Future<void> delete() async {
    await fs.client.send('DELETE', '/doc/$path');
    fs.live.local(parent.id);
  }

  @override
  bool operator ==(Object other) => other is ApiDocRef && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('ApiDocRef: ${invocation.memberName}');
}

/// Hujjat (bo'lmasligi mumkin — `data()` null, Firestore'dagidek)
class ApiDocSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  ApiDocSnapshot(this.fs, this.path, this._data, {this.raw});

  static ApiQueryDocSnapshot fromJson(ApiFirestore fs, Map json) => ApiQueryDocSnapshot(
        fs,
        json['path'] as String,
        decodeValue(json['data']) as Map<String, dynamic>,
        raw: json,
      );

  final ApiFirestore fs;
  final String path;
  final Map<String, dynamic>? _data;

  /// Servis javobi (o'zgarish bormi — solishtirish uchun)
  final Object? raw;

  @override
  String get id => path.split('/').last;

  @override
  DocumentReference<Map<String, dynamic>> get reference => ApiDocRef(fs, path);

  @override
  bool get exists => _data != null;

  @override
  Map<String, dynamic>? data() => _data;

  @override
  dynamic get(Object field) => _data?[field.toString()];

  @override
  dynamic operator [](Object field) => get(field);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('ApiDocSnapshot: ${invocation.memberName}');
}

/// So'rov natijasidagi hujjat — har doim bor, `data()` null emas
class ApiQueryDocSnapshot extends ApiDocSnapshot implements QueryDocumentSnapshot<Map<String, dynamic>> {
  ApiQueryDocSnapshot(super.fs, super.path, Map<String, dynamic> super.data, {super.raw});

  @override
  Map<String, dynamic> data() => _data!;
}

class ApiQuerySnapshot implements QuerySnapshot<Map<String, dynamic>> {
  ApiQuerySnapshot(this.docs);

  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  List<Object?> get raw => [for (final d in docs) (d as ApiDocSnapshot).raw];

  @override
  int get size => docs.length;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('ApiQuerySnapshot: ${invocation.memberName}');
}

/// Bir nechta yozuv bitta tranzaksiyada (`/batch`)
class ApiBatch implements WriteBatch {
  ApiBatch(this.fs);

  final ApiFirestore fs;
  final ops = <Map<String, Object?>>[];

  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) => ops.add({
        'op': 'set',
        'path': document.path,
        'data': _encodeData(data as Map<Object?, Object?>),
        'merge': options?.merge ?? false,
      });

  @override
  void update(DocumentReference document, Map<String, dynamic> data) =>
      ops.add({'op': 'update', 'path': document.path, 'data': _encodeData(data)});

  @override
  void delete(DocumentReference document) => ops.add({'op': 'delete', 'path': document.path});

  @override
  Future<void> commit() async {
    if (ops.isEmpty) return;
    await fs.client.post('/batch', {'ops': ops});
    for (final name in {for (final o in ops) (o['path'] as String).split('/').reversed.elementAt(1)}) {
      fs.live.local(name);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('ApiBatch: ${invocation.memberName}');
}

/// Tranzaksiya: o'qish darhol, yozuvlar oxirida bitta batch bo'lib ketadi
class ApiTransaction implements Transaction {
  ApiTransaction(this.fs) : _batch = ApiBatch(fs);

  final ApiFirestore fs;
  final ApiBatch _batch;

  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(DocumentReference<T> documentReference) async =>
      documentReference.get();

  @override
  Transaction set<T>(DocumentReference<T> documentReference, T data, [SetOptions? options]) {
    _batch.set(documentReference, data, options);
    return this;
  }

  @override
  Transaction update(DocumentReference documentReference, Map<String, dynamic> data) {
    _batch.update(documentReference, data);
    return this;
  }

  @override
  Transaction delete(DocumentReference documentReference) {
    _batch.delete(documentReference);
    return this;
  }

  Future<void> commit() => _batch.commit();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('ApiTransaction: ${invocation.memberName}');
}
