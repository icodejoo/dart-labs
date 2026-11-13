import 'dart:async';
import 'dart:convert' show base64Encode, base64Decode, utf8;

import 'package:cacheman/cacheman.dart';
import 'package:flutter_test/flutter_test.dart';

/// Error matcher label. / 错误断言标签。
const _causeLabel = 'cause';

const _key = 'entry';
const _other = 'other';
const _value = 'value';
const _fallback = 'fallback';
const _ns = 'a';
const _nestedNs = 'a:b';
const _ttl = 100000;

/// Map backend with awaited/synchronous failure injection, local to tests.
/// 测试内部的 Map 后端，支持注入 awaited/同步异常。
class _MemoryAsync extends AsyncCacheman {
  _MemoryAsync({super.options, Map<String, Object?>? data}) : data = data ?? {};

  /// Shared raw backend. / 可共享的原始后端。
  final Map<String, Object?> data;

  /// Primitive calls for routing assertions. / 用于验证路由的原语调用记录。
  final calls = <CacheContext>[];

  /// Attempts and failure budget. / 尝试次数与失败次数预算。
  int writes = 0;
  int failures = 0;

  /// Throw before returning a Future when enabled. / 启用时在返回 Future 前抛错。
  bool throwSynchronously = false;

  /// Original injected failure. / 注入的原始异常。
  final failure = StateError('write failed');

  /// Optional persistence gate proving callers await writes. / 证明等待写入的可选闸门。
  Completer<void>? gate;

  @override
  Future<void> initRaw(CacheContext ctx) async {
    calls.add(ctx);
    await super.initRaw(ctx);
  }

  @override
  Future<Object?> getRaw(CacheContext ctx, String storageKey) async {
    calls.add(ctx);
    return data[storageKey];
  }

  @override
  Future<void> setRaw(CacheContext ctx, String storageKey, String value) {
    calls.add(ctx);
    writes++;
    if (failures > 0) {
      failures--;
      if (throwSynchronously) throw failure;
      return Future<void>.error(failure);
    }
    return Future<void>(() async {
      await gate?.future;
      data[storageKey] = value;
    });
  }

  @override
  Future<void> removeRaw(CacheContext ctx, String storageKey) async {
    calls.add(ctx);
    data.remove(storageKey);
  }

  @override
  Future<Iterable<String>> keysRaw(CacheContext ctx) async {
    calls.add(ctx);
    return data.keys;
  }

  /// Seeds a marked/unmarked envelope without sleeping. / 无需等待即可植入带/不带标记的信封。
  Future<void> seed(String key,
      {int remaining = -1, bool marked = true, int? ttl}) async {
    data[storageKey(key)] = defaultSerialize(CacheEntity(
      value: _value,
      createdAt: marked ? 1 : null,
      expireAt: DateTime.now().millisecondsSinceEpoch + remaining,
      ttl: ttl,
    ));
  }
}

/// Overrides whole-backend clear to verify dispatch and context.
/// 覆写整库清空以验证原语分派和上下文。
class _NativeClear extends _MemoryAsync {
  @override
  Future<void> clearRaw(CacheContext ctx) async {
    calls.add(ctx);
    data.clear();
  }
}

/// Simulates a failed backend scan during a force renewal retry.
/// 模拟 force 续期重试期间后端扫描失败。
class _FailedScan extends _MemoryAsync {
  _FailedScan({super.options});

  @override
  Future<Iterable<String>> keysRaw(CacheContext ctx) =>
      Future.error(StateError('scan failed'));
}

/// Reversible key/value codec, including null/throwing decode modes.
/// 可逆键/值 codec，含 null/抛错解码模式。
class _Codec implements Codec {
  const _Codec({this.reject = false, this.failure});

  /// Null decode mode. / null 解码模式。
  final bool reject;

  /// Original thrown decode error. / 解码时抛出的原始异常。
  final Object? failure;

  @override
  String encode(String value) => base64Encode(utf8.encode(value));

  @override
  String? decode(String value) {
    if (failure != null) throw failure!;
    if (reject) return null;
    try {
      return utf8.decode(base64Decode(value));
    } catch (_) {
      return null;
    }
  }
}

/// Initializes a fresh or shared test backend. / 初始化独立或共享的测试后端。
Future<_MemoryAsync> _ready(
    [CachemanOptions options = const CachemanOptions(),
    Map<String, Object?>? data]) async {
  final cache = _MemoryAsync(options: options, data: data);
  await cache.ensureInitialized();
  return cache;
}

