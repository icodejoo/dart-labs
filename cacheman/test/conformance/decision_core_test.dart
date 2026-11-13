import 'package:cacheman/cacheman.dart';
import 'package:flutter_test/flutter_test.dart';

/// 共用逻辑键。
const _key = 'entry';

/// 第二个键兼作批量及过期条目。
const _other = 'other';

/// 命名空间隔离使用的作用域。
const _scope = 'account:%';

/// 命名空间转义后的契约值。
const _escapedScope = 'account%3A%25:';

/// 共用业务值。
const _value = 'Ada';

/// 共用默认值。
const _fallback = 'missing';

/// 测试寿命足够长，避免机器负载影响续期断言。
const _ttl = 600000;

/// 原始损坏内容，不应被 purge 删除。
const _corrupt = 'broken envelope';

/// codec 的确定性编码前缀。
const _prefix = 'encoded:';

/// 同一后端状态供同步和真正异步的测试原语使用。
class _Backend {
  /// 可直接注入外部数据的内存后端。
  final data = <String, Object?>{};

  /// 按调用顺序记录原语上下文。
  final calls = <CacheContext>[];

  /// 记录写入字符串，验证重试不重新编码。
  final attempts = <String>[];

  /// 各测试独有且可按身份比较的后端异常。
  final failure = StateError('backend failure');

  /// 写入过程中触发其他实例回调，模拟后端集成。
  void Function()? onSet;

  /// 待失败的写入次数。
  int failures = 0;

  /// 是否在读取时抛出原始异常。
  bool failRead = false;

  /// 是否在删除时抛出原始异常。
  bool failRemove = false;

  /// 是否在枚举时抛出原始异常。
  bool failScan = false;

  /// 同步读取；调用者负责决定是否跨异步边界。
  Object? get(CacheContext ctx, String key) {
    calls.add(ctx);
    if (failRead) throw failure;
    return data[key];
  }

  /// 同步更新内存或消耗一次写入失败预算。
  void set(CacheContext ctx, String key, String value) {
    calls.add(ctx);
    attempts.add(value);
    onSet?.call();
    if (failures > 0) {
      failures--;
      throw failure;
    }
    data[key] = value;
  }

  /// 同步删除，或注入删除失败。
  void remove(CacheContext ctx, String key) {
    calls.add(ctx);
    if (failRemove) throw failure;
    data.remove(key);
  }

  /// 返回后端的当前键列表。
  Iterable<String> keys(CacheContext ctx) {
    calls.add(ctx);
    if (failScan) throw failure;
    return data.keys;
  }

  /// 无需等待时间即可植入可识别的信封。
  void seed(String key,
      {Object? value = _value, int? remaining, int? ttl, bool marked = true}) {
    data[key] = defaultSerialize(CacheEntity(
      value: value,
      createdAt: marked ? 1 : null,
      expireAt: remaining == null
          ? null
          : DateTime.now().millisecondsSinceEpoch + remaining,
      ttl: ttl,
    ));
  }
}

/// 返回前完成内存变更，Future 仅代表后台完成的同步后端。
class _Sync extends Cacheman {
  /// 使用显式内存后端，不接触默认容器。
  _Sync(this.backend, CachemanOptions options) : super.custom(options: options);

  /// 本实例使用的内存数据及故障预算。
  final _Backend backend;

  /// 初始化只记录调用。
  @override
  Future<void> initRaw(CacheContext ctx) async => backend.calls.add(ctx);

  /// 返回当前原始数据。
  @override
  Object? getRaw(CacheContext ctx, String storageKey) =>
      backend.get(ctx, storageKey);

  /// 返回当前原始键列表。
  @override
  Iterable<String> keysRaw(CacheContext ctx) => backend.keys(ctx);

  /// 同步完成写入，前台异常同步抛出。
  @override
  Future<void> setRaw(CacheContext ctx, String storageKey, String value) {
    backend.set(ctx, storageKey, value);
    return Future<void>.value();
  }

