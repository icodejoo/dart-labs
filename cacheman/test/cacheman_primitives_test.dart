import 'package:cacheman/cacheman.dart';
import 'package:flutter_test/flutter_test.dart';

const _key = 'entry';
const _other = 'other';
const _value = 'value';
const _ns = 'custom';
const _ttl = 100000;

/// Fully synchronous custom backend; any default container access fails the test.
/// 完全同步的自定义后端；访问默认容器即令测试失败。
class _MemorySync extends Cacheman {
  _MemorySync({super.options}) : super.custom();

  /// Test-local raw storage. / 测试内的原始存储。
  final data = <String, Object?>{};

  /// Primitive routing log. / 原语路由记录。
  final calls = <CacheContext>[];

  /// Default-container access counter. / 默认容器访问计数。
  int containerAccesses = 0;

  /// Write attempts and injected failures. / 写入次数与注入的失败次数。
  int writes = 0;
  int failures = 0;

  /// Whether failures belong to background flush Futures. / 失败是否来自后台 flush Future。
  bool backgroundFailure = false;

  /// Stable error for identity checks. / 用于验证异常身份。
  final failure = StateError('injected');

  @override
  MemoryStorage get container {
    containerAccesses++;
    throw StateError('default container must stay lazy');
  }

  @override
  Future<void> initRaw(CacheContext ctx) {
    calls.add(ctx);
    return Future<void>.value();
  }

  @override
  Object? getRaw(CacheContext ctx, String storageKey) {
    calls.add(ctx);
    return data[storageKey];
  }

  @override
  Iterable<String> keysRaw(CacheContext ctx) {
    calls.add(ctx);
    return data.keys;
  }

  @override
  Future<void> setRaw(CacheContext ctx, String storageKey, String value) {
    calls.add(ctx);
    writes++;
    if (failures > 0) {
      failures--;
      if (backgroundFailure) {
        data[storageKey] =
            value; // memory succeeded; only persistence failed / 内存成功，仅落盘失败
        return Future<void>.error(failure);
      }
      throw failure;
    }
    data[storageKey] = value;
    return Future<void>.value();
  }

  @override
  Future<void> removeRaw(CacheContext ctx, String storageKey) {
    calls.add(ctx);
    data.remove(storageKey);
    return Future<void>.value();
  }

  @override
  Future<void> clearRaw(CacheContext ctx) {
    calls.add(ctx);
    data.clear();
    return Future<void>.value();
  }

  /// Seeds expiry without waiting for wall time. / 无需等待实际时间即可植入过期状态。
  void seed(String key, {int remaining = -1, int? ttl}) {
    data[storageKey(key)] = defaultSerialize(CacheEntity(
      value: _value,
      createdAt: 1,
      expireAt: DateTime.now().millisecondsSinceEpoch + remaining,
      ttl: ttl,
    ));
  }
}

/// Initializes the custom synchronous backend. / 初始化自定义同步后端。
Future<_MemorySync> _ready(
    [CachemanOptions options = const CachemanOptions()]) async {
  final cache = _MemorySync(options: options);
  await cache.ensureInitialized();
  return cache;
}

void main() {
  test('pure Dart backends are replaceable without touching default memory',
      () async {
    final defaultCache = Cacheman(container: 'replaceable');
    final custom = await _ready();
    await defaultCache.ensureInitialized();
    defaultCache.write(_key, _other);
    custom.write(_key, _value);
    expect(defaultCache.read<String>(_key), _other);
    expect(custom.read<String>(_key), _value);
    expect(custom.data[_key], isA<String>());
    expect(custom.containerAccesses, 0);
    expect(() => custom.watch<String>(_key, (_) {}), throwsUnsupportedError);
    final peer = Cacheman(container: 'replaceable');
    await peer.ensureInitialized();
    expect(peer.read<String>(_key), _other);
  });

  test('all primitives override default backend; CRUD is synchronous',
      () async {
    final cache = await _ready();
    cache.writeAll([_key, _other], [1, 2]);
    expect(cache.readAll([_key, _other]), [1, 2]);
    expect(cache.keys(), [_key, _other]);
    expect(cache.length, 2);
    expect(cache.key(1), _other);
    cache.removeAll([_key]);
    expect(cache.read<int>(_key), isNull);
    cache.erase();
    expect(cache.data, isEmpty);
    expect(cache.containerAccesses, 0);
    expect(cache.calls.map((c) => c.op), containsAll(CacheOp.values));
    expect(cache.calls.where((c) => c.op == CacheOp.clear).single.key, isNull);
  });

  test('expiry, sliding, namespace and owned-key cache work over primitives',
      () async {
    final cache =
        await _ready(const CachemanOptions(namespace: _ns, sliding: true));
    cache.write(_key, _value, ttl: _ttl);
    final writes = cache.writes;
    expect(cache.read<String>(_key), _value);
    expect(cache.writes, writes); // above 90%, no renewal
    cache.seed(_key, remaining: 50000, ttl: _ttl);
    expect(cache.read<String>(_key), _value);
    expect(cache.writes, writes + 1);
    expect(cache.keys(), [_key]);
    cache.seed(_key);
    expect(cache.read<String>(_key), isNull);
    expect(cache.keys(), isEmpty);
    cache.write(_key, 1);
    cache.setNamespace(_other);
    cache.write(_key, 2);
    cache.erase();
    cache.setNamespace(_ns);
    expect(cache.read<int>(_key), 1);
    expect(cache.keys(), [_key]);
    cache.seed(_key);
    cache.purge();
    expect(cache.length, 0);
    expect(cache.containerAccesses, 0);
    final write = cache.calls.firstWhere((c) => c.op == CacheOp.write);
    expect(write.key, _key);
    expect(write.namespace, '$_ns:');
  });

  test('force retries synchronous throws and maintains owned keys on retry',
      () async {
    final cache = await _ready(const CachemanOptions(namespace: _ns));
    expect(cache.keys(), isEmpty); // seed the cache before the successful retry
    cache.failures = 1;
    cache.write(_key, _value);
    expect(cache.writes, 2);
    expect(cache.keys(), [_key]);
    expect(cache.read<String>(_key), _value);
    expect(cache.containerAccesses, 0);
  });

  test('flush Future errors report once and are never retried', () async {
    final errors = <Object>[];
    final cache =
        await _ready(CachemanOptions(onError: (_, e) => errors.add(e)));
    cache.backgroundFailure = true;
    cache.failures = 1;
    cache.write(_key, _value);
    await Future<void>.delayed(Duration.zero);
    expect(cache.writes, 1);
    expect(cache.read<String>(_key), _value);
    expect(errors.single,
        isA<FlushError>().having((e) => e.cause, 'cause', same(cache.failure)));
    expect(cache.containerAccesses, 0);
  });
}