void main() {
  test('initialization is explicit and forwards context', () async {
    final cache = _MemoryAsync();
    await expectLater(cache.write(_key, _value), throwsAssertionError);
    await cache.ensureInitialized();
    expect(cache.calls.single.op, CacheOp.init);
    expect(cache.calls.single.key, isNull);
    await cache.write(_key, _value);
    expect(await cache.read<String>(_key), _value);
  });

  test('read/write await persistence and read fresh data every time', () async {
    final cache = await _ready();
    cache.gate = Completer<void>();
    final pending = cache.write(_key, {
      'nested': [1, 2]
    });
    await Future<void>.delayed(Duration.zero);
    expect(cache.data, isEmpty);
    cache.gate!.complete();
    await pending;
    expect(await cache.read<Map<String, dynamic>>(_key), {
      'nested': [1, 2]
    });
    cache.data.clear();
    expect(await cache.read<String>(_key, _fallback), _fallback);
    cache.data[_key] = 42;
    expect(await cache.read<String>(_key, _fallback), _fallback);
  });

  test('ttl expires and lazy read physically deletes the key', () async {
    final cache = await _ready();
    await cache.write(_key, _value, ttl: 20);
    expect(await cache.read<String>(_key), _value);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(await cache.length(), 1);
    expect(await cache.read<String>(_key, _fallback), _fallback);
    expect(cache.data, isEmpty);
  });

  test(
      'expireAt accepts DateTime/int, rejects past/invalid; invalid ttl ignored',
      () async {
    final cache = await _ready();
    final expiry = DateTime.now().add(const Duration(days: 1));
    for (final input in <Object>[expiry, expiry.millisecondsSinceEpoch]) {
      await cache.write(_key, _value, expireAt: input);
      expect(defaultDeserialize(cache.data[_key] as String).expireAt,
          expiry.millisecondsSinceEpoch);
    }
    await cache.erase();
    for (final input in <Object>[1, _value]) {
      await cache.write(_key, _value, expireAt: input);
      expect(await cache.keys(), isEmpty);
    }
    await cache.write(_key, _value, ttl: 0);
    expect(defaultDeserialize(cache.data[_key] as String).expireAt, isNull);
  });

  test('sliding plus ttl restarts a past absolute expiry', () async {
    final cache = await _ready(const CachemanOptions(sliding: true));
    await cache.write(_key, _value, ttl: _ttl, expireAt: 1);
    final entity = defaultDeserialize(cache.data[_key] as String);
    expect(entity.expireAt, entity.createdAt! + _ttl);
  });

  test('sliding skips above 90 percent and renews at inclusive boundary',
      () async {
    // Compute the envelope at deserialization so the boundary cannot expire
    // during an awaited backend read. / 在反序列化时构造，避免异步读取耗时影响阈值。
    for (final offset in [1000, 0, -1]) {
      final cache = await _ready(CachemanOptions(
        sliding: true,
        deserialize: (_) => CacheEntity(
          value: _value,
          createdAt: 1,
          ttl: _ttl,
          expireAt: DateTime.now().millisecondsSinceEpoch + 90000 + offset,
        ),
      ));
      cache.data[_key] = _value;
      expect(await cache.read<String>(_key), _value);
      expect(cache.writes, offset > 0 ? 0 : 1);
      if (offset <= 0) {
        final renewed = defaultDeserialize(cache.data[_key] as String);
        expect(renewed.createdAt, 1);
        expect(renewed.ttl, _ttl);
      }
    }
  });

  test(
      'renewal failure reports without throwing from read or changing envelope',
      () async {
    final errors = <Object>[];
    final cache = await _ready(
        CachemanOptions(sliding: true, onError: (_, e) => errors.add(e)));
    await cache.seed(_key, remaining: 50000, ttl: _ttl);
    final before = cache.data[_key];
    cache.failures = 2;
    expect(await cache.read<String>(_key), _value);
    expect(cache.writes, 2);
    expect(
        errors.single,
        isA<WriteError>()
            .having((e) => e.cause, _causeLabel, same(cache.failure)));
    expect(cache.data[_key], before);
  });

  test('namespace escaping, isolation, scope switching and scoped erase',
      () async {
    final data = <String, Object?>{};
    final a = await _ready(const CachemanOptions(namespace: _ns), data);
    final b = await _ready(const CachemanOptions(namespace: _nestedNs), data);
    await a.write('b:$_key', 1);
    await b.write(_key, 2);
    expect(await a.read<int>('b:$_key'), 1);
    expect(await b.read<int>(_key), 2);
    expect(b.namespace, 'a%3Ab:');
    await a.erase();
    expect(await b.read<int>(_key), 2);
    await a.setNamespace(_nestedNs);
    expect(await a.keys(), [_key]);
    await a.setNamespace('50%');
    expect(a.namespace, '50%25:');
    await a.setNamespace();
    expect(await a.keys(), ['${b.namespace}$_key']);
  });

  test(
      'enckey and codeable roundtrip separately; fresh enumeration sees external writes',
      () async {
    const codec = _Codec();
    final cache = await _ready(const CachemanOptions(
        namespace: _ns,
        enckey: true,
        keyCodec: codec,
        codeable: true,
        codec: codec));
    await cache.write(_key, _value);
    final sk = cache.storageKey(_key);
    expect(sk, isNot(contains(_key)));
    expect(cache.data[sk], isNot(contains(_value)));
    expect(await cache.read<String>(_key), _value);
    expect(await cache.keys(), [_key]);
    cache.data[cache.storageKey(_other)] = cache.data[sk];
    cache.data['foreign'] = _value;
    expect(await cache.length(), 2);
    expect(await cache.keys(), [_key, _other]);
    await cache.setNamespace();
    expect(await cache.keys(), ['$_ns:$_key', '$_ns:$_other']);
    await cache
        .erase(); // enckey without namespace remains scoped, just like Cacheman.
    expect(cache.data, {'foreign': _value});
  });

  test('missing codecs degrade to plain keys and values', () async {
    final cache =
        await _ready(const CachemanOptions(enckey: true, codeable: true));
    await cache.write(_key, _value);
    expect(cache.storageKey(_key), _key);
    expect(await cache.read<String>(_key), _value);
  });

  test('raw rejects non-String, bypasses codec/serialization/expiry and purge',
      () async {
    final cache = await _ready(CachemanOptions(
      raw: true,
      codeable: true,
      codec: _Codec(failure: StateError('do not decode')),
      serialize: (_) => throw StateError('do not serialize'),
      deserialize: (_) => throw StateError('do not deserialize'),
    ));
    await cache.write(_key, 42);
    expect(cache.data, isEmpty);
    const lookalike = '{"value":1,"expireAt":1,"createdAt":1}';
    await cache.write(_key, lookalike, ttl: 1, expireAt: 1);
    await cache.purge();
    expect(await cache.read<String>(_key), lookalike);
  });

  test(
      'readonly counts null, does not renew/report, allows expired replacement',
      () async {
    final errors = <Object>[];
    final cache = await _ready(CachemanOptions(
        readonly: true, sliding: true, onError: (_, e) => errors.add(e)));
    await cache.write<Object?>(_key, null);
    await cache.write(_key, _value);
    expect(await cache.read<Object?>(_key), isNull);
    await cache.seed(_key, remaining: 50000, ttl: _ttl);
    final before = cache.data[_key];
    final writes = cache.writes;
    await cache.write(_key, _fallback);
    expect(cache.data[_key], before);
    expect(cache.writes, writes);
    await cache.seed(_key);
    await cache.write(_key, _fallback);
    expect(await cache.read<String>(_key), _fallback);
    cache.data[_key] = 'invalid envelope';
    await cache.write(_key, _value);
    expect(errors, isEmpty);
  });

  for (final synchronous in [false, true]) {
    test('force purges then retries once (synchronous=$synchronous)', () async {
      final cache = await _ready();
      await cache.seed(_other);
      cache.failures = 1;
      cache.throwSynchronously = synchronous;
      await cache.write(_key, _value);
      expect(cache.writes, 2);
      expect(await cache.read<String>(_key), _value);
      expect(cache.data.containsKey(_other), isFalse);
      final removal = cache.calls.indexWhere((c) => c.op == CacheOp.remove);
      final writes = cache.calls.indexed
          .where((e) => e.$2.op == CacheOp.write)
          .map((e) => e.$1)
          .toList();
      expect(removal, greaterThan(writes.first));
      expect(removal, lessThan(writes.last));
    });
  }

  test(
      'two failures report final error with storage key, force false never retries',
      () async {
    for (final force in [true, false]) {
      final errors = <(String, Object)>[];
      final cache = await _ready(CachemanOptions(
          namespace: _ns, force: force, onError: (k, e) => errors.add((k, e))));
      cache.failures = 2;
      await cache.write(_key, _value);
      expect(cache.writes, force ? 2 : 1);
      expect(errors.single.$1, '$_ns:$_key');
      expect(
          errors.single.$2,
          isA<WriteError>()
              .having((e) => e.cause, _causeLabel, same(cache.failure)));
    }
  });

  test('serialize errors never retry and preserve the original exception',
      () async {
    var count = 0;
    final failure = StateError('serialize');
    final cache = await _ready(CachemanOptions(serialize: (e) {
      if (count++ == 0) throw failure;
      return defaultSerialize(e);
    }));
    await cache.write(_key, _value);
    expect(count, 1);
    expect(await cache.read<String>(_key), isNull);
    final errors = <Object>[];
    final broken = await _ready(CachemanOptions(
        serialize: (_) => throw failure, onError: (_, e) => errors.add(e)));
    await broken.write(_key, _value);
    expect(
        errors.single,
        isA<SerializeError>()
            .having((e) => e.cause, _causeLabel, same(failure)));
  });

  test(
      'decode null/throw/deserialize failures delete then report once; probes stay quiet',
      () async {
    final original = FormatException('bad envelope');
    final options = [
      const CachemanOptions(codeable: true, codec: _Codec(reject: true)),
      CachemanOptions(codeable: true, codec: _Codec(failure: original)),
      CachemanOptions(deserialize: (_) => throw original),
    ];
    for (var i = 0; i < options.length; i++) {
      final errors = <Object>[];
      late _MemoryAsync cache;
      final option = options[i];
      cache = await _ready(CachemanOptions(
        codeable: option.codeable,
        codec: option.codec,
        deserialize: option.deserialize,
        onError: (k, e) {
          expect(k, _key);
          expect(cache.data.containsKey(k), isFalse);
          errors.add(e);
        },
      ));
      cache.data[_key] = _value;
      await cache.purge();
      expect(errors, isEmpty);
      expect(cache.data.containsKey(_key), isTrue);
      expect(await cache.read<String>(_key, _fallback), _fallback);
      expect(
          errors.single,
          isA<CorruptEntryError>()
              .having((e) => e.dropped, 'dropped', isTrue)
              .having((e) => e.cause, _causeLabel,
                  i == 0 ? isA<FormatException>() : same(original)));
      expect(await cache.read<String>(_key, _fallback), _fallback);
      expect(errors, hasLength(1));
    }
  });

  test('purge protects foreign unmarked envelopes and other namespaces',
      () async {
    final cache = await _ready(const CachemanOptions(namespace: _ns));
    await cache.seed(_key);
    await cache.seed(_other, marked: false);
    const foreignKey = 'outside';
    cache.data[foreignKey] =
        defaultSerialize(CacheEntity(value: _value, createdAt: 1, expireAt: 1));
    expect(await cache.keys(), [_key, _other]);
    await cache.purge();
    expect(await cache.keys(), [_other]);
    expect(await cache.read<String>(_other), _value);
    expect(cache.data.containsKey(foreignKey), isTrue);
  });

  test(
      'unscoped erase default clears every backend key via snapshot enumeration',
      () async {
    final cache = await _ready();
    await cache.writeAll([_key, _other], [1, 2]);
    cache.data['external'] = false;
    await cache.erase();
    expect(await cache.length(), 0);
    expect(cache.data, isEmpty);
    expect(cache.calls.where((c) => c.op == CacheOp.remove), hasLength(3));
  });

  test('unscoped erase dispatches to overridden clearRaw with null key',
      () async {
    final cache = _NativeClear();
    await cache.ensureInitialized();
    await cache.write(_key, _value);
    cache.calls.clear();
    await cache.erase();
    expect(cache.data, isEmpty);
    expect(cache.calls.single.op, CacheOp.clear);
    expect(cache.calls.single.key, isNull);
    expect(cache.calls.single.namespace, isEmpty);
  });

  test(
      'renewal force scan failure is reported and read still returns the value',
      () async {
    final errors = <Object>[];
    final cache = _FailedScan(
        options:
            CachemanOptions(sliding: true, onError: (_, e) => errors.add(e)));
    await cache.ensureInitialized();
    await cache.seed(_key, remaining: 50000, ttl: _ttl);
    cache.failures = 1;
    expect(await cache.read<String>(_key), _value);
    expect(
        errors.single,
        isA<WriteError>()
            .having((e) => e.cause, _causeLabel, isA<StateError>()));
  });

  test('batch defaults, short values, ttl/expireAt and remove forwarding',
      () async {
    final cache = await _ready();
    final expiry = DateTime.now().millisecondsSinceEpoch + _ttl;
    await cache.writeAll([_key, _other], [1], ttl: _ttl, expireAt: expiry);
    expect(await cache.readAll([_key, _other], [0, _fallback]), [1, _fallback]);
    expect(await cache.readAll([_key, _other]), [1, null]);
    expect(defaultDeserialize(cache.data[_key] as String).expireAt, expiry);
    await cache.removeAll([_key, _other]);
    expect(await cache.keys(), isEmpty);
  });

  test('context carries logical keys, escaped namespace and actual operation',
      () async {
    final cache = await _ready(const CachemanOptions(
        namespace: _nestedNs, enckey: true, keyCodec: _Codec()));
    await cache.write(_key, _value);
    await cache.read<String>(_key);
    await cache.keys();
    await cache.remove(_key);
    for (final call in cache.calls) {
      expect(call.namespace, cache.namespace);
      expect(call.key,
          [CacheOp.init, CacheOp.keys].contains(call.op) ? isNull : _key);
    }
    expect(
        cache.calls.map((c) => c.op),
        containsAll([
          CacheOp.init,
          CacheOp.write,
          CacheOp.read,
          CacheOp.keys,
          CacheOp.remove
        ]));
  });
}