  /// 同步完成删除。
  @override
  Future<void> removeRaw(CacheContext ctx, String storageKey) {
    backend.remove(ctx, storageKey);
    return Future<void>.value();
  }

  /// 原生整库清空，包含外部键。
  @override
  Future<void> clearRaw(CacheContext ctx) {
    backend.calls.add(ctx);
    backend.data.clear();
    return Future<void>.value();
  }
}

/// 每个原语都跨事件循环后才读写内存，验证外壳确实等待 IO。
class _Async extends AsyncCacheman {
  /// 使用相同后端协议和故障预算。
  _Async(this.backend, CachemanOptions options) : super(options: options);

  /// 本实例使用的内存数据及故障预算。
  final _Backend backend;

  /// 初始化跨异步边界后记录调用。
  @override
  Future<void> initRaw(CacheContext ctx) async {
    await Future<void>.delayed(Duration.zero);
    backend.calls.add(ctx);
  }

  /// 异步读取当前原始数据。
  @override
  Future<Object?> getRaw(CacheContext ctx, String storageKey) async {
    await Future<void>.delayed(Duration.zero);
    return backend.get(ctx, storageKey);
  }

  /// 异步枚举当前原始键。
  @override
  Future<Iterable<String>> keysRaw(CacheContext ctx) async {
    await Future<void>.delayed(Duration.zero);
    return backend.keys(ctx);
  }

  /// 异步完成写入或返回失败 Future。
  @override
  Future<void> setRaw(CacheContext ctx, String storageKey, String value) async {
    await Future<void>.delayed(Duration.zero);
    backend.set(ctx, storageKey, value);
  }

  /// 异步完成删除。
  @override
  Future<void> removeRaw(CacheContext ctx, String storageKey) async {
    await Future<void>.delayed(Duration.zero);
    backend.remove(ctx, storageKey);
  }

  /// 原生异步整库清空，包含外部键。
  @override
  Future<void> clearRaw(CacheContext ctx) async {
    await Future<void>.delayed(Duration.zero);
    backend.calls.add(ctx);
    backend.data.clear();
  }
}

/// 可拒绝解码的确定性 codec，供键和值编码共用。
class _Codec implements Codec {
  /// 指定是否返回 null 解码结果。
  const _Codec({this.reject = false});

  /// null 解码模拟损坏值。
  final bool reject;

  /// 为原始字符串加可逆前缀。
  @override
  String encode(String value) => '$_prefix$value';

  /// 只接受本 codec 编码的值。
  @override
  String? decode(String value) => !reject && value.startsWith(_prefix)
      ? value.substring(_prefix.length)
      : null;
}

/// 统一测试入口，仅测试代码用 dynamic 适配两种返回协议。
Future<dynamic> _ready(bool asynchronous, _Backend backend,
    [CachemanOptions options = const CachemanOptions()]) async {
  final dynamic cache =
      asynchronous ? _Async(backend, options) : _Sync(backend, options);
  await cache.ensureInitialized();
  backend.calls.clear();
  return cache;
}

/// 统一测试中的同步 getter 与异步方法。
Future<int> _length(dynamic cache) async =>
    cache is Cacheman ? cache.length : await cache.length() as int;

/// 同一批场景逐一运行在两个真实外壳上。
void main() {
  for (final asynchronous in [false, true]) {
    group('decision conformance (async=$asynchronous)', () {
      late _Backend backend;
      late List<Object> errors;

      setUp(() {
        backend = _Backend();
        errors = [];
      });

      test('fresh reads, absence, foreign values and typed writes', () async {
        final cache = await _ready(asynchronous, backend);
        expect(await cache.read<String>(_key, _fallback), _fallback);
        backend.data[_key] = 42;
        expect(await cache.read<String>(_key, _fallback), _fallback);
        expect(backend.data[_key], 42);
        await cache.write(_key, _value);
        expect(await cache.read<String>(_key), _value);
        backend.seed(_key, value: _fallback);
        expect(await cache.read<String>(_key), _fallback);
        expect(backend.calls.where((c) => c.op == CacheOp.read).length, 4);
      });

      test('expiry lazily removes only marked data', () async {
        final cache = await _ready(asynchronous, backend);
        backend.seed(_key, remaining: -_ttl);
        expect(await _length(cache), 1);
        expect(await cache.read<String>(_key, _fallback), _fallback);
        expect(backend.data, isEmpty);
        backend.seed(_key, remaining: -_ttl, marked: false);
        expect(await cache.read<String>(_key), _value);
        expect(backend.data, contains(_key));
      });

      test('sliding renews once and preserves envelope metadata', () async {
        final cache = await _ready(
            asynchronous, backend, const CachemanOptions(sliding: true));
        backend.seed(_key, remaining: _ttl ~/ 2, ttl: _ttl);
        final before = defaultDeserialize(backend.data[_key] as String);
        expect(await cache.read<String>(_key), _value);
        final after = defaultDeserialize(backend.data[_key] as String);
        expect(after.expireAt, greaterThan(before.expireAt!));
        expect(after.createdAt, before.createdAt);
        expect(after.ttl, before.ttl);
        expect(await cache.read<String>(_key), _value);
        expect(backend.attempts, hasLength(1));
      });

      test('renewal failure returns original value and retains encoding',
          () async {
        final cache = await _ready(asynchronous, backend,
            CachemanOptions(sliding: true, onError: (_, e) => errors.add(e)));
        backend.seed(_key, remaining: _ttl ~/ 2, ttl: _ttl);
        final original = backend.data[_key];
        backend.failures = 2;
        expect(await cache.read<String>(_key), _value);
        expect(backend.data[_key], original);
        expect(backend.attempts, hasLength(2));
        expect(backend.attempts.first, backend.attempts.last);
        expect((errors.single as WriteError).cause, same(backend.failure));
      });

      test('decode failure deletes before reporting original error and trace',
          () async {
        final failure = FormatException(_corrupt);
        final cache = await _ready(
            asynchronous,
            backend,
            CachemanOptions(
              namespace: _scope,
              deserialize: (_) => throw failure,
              onError: (key, error) {
                expect(key, '$_escapedScope$_key');
                expect(backend.data, isEmpty);
                errors.add(error);
              },
            ));
        backend.data[cache.storageKey(_key) as String] = _corrupt;
        expect(await cache.read<String>(_key, _fallback), _fallback);
        final error = errors.single as CorruptEntryError;
        expect(error.cause, same(failure));
        expect(error.stackTrace, isNotNull);
        expect(error.dropped, isTrue);
      });

      test('null codec decode reports a format error after removal', () async {
        final cache = await _ready(
            asynchronous,
            backend,
            CachemanOptions(
              codeable: true,
              codec: const _Codec(reject: true),
              onError: (_, e) => errors.add(e),
            ));
        backend.data[_key] = _corrupt;
        expect(await cache.read<String>(_key, _fallback), _fallback);
        expect(backend.data, isEmpty);
        expect(
            (errors.single as CorruptEntryError).cause, isA<FormatException>());
      });

      test('type mismatch returns fallback and keeps data', () async {
        final cache = await _ready(asynchronous, backend,
            CachemanOptions(onError: (_, e) => errors.add(e)));
        await cache.write(_key, 42);
        final original = backend.data[_key];
        expect(await cache.read<String>(_key, _fallback), _fallback);
        expect(backend.data[_key], original);
        expect(errors.single, isA<TypeMismatchError>());
        expect(await cache.read<num>(_key), 42);
      });

      test('adapter conversion follows renewal IO even on type failure',
          () async {
        final cache = await _ready(asynchronous, backend,
            CachemanOptions(sliding: true, onError: (_, e) => errors.add(e)));
        backend.seed(_key, remaining: _ttl ~/ 2, ttl: _ttl);
        final adapter = ValueAdapter<String>(
          toJson: (v) => v,
          fromJson: (_) {
            expect(backend.attempts, hasLength(1));
            throw StateError(_key);
          },
        );
        expect(
            await cache.readWith<String>(_key,
                defaultValue: _fallback, adapter: adapter),
            _fallback);
        expect(errors.single, isA<TypeMismatchError>());
        expect(backend.data, contains(_key));
      });

      test('adapters roundtrip before serialization', () async {
        final cache = await _ready(asynchronous, backend);
        final adapter = ValueAdapter<String>(
          toJson: (value) => {_key: value},
          fromJson: (json) => (json as Map)[_key] as String,
        );
        await cache.write<String>(_key, _value, adapter: adapter);
        expect(await cache.readWith<String>(_key, adapter: adapter), _value);
      });

      test('raw bypasses codec, adapter, expiry and purge IO', () async {
        final cache = await _ready(
            asynchronous,
            backend,
            CachemanOptions(
              raw: true,
              sliding: true,
              codeable: true,
              codec: const _Codec(reject: true),
              serialize: (_) => throw StateError(_key),
              deserialize: (_) => throw StateError(_key),
            ));
        final adapter = ValueAdapter<String>(
          toJson: (_) => throw StateError(_key),
          fromJson: (_) => throw StateError(_key),
        );
        await cache.write(_key, _value, ttl: -1, expireAt: 1, adapter: adapter);
        expect(backend.data[_key], _value);
        expect(await cache.readWith<String>(_key, adapter: adapter), _value);
        await cache.write(_other, 42);
        expect(backend.data, isNot(contains(_other)));
        backend.calls.clear();
        await cache.purge();
        expect(backend.calls, isEmpty);
      });

      test('raw type mismatch preserves the string', () async {
        final cache = await _ready(asynchronous, backend,
            CachemanOptions(raw: true, onError: (_, e) => errors.add(e)));
        await cache.write(_key, _value);
        expect(await cache.read<int>(_key, 42), 42);
        expect(backend.data[_key], _value);
        expect(errors.single, isA<TypeMismatchError>());
      });

      test('readonly protects null and alive values without renewal', () async {
        final cache = await _ready(asynchronous, backend,
            const CachemanOptions(readonly: true, sliding: true));
        for (final value in [null, _value]) {
          backend.seed(_key, value: value, remaining: _ttl ~/ 2, ttl: _ttl);
          final original = backend.data[_key];
          await cache.write(_key, _fallback);
          expect(backend.data[_key], original);
        }
        expect(backend.attempts, isEmpty);
        expect(backend.calls.every((c) => c.op == CacheOp.read), isTrue);
      });

      test('readonly overwrites expired and corrupt data quietly', () async {
        final cache = await _ready(asynchronous, backend,
            CachemanOptions(readonly: true, onError: (_, e) => errors.add(e)));
        backend.seed(_key, remaining: -_ttl);
        await cache.write(_key, _value);
        backend.data[_key] = _corrupt;
        await cache.write(_key, _fallback);
        expect(await cache.read<String>(_key), _fallback);
        expect(errors, isEmpty);
        expect(backend.calls.where((c) => c.op == CacheOp.remove), isEmpty);
      });

      test('raw readonly keeps an existing empty string', () async {
        final cache = await _ready(asynchronous, backend,
            const CachemanOptions(raw: true, readonly: true));
        backend.data[_key] = '';
        await cache.write(_key, _value);
        expect(backend.data[_key], isEmpty);
        expect(backend.attempts, isEmpty);
      });

      test('force purges then retries the exact encoding once', () async {
        var encodes = 0;
        final cache = await _ready(
            asynchronous,
            backend,
            CachemanOptions(
              serialize: (entity) {
                encodes++;
                return defaultSerialize(entity);
              },
              onError: (_, e) => errors.add(e),
            ));
        backend.seed(_other, remaining: -_ttl);
        backend.failures = 1;
        await cache.write(_key, _value);
        expect(encodes, 1);
        expect(backend.attempts, hasLength(2));
        expect(backend.attempts.first, backend.attempts.last);
        expect(backend.data.keys, [_key]);
        expect(backend.calls.map((c) => c.op), [
          CacheOp.write,
          CacheOp.keys,
          CacheOp.read,
          CacheOp.remove,
          CacheOp.write,
        ]);
        expect(errors, isEmpty);
      });

      test('force exhaustion reports once with storage key and original cause',
          () async {
        final cache = await _ready(
            asynchronous,
            backend,
            CachemanOptions(
              namespace: _scope,
              onError: (key, e) {
                expect(key, (e as CachemanError).key);
                errors.add(e);
              },
            ));
        backend.failures = 2;
        await cache.write(_key, _value);
        final error = errors.single as WriteError;
        expect(error.key, cache.storageKey(_key));
        expect(error.cause, same(backend.failure));
        expect(error.stackTrace, isNotNull);
        expect(backend.attempts, hasLength(2));
      });

      test('force false never scans or retries', () async {
        final cache = await _ready(asynchronous, backend,
            CachemanOptions(force: false, onError: (_, e) => errors.add(e)));
        backend.failures = 2;
        await cache.write(_key, _value);
        expect(backend.attempts, hasLength(1));
        expect(backend.calls.single.op, CacheOp.write);
        expect(errors.single, isA<WriteError>());
      });

      test('failed force scan is the final write error', () async {
        final cache = await _ready(asynchronous, backend,
            CachemanOptions(onError: (_, e) => errors.add(e)));
        backend.failures = 1;
        backend.failScan = true;
        await cache.write(_key, _value);
        expect(backend.attempts, hasLength(1));
        expect((errors.single as WriteError).cause, same(backend.failure));
      });

      test('encoding failure never calls backend or force purge', () async {
        final failure = StateError(_corrupt);
        var encodes = 0;
        final cache = await _ready(
            asynchronous,
            backend,
            CachemanOptions(
              serialize: (_) {
                encodes++;
                throw failure;
              },
              onError: (_, e) => errors.add(e),
            ));
        await cache.write(_key, _value);
        expect(encodes, 1);
        expect(backend.calls, isEmpty);
        expect((errors.single as SerializeError).cause, same(failure));
      });

      test('backend read and deletion exceptions propagate without reports',
          () async {
        final cache = await _ready(asynchronous, backend,
            CachemanOptions(onError: (_, e) => errors.add(e)));
        backend.failRead = true;
        await expectLater(Future<dynamic>(() => cache.read<String>(_key)),
            throwsA(same(backend.failure)));
        backend.failRead = false;
        backend.failRemove = true;
        backend.data[_key] = _corrupt;
        await expectLater(Future<dynamic>(() => cache.read<String>(_key)),
            throwsA(same(backend.failure)));
        expect(backend.data[_key], _corrupt);
        expect(errors, isEmpty);
      });

      test('throwing onError escapes once for decode, type and writes',
          () async {
        final handlerFailure = StateError(_fallback);
        final cache = await _ready(asynchronous, backend, CachemanOptions(
          onError: (_, error) {
            errors.add(error);
            throw handlerFailure;
          },
        ));
        backend.data[_key] = _corrupt;
        await expectLater(Future<dynamic>(() => cache.read<String>(_key)),
            throwsA(same(handlerFailure)));
        expect(backend.data, isEmpty);
        backend.seed(_key, value: 42);
        await expectLater(Future<dynamic>(() => cache.read<String>(_key)),
            throwsA(same(handlerFailure)));
        expect(backend.data, contains(_key));
        backend.failures = 2;
        await expectLater(Future<dynamic>(() => cache.write(_other, _value)),
            throwsA(same(handlerFailure)));
        expect(errors.map((e) => e.runtimeType), [
          CorruptEntryError,
          TypeMismatchError,
          WriteError,
        ]);
      });

      test('backend-triggered peer onError propagates without write retry',
          () async {
        final handlerFailure = StateError(_fallback);
        final peerBackend = _Backend();
        final peer = _Sync(peerBackend, CachemanOptions(onError: (_, error) {
          errors.add(error);
          throw handlerFailure;
        }));
        await peer.ensureInitialized();
        peerBackend.seed(_key);
        final cache = await _ready(asynchronous, backend,
            CachemanOptions(onError: (_, e) => errors.add(e)));
        backend.onSet = () => peer.read<int>(_key);
        await expectLater(Future<dynamic>(() => cache.write(_key, _value)),
            throwsA(same(handlerFailure)));
        expect(errors.single, isA<TypeMismatchError>());
        expect(backend.attempts, hasLength(1));
        expect(backend.calls.single.op, CacheOp.write);
      });

      test('batches keep order, positional defaults and short values',
          () async {
        final cache = await _ready(asynchronous, backend);
        expect(await cache.readAll([_key, _other], [_fallback]),
            [_fallback, null]);
        backend.calls.clear();
        await cache.writeAll([_key, _other], [_value], ttl: _ttl);
        expect(backend.data.keys, [_key]);
        expect(defaultDeserialize(backend.data[_key] as String).ttl, _ttl);
        await cache.writeAll([_key, _other], [_value, _fallback, 42]);
        expect(await cache.readAll([_other, _key]), [_fallback, _value]);
        backend.calls.clear();
        await cache.removeAll([_other, _key]);
        expect(backend.calls.map((c) => c.storageKey), [_other, _key]);
        expect(backend.data, isEmpty);
      });

      test('namespace, keys, length and scoped erase isolate foreign entries',
          () async {
        final cache = await _ready(
            asynchronous, backend, const CachemanOptions(namespace: _scope));
        expect(cache.namespace, _escapedScope);
        backend.data[_key] = _corrupt;
        await cache.writeAll([_key, _other], [_value, _fallback]);
        expect(await cache.keys(), [_key, _other]);
        expect(await _length(cache), 2);
        await cache.setNamespace(_other);
        expect(await cache.keys(), isEmpty);
        await cache.write(_key, _fallback);
        await cache.erase();
        expect(backend.data, hasLength(3));
        await cache.setNamespace(_scope);
        await cache.erase();
        expect(backend.data, {_key: _corrupt});
      });

      test('unscoped erase delegates to whole backend clear', () async {
        final cache = await _ready(asynchronous, backend);
        backend.data[_key] = 42;
        backend.data[_other] = _corrupt;
        expect(await _length(cache), 2);
        backend.calls.clear();
        await cache.erase();
        expect(backend.data, isEmpty);
        expect(backend.calls.single.op, CacheOp.clear);
        expect(backend.calls.single.key, isNull);
      });

      test('encoded keys and values roundtrip; erase preserves foreign keys',
          () async {
        final cache = await _ready(
            asynchronous,
            backend,
            const CachemanOptions(
                enckey: true, codeable: true, codec: _Codec()));
        backend.data[_other] = _corrupt;
        await cache.write(_key, _value);
        expect(backend.data[cache.storageKey(_key)], startsWith(_prefix));
        expect(await cache.read<String>(_key), _value);
        expect(await cache.keys(), [_key]);
        expect(await _length(cache), 1);
        await cache.erase();
        expect(backend.data, {_other: _corrupt});
      });

      test('purge deletes only owned marked expired envelopes quietly',
          () async {
        final cache = await _ready(
            asynchronous,
            backend,
            CachemanOptions(
              namespace: _scope,
              onError: (_, e) => errors.add(e),
            ));
        final owned = cache.storageKey(_key) as String;
        backend.seed(owned, remaining: -_ttl);
        backend.seed(_key, remaining: -_ttl);
        final unmarked = cache.storageKey(_other) as String;
        backend.seed(unmarked, remaining: -_ttl, marked: false);
        final damaged = cache.storageKey(_corrupt) as String;
        backend.data[damaged] = _corrupt;
        await cache.purge();
        expect(backend.data.keys, [_key, unmarked, damaged]);
        expect(await _length(cache), 2);
        expect(errors, isEmpty);
      });

      test('purgeOnInit preserves the documented facade timing', () async {
        backend.seed(_key, remaining: -_ttl);
        final cache = await _ready(
            asynchronous, backend, const CachemanOptions(purgeOnInit: true));
        expect(backend.data, contains(_key));
        await Future<void>.delayed(Duration.zero);
        expect(backend.data.containsKey(_key), asynchronous);
        await cache.purge();
        expect(backend.data, isEmpty);
      });

      test(
          'renewal encoding failure retains the original value without write IO',
          () async {
        final failure = StateError(_corrupt);
        final cache = await _ready(
            asynchronous,
            backend,
            CachemanOptions(
              sliding: true,
              serialize: (_) => throw failure,
              onError: (_, e) => errors.add(e),
            ));
        backend.seed(_key, remaining: _ttl ~/ 2, ttl: _ttl);
        final original = backend.data[_key];
        expect(await cache.read<String>(_key), _value);
        expect(backend.data[_key], original);
        expect(backend.calls.single.op, CacheOp.read);
        expect((errors.single as SerializeError).cause, same(failure));
      });

      test('absolute expiry and invalid parameters keep existing write rules',
          () async {
        final cache = await _ready(asynchronous, backend);
        final future = DateTime.now().add(const Duration(days: 1));
        for (final expiry in [future, future.millisecondsSinceEpoch]) {
          await cache.write(_key, _value, expireAt: expiry, ttl: _ttl);
          expect(defaultDeserialize(backend.data[_key] as String).expireAt,
              future.millisecondsSinceEpoch);
        }
        final original = backend.data[_key];
        await cache.write(_key, _fallback, expireAt: 1);
        await cache.write(_key, _fallback, expireAt: _corrupt);
        expect(backend.data[_key], original);
        await cache.write(_key, _value, ttl: -1);
        final noExpiry = defaultDeserialize(backend.data[_key] as String);
        expect(noExpiry.ttl, isNull);
        expect(noExpiry.expireAt, isNull);
      });

      test('raw force retries without any purge IO', () async {
        final cache = await _ready(
            asynchronous, backend, const CachemanOptions(raw: true));
        backend.failures = 1;
        await cache.write(_key, _value);
        expect(backend.data[_key], _value);
        expect(backend.attempts, [_value, _value]);
        expect(backend.calls.map((c) => c.op), [CacheOp.write, CacheOp.write]);
      });

      test('batch duplicate keys respect readonly in original order', () async {
        final cache = await _ready(
            asynchronous, backend, const CachemanOptions(readonly: true));
        await cache.writeAll([_key, _key], [_value, _fallback]);
        expect(await cache.readAll([_key, _key]), [_value, _value]);
        expect(backend.attempts, hasLength(1));
      });

      test('batch IO failure stops before the next item', () async {
        final cache = await _ready(asynchronous, backend);
        backend.failRead = true;
        await expectLater(Future<dynamic>(() => cache.readAll([_key, _other])),
            throwsA(same(backend.failure)));
        expect(backend.calls.single.storageKey, _key);
        backend.calls.clear();
        backend.failRemove = true;
        await expectLater(
            Future<dynamic>(() => cache.removeAll([_key, _other])),
            throwsA(same(backend.failure)));
        expect(backend.calls.single.storageKey, _key);
      });

      test('return timing follows the facade IO contract', () async {
        final cache = await _ready(asynchronous, backend);
        final dynamic pending = cache.write(_key, _value);
        if (asynchronous) {
          expect(pending, isA<Future<void>>());
          expect(backend.data, isEmpty);
          await pending;
        } else {
          expect(pending, isNull);
          expect(backend.data, contains(_key));
        }
        expect(await cache.read<String>(_key), _value);
      });

      test('initialization assertion precedes encoding and write IO', () async {
        var encodes = 0;
        final options = CachemanOptions(serialize: (entity) {
          encodes++;
          return defaultSerialize(entity);
        });
        final dynamic cache =
            asynchronous ? _Async(backend, options) : _Sync(backend, options);
        await expectLater(Future<dynamic>(() => cache.write(_key, _value)),
            throwsAssertionError);
        expect(encodes, 0);
        expect(backend.calls, isEmpty);
        await cache.ensureInitialized();
        await cache.write(_key, _value);
        expect(encodes, 1);
      });
    });
  }
}
