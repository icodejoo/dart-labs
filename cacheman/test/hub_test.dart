import 'dart:async';
import 'dart:convert' show JsonUnsupportedObjectError, jsonDecode, jsonEncode;

import 'package:cacheman/cacheman.dart';
import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';

import 'cacheman_test.dart' show FakeCodec;

/// Error matcher label. / 错误断言标签。
const _causeLabel = 'cause';

/// Common logical key. / 共用逻辑键。
const _key = 'entry';

/// Alternate key/scope. / 另一键及作用域。
const _other = 'other';

/// Shared test namespace. / 共用测试命名空间。
const _ns = 'scope';

/// Small timer window. / 短计时窗口。
const _delay = Duration(milliseconds: 40);

/// Pending window for explicit/lifecycle flush. / 主动或生命周期落盘的待处理窗口。
const _longDelay = Duration(seconds: 10);

/// Common stored string and envelope value field. / 共用存储字符串及信封值字段。
const _value = 'value';

/// First two numbered keys. / 前两个数字键。
const _zeroKey = '0';
const _oneKey = '1';

/// Parallel backend payload fields. / 并行后端的负载字段。
const _smallKey = 'small';
const _largeKey = 'large';

/// Rx counter field. / Rx计数字段。
const _counterField = 'n';

/// Foreign backend key. / 外部底层键。
const _foreignKey = 'foreign';

/// Jsonx type tag field. / Jsonx类型标签字段。
const _tagField = '#t';

/// DateTime type tag. / DateTime 类型标签。
const _dateTimeTag = 'DateTime';

/// Empty logical key. / 空串逻辑键。
const _emptyKey = '';

/// Legacy DateTime text. / 旧版 DateTime 文本。
const _legacyDateTime = '2026-11-06T12:34:56.123456Z';

/// Object whose toJson fails internally. / toJson 内部抛错的对象。
class _BrokenJson {
  /// Original failure retained by the encoder. / 编码器保留的原始错误。
  final failure = NoSuchMethodError.withInvocation(
      Object(), Invocation.method(#missing, const []));

  /// Fails during conversion. / 转换期间抛错。
  Object toJson() => throw failure;
}

/// Observable backend shared by test subclasses. / 测试子类共享的可监听底层。
class _Backend {
  /// Stored raw values. / 存储的原始值。
  final data = <String, Object?>{};

  /// Underlying subscribers. / 底层订阅者。
  final listeners = <void Function(String?)>[];

  /// Subscription count. / 订阅次数。
  int subscriptions = 0;

  /// Persistence calls. / 持久化调用次数。
  int saves = 0;

  /// Full key scans. / 全量键扫描次数。
  int scans = 0;

  /// Deliver notifications in a microtask. / 用微任务发送通知。
  bool asynchronous = false;

  /// Injected persistence failure. / 注入的持久化错误。
  Object? saveError;

  /// Throw before returning a Future. / 在返回Future前抛错。
  bool syncSaveError = false;

  /// Notify a snapshot of subscribers. / 通知订阅者快照。
  void change(String? key) {
    for (final listener in listeners.toList()) {
      if (asynchronous) {
        scheduleMicrotask(() => listener(key));
      } else {
        listener(key);
      }
    }
  }
}

/// Full opt-in sync backend without any default-container contact.
/// 完整接入的同步后端，禁止接触默认容器。
class _Observable extends Cacheman {
  _Observable(this.backend, {super.options}) : super.custom();

  /// Shared backend identity. / 共享底层身份。
  final _Backend backend;

  /// Retained contexts for lazy-resolution checks. / 留存惰性解析测试的上下文。
  final contexts = <CacheContext>[];

  @override
  MemoryStorage get container => throw StateError('must not open default memory');
  @override
  Future<void> initRaw(CacheContext ctx) async {}
  @override
  Object get hubIdentity => backend;
  @override
  bool get syncNotificationsRaw => !backend.asynchronous;
  @override
  VoidCallback? listenRaw(CacheContext ctx, void Function(String?) onChange) {
    backend.subscriptions++;
    backend.listeners.add(onChange);
    return () => backend.listeners.remove(onChange);
  }

  @override
  Object? getRaw(CacheContext ctx, String storageKey) {
    contexts.add(ctx);
    return backend.data[storageKey];
  }

  @override
  Iterable<String> keysRaw(CacheContext ctx) {
    backend.scans++;
    return backend.data.keys;
  }

  @override
  Future<void> setRaw(CacheContext ctx, String storageKey, String value) {
    setDeferredRaw(ctx, storageKey, value);
    return Future<void>.value();
  }

  @override
  void setDeferredRaw(CacheContext ctx, String storageKey, String value) {
    backend.data[storageKey] = value;
    backend.change(storageKey);
  }

  @override
  Future<void> removeRaw(CacheContext ctx, String storageKey) {
    backend.data.remove(storageKey);
    backend.change(storageKey);
    return Future<void>.value();
  }

  @override
  Future<void> clearRaw(CacheContext ctx) {
    backend.data.clear();
    backend.change(null);
    return Future<void>.value();
  }

  @override
  Future<void> flushRaw(CacheContext ctx) {
    backend.saves++;
    if (backend.syncSaveError) throw backend.saveError!;
    return backend.saveError == null
        ? Future<void>.value()
        : Future<void>.error(backend.saveError!);
  }
}

/// Existing stage 1a subclass: inherits the new conservative defaults.
/// 阶段 1a 的已有子类，继承新增原语的保守默认行为。
class _Unobservable extends Cacheman {
  _Unobservable({super.options}) : super.custom();

  /// Legacy raw map. / 既有底层映射。
  final data = <String, String>{};

  /// Persistence calls. / 持久化调用次数。
  int saves = 0;

  /// Inject a background write failure. / 注入后台写入错误。
  bool failedSave = false;
  @override
  MemoryStorage get container => throw StateError('default backend accessed');
  @override
  Future<void> initRaw(CacheContext ctx) async {}
  @override
  Object? getRaw(CacheContext ctx, String key) => data[key];
  @override
  Iterable<String> keysRaw(CacheContext ctx) => data.keys;
  @override
  Future<void> setRaw(CacheContext ctx, String key, String value) {
    data[key] = value;
    saves++;
    return failedSave
        ? Future<void>.error(StateError('fallback write'))
        : Future<void>.value();
  }
}

/// Enforces synchronization failures on delete/clear Future boundaries.
/// 在删除/清空 Future 边界注入错误。
class _FailedMutations extends _Observable {
  _FailedMutations(super.backend, {super.options});
  @override
  Future<void> removeRaw(CacheContext ctx, String key) =>
      Future<void>.error(StateError('remove'));
  @override
  Future<void> clearRaw(CacheContext ctx) =>
      Future<void>.error(StateError('clear'));
}

/// Initializes a facade over a supplied backend. / 初始化指定后端的薄层。
Future<_Observable> _ready(_Backend backend,
    [CachemanOptions options = const CachemanOptions(namespace: _ns)]) async {
  final cache = _Observable(backend, options: options);
  await cache.ensureInitialized();
  return cache;
}

/// Minimal Rx that deliberately has no equality guard. / 故意不做判等的最小 Rx。
class _Rx {
  /// Current reactive value. / 当前响应值。
  Map<String, dynamic>? _value;

  /// Reactive assignments. / 响应值赋值次数。
  int writes = 0;

  /// Feedback writer. / 回写函数。
  late void Function(Map<String, dynamic>?) changed;

  /// Assign and emit without equality checks. / 不判等地赋值并通知。
  set value(Map<String, dynamic>? value) {
    _value = value;
    writes++;
    if (writes > 5) throw StateError('feedback loop');
    changed(_value);
  }

  /// Current payload. / 当前负载。
  Map<String, dynamic>? get value => _value;
}

/// Counts bounded key mapping behavior and can reject logical decoding.
/// 统计有界键映射行为，也可模拟逻辑键解码失败。
class _KeyCodec extends FakeCodec {
  /// Key encoding count. / 键编码次数。
  int encodes = 0;

  /// Key decoding count. / 键解码次数。
  int decodes = 0;

  /// Return null from key decoding. / 键解码返回null。
  bool reject = false;

  /// Injected encoding error. / 注入的编码错误。
  Object? encodeError;
  @override
  String encode(String value) {
    encodes++;
    if (encodeError != null) throw encodeError!;
    return super.encode(value);
  }

  @override
  String? decode(String value) {
    decodes++;
    return reject ? null : super.decode(value);
  }
}

/// Rejects initialization until explicitly retried. / 显式重试前拒绝初始化。
class _InitFailure extends _Observable {
  _InitFailure(super.backend);

  /// Reject initialization. / 拒绝初始化。
  bool failInit = true;
  @override
  Future<void> initRaw(CacheContext ctx) async {
    if (failInit) throw StateError('init');
  }
}

/// Independent asynchronous backend used alongside the synchronous facade.
/// 与同步薄层并行使用的独立异步后端。
class _ParallelAsync extends AsyncCacheman {
  _ParallelAsync({super.options});

  /// Stored raw values. / 存储的原始值。
  final data = <String, Object?>{};

  /// Optional initialization failure. / 可选的初始化错误。
  bool failInit = false;
  @override
  Future<void> initRaw(CacheContext ctx) async {
    if (failInit) throw StateError('async init');
    await super.initRaw(ctx);
  }

  @override
  Future<Object?> getRaw(CacheContext ctx, String key) async => data[key];
  @override
  Future<Iterable<String>> keysRaw(CacheContext ctx) async => data.keys;
  @override
  Future<void> setRaw(CacheContext ctx, String key, String value) async {
    data[key] = value;
  }

  @override
  Future<void> removeRaw(CacheContext ctx, String key) async {
    data.remove(key);
  }
}

/// Runs real and custom-backend acceptance cases. / 执行真实与自定义底层的验收用例。
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  var seq = 0;

  Future<Cacheman> real(String name,
      [CachemanOptions options = const CachemanOptions(namespace: _ns)]) async {
    final cache = Cacheman(container: name, options: options);
    await cache.ensureInitialized();
    return cache;
  }

  String name() => 'hub_${seq++}';

  test(
      'real watch before initialization survives empty changes and later writes',
      () async {
    final cache = Cacheman(container: name());
    final values = <int?>[];
    final stop = cache.watch<int>(_key, values.add, includeOwnWrites: true);
    addTearDown(stop);
    await cache.ensureInitialized();
    values.clear();
    cache.write(_key, 1);
    expect(values, [1]);
    expect(cache.read<int>(_key), 1);
  });

  test('memory initialization preserves existing values without spurious events', () async {
    final cache = Cacheman(container: name());
    final values = <int?>[];
    addTearDown(cache.watch<int>(_key, values.add, includeOwnWrites: true));
    await cache.container.write(_key, defaultSerialize(CacheEntity(value: 1)));
    await cache.ensureInitialized();
    expect(values, [1]);
    expect(cache.read<int>(_key), 1);
  });

  test(
      'real empty key writes stay keyed and default erase notifies all watchers',
      () async {
    final cache = await real(name(), const CachemanOptions());
    final empty = <int?>[];
    final others = <int?>[];
    addTearDown(cache.watch<int>(_emptyKey, empty.add, includeOwnWrites: true));
    addTearDown(cache.watch<int>(_other, others.add, includeOwnWrites: true));
    cache.write(_emptyKey, 1);
    expect(empty, [1]);
    expect(others, isEmpty);
    cache.write(_other, 2);
    cache.write(_emptyKey, 3);
    expect(empty, [1, 3]);
    expect(others, [2]);
    cache.erase();
    expect(empty, [1, 3, null]);
    expect(others, [2, null]);
    expect(cache.keys(), isEmpty);
  });

  test('real shared container indexes heal after peers and external changes',
      () async {
    final id = name();
    final a = await real(id);
    final b = await real(id);
    expect(a.keys(), isEmpty);
    expect(b.keys(), isEmpty);
    a.write(_key, 1);
    expect(b.keys(), [_key]);
    expect(b.length, 1);
    b.remove(_key);
    expect(a.keys(), isEmpty);
    expect(a.length, 0);
    await a.container.write(a.storageKey(_other),
        defaultSerialize(CacheEntity(value: 2, createdAt: 1)));
    expect(a.keys(), [_other]);
    expect(b.keys(), [_other]);
    await a.container.erase();
    expect(a.keys(), isEmpty);
  });

  test('one shared subscription and N local writes need no index rebuild',
      () async {
    final backend = _Backend();
    final a = await _ready(backend);
    final b = await _ready(backend);
    expect(a.keys(), isEmpty);
    expect(b.keys(), isEmpty);
    expect(backend.subscriptions, 1);
    final before = backend.scans;
    for (var i = 0; i < 100; i++) {
      a.write(i.toString(), i);
      expect(a.length, i + 1);
    }
    expect(backend.scans, before);
    expect(b.length, 100);
    expect(backend.scans, before + 1);
    a.remove(_zeroKey);
    expect(a.length, 99);
    expect(backend.scans, before + 1); // b's query did not change a's version.
    final scans = backend.scans;
    a.remove(_oneKey);
    expect(a.length, 98);
    expect(backend.scans, scans);
  });

  test(
      'real watch suppresses own writes and handles external clear cancel and namespace',
      () async {
    final id = name();
    final a = await real(id);
    final b = await real(id);
    final values = <int?>[];
    final own = <int?>[];
    final stop = a.watch<int>(_key, values.add);
    final stopOwn = a.watch<int>(_key, own.add, includeOwnWrites: true);
    a.write(_key, 1);
    expect(values, isEmpty);
    expect(own, [1]);
    b.write(_key, 2);
    expect(values, [2]);
    await a.container.write(a.storageKey(_key),
        defaultSerialize(CacheEntity(value: 3, createdAt: 1)));
    expect(values, [2, 3]);
    await b.container.erase();
    expect(values, [2, 3, null]);
    a.setNamespace(_other);
    b.write(_key, 4);
    expect(values, [2, 3, null]);
    b.setNamespace(_other);
    b.write(_key, 5);
    expect(values.last, 5);
    stop();
    stop();
    stopOwn();
    b.write(_key, 6);
    expect(values.last, 5);
  });

  test('own erase lazy deletion and sliding renewal are suppressed', () async {
    final cache = await real(name(), const CachemanOptions(sliding: true));
    var callbacks = 0;
    final stop = cache.watch<String>(_key, (_) => callbacks++);
    cache.write(_key, _value);
    cache.erase();
    expect(callbacks, 0);
    await cache.container.write(
        cache.storageKey(_key),
        defaultSerialize(CacheEntity(
          value: _value,
          createdAt: 1,
          expireAt: 1,
        )));
    expect(
        callbacks, 1); // only the external write, not the nested lazy delete.
    await cache.container.write(
        cache.storageKey(_key),
        defaultSerialize(CacheEntity(
          value: _value,
          createdAt: 1,
          ttl: 100000,
          expireAt: DateTime.now().millisecondsSinceEpoch + 50000,
        )));
    expect(callbacks, 2);
    expect(cache.read<String>(_key), _value);
    expect(callbacks, 2);
    stop();
  });

  test(
      'watch type errors report and snapshot dispatch supports reentrant changes',
      () async {
    final errors = <Object>[];
    final backend = _Backend();
    final a = await _ready(backend,
        CachemanOptions(namespace: _ns, onError: (_, e) => errors.add(e)));
    final b = await _ready(backend);
    final mismatches = <int?>[];
    final bad = a.watch<int>(_key, mismatches.add);
    var calls = 0;
    late VoidCallback second;
    VoidCallback? lateStop;
    final first = a.watch<String>(_key, (_) {
      calls++;
      second();
      lateStop ??= a.watch<String>(_key, (_) => calls += 10);
    });
    second = a.watch<String>(_key, (_) => calls += 100);
    b.write(_key, _value);
    expect(errors.single, isA<TypeMismatchError>());
    expect(mismatches, [null]);
    expect(calls, 1);
    bad();
    b.write(_key, _value);
    expect(calls, 12);
    first();
    lateStop!();
  });

  test('Map Rx two-way binding has bounded callbacks without equality checks',
      () async {
    final id = name();
    final a = await real(id);
    final b = await real(id);
    final rx = _Rx();
    var callbacks = 0;
    rx.changed = (v) => a.write(_key, v);
    final stop = a.watch<Map<String, dynamic>>(_key, (v) {
      callbacks++;
      rx.value = v;
    });
    rx.value = {_counterField: 1};
    expect(callbacks, 0);
    b.write(_key, {_counterField: 2});
    expect(callbacks, 1);
    expect(rx.writes, 2);
    expect(rx.value, {_counterField: 2});
    stop();
  });

  test('reentrant peer writes do not bless an incomplete owned-key index',
      () async {
    final backend = _Backend();
    final a = await _ready(backend);
    final b = await _ready(backend);
    a.keys();
    final stop =
        a.watch<int>(_key, (_) => b.write(_other, 2), includeOwnWrites: true);
    a.write(_key, 1);
    expect(a.keys(), containsAll([_key, _other]));
    stop();
  });

  test('unsupported and asynchronous notifications rescan on every query',
      () async {
    final silent = _Unobservable();
    await silent.ensureInitialized();
    expect(silent.keys(), isEmpty);
    silent.data[_key] = _value;
    expect(silent.keys(), [_key]);
    expect(() => silent.watch<String>(_key, (_) {}), throwsUnsupportedError);
    silent.flush(); // default custom flush is a no-op.
    final backend = _Backend()..asynchronous = true;
    final cache = await _ready(backend);
    final values = <int?>[];
    final stop = cache.watch<int>(_key, values.add);
    cache.keys();
    cache.write(_key, 1);
    expect(cache.keys(), [_key]);
    backend.data[cache.storageKey(_other)] =
        defaultSerialize(CacheEntity(value: 2));
    expect(cache.length, 2);
    await Future<void>.delayed(Duration.zero);
    expect(values, [1]); // documented fallback: own writes can arrive.
    stop();
  });

  test('flushDelay coalesces shared writers and keeps the earliest deadline',
      () async {
    final backend = _Backend();
    final a = await _ready(backend, const CachemanOptions(flushDelay: _delay));
    final b =
        await _ready(backend, const CachemanOptions(flushDelay: _longDelay));
    a.write(_key, 1);
    b.write(_other, 2);
    expect(backend.saves, 0);
    expect(a.read<int>(_key), 1);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(backend.saves, 1);
    b.write(_key, 3);
    a.write(_key, 4); // replace the later pending deadline.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(backend.saves, 2);
    a.write(_key, 5);
    a.flush();
    expect(backend.saves, 3);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(backend.saves, 3);
  });

  test('all background lifecycle states flush pending writes; resumed does not',
      () async {
    final backend = _Backend();
    final cache =
        await _ready(backend, const CachemanOptions(flushDelay: _longDelay));
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.detached
    ]) {
      cache.write(_key, 1);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final before = backend.saves;
      binding.handleAppLifecycleStateChanged(state);
      expect(backend.saves, before + 1);
    }
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  test('delayed flush errors report to latest writer and explicit caller',
      () async {
    for (final synchronous in [false, true]) {
      final first = <Object>[];
      final latest = <Object>[];
      final failure = StateError('save failed');
      final backend = _Backend()
        ..saveError = failure
        ..syncSaveError = synchronous;
      final a = await _ready(backend,
          CachemanOptions(flushDelay: _delay, onError: (_, e) => first.add(e)));
      final b = await _ready(
          backend,
          CachemanOptions(
              flushDelay: _delay, onError: (_, e) => latest.add(e)));
      a.write(_key, 1);
      b.write(_other, 2);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(first, isEmpty);
      expect(latest.single,
          isA<FlushError>().having((e) => e.cause, _causeLabel, same(failure)));
      a.flush();
      await Future<void>.delayed(Duration.zero);
      expect(first.single,
          isA<FlushError>().having((e) => e.cause, _causeLabel, same(failure)));
    }
  });

  test('memory delayed writes are immediately readable and removable', () async {
    final cache = await real(name(), const CachemanOptions(flushDelay: _longDelay));
    cache.write(_key, _value);
    expect(cache.container.read<String>(_key), isNotNull);
    expect(cache.read<String>(_key), _value);
    cache.flush();
    cache.remove(_key);
    expect(cache.container.hasData(_key), isFalse);
    cache.flush();
  });

  test(
      'custom delayed fallback delegates to setRaw and needs no default backend',
      () async {
    final cache =
        _Unobservable(options: const CachemanOptions(flushDelay: _longDelay));
    await cache.ensureInitialized();
    cache.write(_key, _value);
    expect(cache.saves, 1);
    expect(cache.read<String>(_key), _value);
    cache.flush();
  });

  test('purgeOnInit is nonblocking clears expired envelopes and ignores raw',
      () async {
    final id = name();
    final seed = await real(id);
    await seed.container.write(
        seed.storageKey(_key),
        defaultSerialize(
            CacheEntity(value: _value, createdAt: 1, expireAt: 1)));
    final cache = await real(
        id, const CachemanOptions(namespace: _ns, purgeOnInit: true));
    expect(cache.keys(), [_key]);
    await Future<void>.delayed(Duration.zero);
    expect(cache.keys(), isEmpty);
    final raw =
        await real(name(), const CachemanOptions(raw: true, purgeOnInit: true));
    raw.write(_key, _value);
    await Future<void>.delayed(Duration.zero);
    expect(raw.read<String>(_key), _value);
  });

  test('delete and clear Future errors are reported once without retry',
      () async {
    final errors = <Object>[];
    final cache = _FailedMutations(_Backend(),
        options: CachemanOptions(onError: (_, e) => errors.add(e)));
    await cache.ensureInitialized();
    cache.remove(_key);
    cache.erase();
    await Future<void>.delayed(Duration.zero);
    expect(errors, hasLength(2));
    expect(errors, everyElement(isA<FlushError>()));
  });

  test('CacheContext is lazy memoized and captures namespace before switching',
      () async {
    var resolves = 0;
    final lazy = CacheContext.lazy(
        storageKey: _key,
        namespace: '',
        op: CacheOp.read,
        resolveKey: () {
          resolves++;
          return null;
        });
    expect(resolves, 0);
    expect(lazy.storageKey, _key);
    expect(lazy.key, isNull);
    expect(lazy.key, isNull);
    expect(resolves, 1);
    final legacy =
        CacheContext(key: _key.toLowerCase(), namespace: '', op: CacheOp.read);
    expect(legacy.key, _key);
    expect(legacy.storageKey, isNull);
    for (final encrypted in [false, true]) {
      final cache = await _ready(
          _Backend(),
          CachemanOptions(
              namespace: _ns, enckey: encrypted, keyCodec: FakeCodec()));
      cache.write(_key, _value);
      cache.read<String>(_key);
      final ctx = cache.contexts.last;
      cache.setNamespace(_other);
      expect(ctx.key, _key);
      expect(ctx.namespace, '$_ns:');
    }
  });

  test('deferred fallback Future failures report without force retry',
      () async {
    final errors = <Object>[];
    final cache = _Unobservable(
        options: CachemanOptions(
            flushDelay: _longDelay, onError: (_, e) => errors.add(e)))
      ..failedSave = true;
    await cache.ensureInitialized();
    cache.write(_key, _value);
    cache.flush();
    await Future<void>.delayed(Duration.zero);
    expect(cache.saves, 1);
    expect(errors.single,
        isA<FlushError>().having((e) => e.cause, _causeLabel, isA<StateError>()));
  });

  test('force false reports once and fallback print preserves the error',
      () async {
    final messages = <String>[];
    var attempts = 0;
    final failure = StateError('serialize failed');
    final cache = await _ready(
        _Backend(),
        CachemanOptions(
            force: false,
            serialize: (_) {
              attempts++;
              throw failure;
            }));
    runZoned(() => cache.write(_key, _value),
        zoneSpecification: ZoneSpecification(
            print: (_, __, ___, message) => messages.add(message)));
    expect(attempts, 1);
    expect(messages.single, contains(failure.toString()));
    expect(cache.keys(), isEmpty);
    final handlerFailure = StateError('error handler');
    final options = CachemanOptions(
      force: false,
      serialize: (_) => throw failure,
      deserialize: (_) => throw failure,
      onError: (_, __) => throw handlerFailure,
    );
    final propagating = await _ready(_Backend(), options);
    expect(
        () => propagating.write(_key, _value), throwsA(same(handlerFailure)));
    propagating.backend.data[propagating.storageKey(_key)] = _value;
    expect(() => propagating.read<String>(_key), throwsA(same(handlerFailure)));
    final async = _ParallelAsync(options: options);
    await async.ensureInitialized();
    await expectLater(async.write(_key, _value), throwsA(same(handlerFailure)));
    async.data[async.storageKey(_key)] = _value;
    await expectLater(async.read<String>(_key), throwsA(same(handlerFailure)));
  });

  test(
      'ttl zero negative and absolute expiry validation retain intended behavior',
      () async {
    final backend = _Backend();
    final cache = await _ready(backend);
    for (final ttl in [0, -1]) {
      cache.write(_key, _value, ttl: ttl);
      expect(
          defaultDeserialize(backend.data[cache.storageKey(_key)] as String)
              .ttl,
          isNull);
      expect(cache.read<String>(_key), _value);
    }
    final future = DateTime.now().add(const Duration(days: 1));
    for (final expiry in <Object>[future, future.millisecondsSinceEpoch]) {
      cache.write(_key, _value, expireAt: expiry);
      expect(
          defaultDeserialize(backend.data[cache.storageKey(_key)] as String)
              .expireAt,
          future.millisecondsSinceEpoch);
    }
    for (final expiry in <Object>[1, _value]) {
      cache.write(_other, _value, expireAt: expiry);
      expect(cache.read<String>(_other), isNull);
    }
    final sliding =
        await _ready(_Backend(), const CachemanOptions(sliding: true));
    sliding.write(_key, _value, ttl: 100000, expireAt: 1);
    expect(sliding.read<String>(_key), _value);
  });

  test(
      'sync sliding includes exactly 90 percent and preserves the original entity',
      () async {
    for (final offset in [1000, 0, -1]) {
      late CacheEntity original;
      var writes = 0;
      final cache = await _ready(
          _Backend(),
          CachemanOptions(
            sliding: true,
            deserialize: (_) => original = CacheEntity(
                value: _value,
                createdAt: 1,
                ttl: 100000,
                expireAt:
                    DateTime.now().millisecondsSinceEpoch + 90000 + offset),
            serialize: (e) {
              writes++;
              return defaultSerialize(e);
            },
          ));
      cache.backend.data[cache.storageKey(_key)] = _value;
      expect(cache.read<String>(_key), _value);
      expect(writes, offset > 0 ? 0 : 1);
      if (offset <= 0) {
        final saved = defaultDeserialize(
            cache.backend.data[cache.storageKey(_key)] as String);
        expect(saved.expireAt, greaterThan(original.expireAt!));
        expect(saved.createdAt, original.createdAt);
        expect(saved.ttl, original.ttl);
      }
    }
  });

  test('both key maps clear on 1024 overflow and namespace resets both',
      () async {
    final codec = _KeyCodec();
    final backend = _Backend();
    final cache =
        await _ready(backend, CachemanOptions(enckey: true, keyCodec: codec));
    final first = cache.storageKey(_zeroKey);
    cache.storageKey(_zeroKey);
    expect(codec.encodes, 1);
    for (var i = 1; i <= 1024; i++) {
      cache.write(i.toString(), i);
    }
    expect(cache.storageKey(_zeroKey), first);
    expect(codec.encodes, 1026);
    cache.write(_zeroKey, 0);
    expect(cache.keys(), hasLength(1025));
    final afterScan = codec.decodes;
    cache.key(0);
    expect(codec.decodes, afterScan + 1);
    cache.key(0);
    expect(codec.decodes, afterScan + 1);
    cache.setNamespace('');
    cache.storageKey(_zeroKey);
    expect(codec.encodes, 1027);
    cache.key(0);
    expect(codec.decodes, greaterThan(afterScan + 1));
  });

  test(
      'null key decoding falls back without memoizing and excludes unowned keys',
      () async {
    final codec = _KeyCodec()..reject = true;
    final cache = await _ready(
        _Backend(), CachemanOptions(enckey: true, keyCodec: codec));
    cache.read<String>(_key);
    final before = codec.decodes;
    expect(cache.contexts.last.key, cache.storageKey(_key));
    expect(codec.decodes, before + 1);
    cache.read<String>(_key);
    expect(cache.contexts.last.key, cache.storageKey(_key));
    expect(codec.decodes, before + 2);
    cache.backend.data[cache.storageKey(_key)] = _value;
    expect(cache.keys(), isEmpty);
    cache.read<String>(_other);
    final saved = cache.contexts.last;
    cache.setNamespace(_ns);
    expect(saved.key, saved.storageKey);
  });

  test(
      'readonly raw null foreign and expired probes have no renewal side effects',
      () async {
    final raw = await _ready(
        _Backend(), const CachemanOptions(raw: true, readonly: true));
    raw.write(_key, _value);
    raw.write(_key, _other);
    expect(raw.read<String>(_key), _value);
    final cache =
        await _ready(_Backend(), const CachemanOptions(readonly: true));
    cache.write<Object?>(_key, null);
    cache.write(_key, _value);
    expect(cache.read<Object?>(_key), isNull);
    cache.backend.data[cache.storageKey(_key)] = false;
    expect(cache.read<String>(_key, _other), _other);
    cache.write(_key, _value);
    expect(cache.read<String>(_key), _value);
    cache.backend.data[cache.storageKey(_key)] =
        defaultSerialize(CacheEntity(value: _other, createdAt: 1, expireAt: 1));
    cache.write(_key, _value);
    expect(cache.read<String>(_key), _value);
  });

  test(
      'watch migration handles encoded keys and cancellation during clear snapshot',
      () async {
    final backend = _Backend();
    final options =
        CachemanOptions(namespace: _ns, enckey: true, keyCodec: FakeCodec());
    final a = await _ready(backend, options);
    final b = await _ready(backend, options);
    final values = <String?>[];
    final stop = a.watch<String>(_key, values.add);
    a.setNamespace(_other);
    b.write(_key, _value);
    expect(values, isEmpty);
    b.setNamespace(_other);
    b.write(_key, _value);
    expect(values, [_value]);
    stop();
    var calls = 0;
    late VoidCallback cancel;
    final first = a.watch<String>(_key, (_) {
      calls++;
      cancel();
    });
    cancel = a.watch<String>(_other, (_) => calls += 10);
    backend.data.clear();
    backend.change(null);
    expect(calls, 1);
    first();
  });

  test('watch can change its namespace during an own write safely', () async {
    final a = await _ready(_Backend());
    a.keys();
    final stop = a.watch<int>(_key, (_) => a.setNamespace(_other),
        includeOwnWrites: true);
    a.write(_key, 1);
    expect(a.namespace, '$_other:');
    expect(a.keys(), isEmpty);
    stop();
  });

  test(
      'failed initialization leaves sync and async writes guarded until retry succeeds',
      () async {
    final sync = _InitFailure(_Backend());
    await expectLater(sync.ensureInitialized(), throwsStateError);
    expect(() => sync.write(_key, _value), throwsAssertionError);
    sync.failInit = false;
    await sync.ensureInitialized();
    sync.write(_key, _value);
    expect(sync.read<String>(_key), _value);
    final async = _ParallelAsync()..failInit = true;
    await expectLater(async.ensureInitialized(), throwsStateError);
    await expectLater(async.write(_key, _value), throwsAssertionError);
    async.failInit = false;
    await async.ensureInitialized();
    await async.write(_key, _value);
    expect(await async.read<String>(_key), _value);
  });

  test('sync and async backends run in parallel and never cache read values',
      () async {
    final sync = await _ready(_Backend());
    final async = _ParallelAsync(
        options: const CachemanOptions(
            namespace: _ns, flushDelay: _longDelay, purgeOnInit: true));
    await async.ensureInitialized();
    sync.write(_key, {_smallKey: 1});
    await async.write(_key, {
      _largeKey: [1, 2, 3]
    });
    final small = sync.read<Map<String, dynamic>>(_key)!;
    small[_smallKey] = 99;
    expect(sync.read<Map<String, dynamic>>(_key), {_smallKey: 1});
    expect(await async.read<Map<String, dynamic>>(_key), {
      _largeKey: [1, 2, 3]
    });
    sync.backend.data[sync.storageKey(_key)] =
        defaultSerialize(CacheEntity(value: _other));
    expect(sync.read<String>(_key), _other);
    async.data[async.storageKey(_other)] =
        defaultSerialize(CacheEntity(value: _value, createdAt: 1, expireAt: 1));
    await async.ensureInitialized();
    await Future<void>.delayed(Duration.zero);
    expect(await async.keys(), contains(_other));
    sync.erase();
    expect(await async.length(), 2);
  });

  test(
      'sync enckey-only erase preserves foreign keys and unmarked envelopes never expire',
      () async {
    final cache = await _ready(
        _Backend(), CachemanOptions(enckey: true, keyCodec: FakeCodec()));
    cache.backend.data[_foreignKey] = _value;
    cache.backend.data[cache.storageKey(_key)] =
        defaultSerialize(CacheEntity(value: _value, expireAt: 1));
    cache.backend.change(cache.storageKey(_key));
    cache.purge();
    expect(cache.read<String>(_key), _value);
    expect(cache.key(-1), isNull);
    expect(cache.key(1), isNull);
    expect(cache.key(0), _key);
    cache.erase();
    expect(cache.backend.data, {_foreignKey: _value});
    cache.setNamespace('');
    expect(cache.namespace, isEmpty);
  });

  test(
      'watch codec and callback failures preserve registered error keys and keep dispatching',
      () async {
    final backend = _Backend();
    final codec = _KeyCodec();
    final errors = <(String, Object)>[];
    final a = await _ready(
        backend,
        CachemanOptions(
            enckey: true,
            keyCodec: codec,
            onError: (key, error) => errors.add((key, error))));
    final b = await _ready(
        backend, CachemanOptions(enckey: true, keyCodec: FakeCodec()));
    final failure = StateError('callback');
    final encodeFailure = StateError('encode');
    final sk = a.storageKey(_key);
    final stop = a.watch<String>(_key, (_) => throw failure);
    final values = <String?>[];
    final peerStop = b.watch<String>(_key, values.add);
    backend.data[sk] = defaultSerialize(CacheEntity(value: _value));
    backend.change(sk);
    expect(errors.single.$1, sk);
    expect(errors.single.$2,
        isA<WatchError>().having((e) => e.cause, _causeLabel, same(failure)));
    expect(values, [_value]);
    for (var i = 0; i <= 1024; i++) {
      a.storageKey('evict$i');
    }
    codec.encodeError = encodeFailure;
    backend.change(sk);
    expect(errors.last.$1, sk);
    expect(errors.last.$2,
        isA<WatchError>().having((e) => e.cause, _causeLabel, same(encodeFailure)));
    expect(values, [_value, _value]);
    stop();
    peerStop();
  });

  test('throwing watch onError propagates once through own and peer writes',
      () async {
    for (final own in [false, true]) {
      final backend = _Backend();
      final failure = StateError('handler');
      var reports = 0;
      final a = await _ready(
          backend,
          CachemanOptions(
              namespace: _ns,
              onError: (_, error) {
                reports++;
                expect(error, isA<TypeMismatchError>());
                throw failure;
              }));
      final b = await _ready(backend);
      final stop = a.watch<int>(
          _key, (_) => fail('handler failure must propagate'),
          includeOwnWrites: true);
      expect(() => (own ? a : b).write(_key, _value), throwsA(same(failure)));
      expect(reports, 1);
      expect(backend.scans, 0);
      stop();
    }
  });

  test('R1 reentrant namespace enumeration preserves scope isolation',
      () async {
    final backend = _Backend();
    final cache = await _ready(backend);
    final oldKey = cache.storageKey(_key);
    expect(cache.keys(), isEmpty);
    final stop = cache.watch<int>(_key, (_) {
      cache.setNamespace(_other);
      expect(cache.keys(), isEmpty);
    }, includeOwnWrites: true);
    addTearDown(stop);
    cache.write(_key, 1);
    expect(cache.keys(), isEmpty);
    cache.write(_other, 2);
    expect(cache.keys(), [_other]);
    cache.erase();
    expect(backend.data.keys, [oldKey]);
    expect(defaultDeserialize(backend.data[oldKey] as String).value, 1);
  });

  test('R3 caught unrelated handler errors do not poison watch dispatch',
      () async {
    final reports = <Object>[];
    final cache = await _ready(
        _Backend(), CachemanOptions(onError: (_, e) => reports.add(e)));
    final handlerFailure = StateError('unrelated handler');
    final unrelated = await _ready(
        _Backend(), CachemanOptions(onError: (_, e) => throw handlerFailure));
    unrelated.write(_key, _value);
    final failure = StateError('watch business failure');
    final first = cache.watch<int>(_key, (_) {
      try {
        unrelated.read<int>(_key);
      } catch (_) {
        // The unrelated handler error is handled here. / 此处已处理无关的处理器异常。
      }
      throw failure;
    }, includeOwnWrites: true);
    addTearDown(first);
    var calls = 0;
    final second =
        cache.watch<int>(_key, (_) => calls++, includeOwnWrites: true);
    addTearDown(second);
    expect(() => cache.write(_key, 1), returnsNormally);
    expect(reports.single,
        isA<WatchError>().having((e) => e.cause, _causeLabel, same(failure)));
    expect(calls, 1);
    first();
    final reused = cache.watch<int>(_key, (_) => throw handlerFailure,
        includeOwnWrites: true);
    addTearDown(reused);
    expect(() => unrelated.read<int>(_key), throwsA(same(handlerFailure)));
    // A new report resets the marker before business code reuses the object.
    // 新一次上报清空标记，随后业务代码可复用同一异常对象。
    expect(cache.read<String>(_key), isNull);
    expect(reports.last, isA<TypeMismatchError>());
    expect(() => cache.write(_key, 2), returnsNormally);
    expect(reports.length, 3);
    expect(
        reports.last,
        isA<WatchError>()
            .having((e) => e.cause, _causeLabel, same(handlerFailure)));
    expect(calls, 2);
  });

  test('R4 default memory handler errors propagate unchanged through Zone',
      () async {
    final id = name();
    final failure = StateError('watch handler');
    final watcherErrors = <Object>[];
    final writerErrors = <Object>[];
    final zoneErrors = <Object>[];
    final watcher = await real(id, CachemanOptions(onError: (_, error) {
      watcherErrors.add(error);
      throw failure;
    }));
    final writer = await real(
        id, CachemanOptions(onError: (_, error) => writerErrors.add(error)));
    final callbackFailure = StateError('watch callback');
    final stop = watcher.watch<int>(_key, (_) => throw callbackFailure);
    addTearDown(stop);
    final mutations = [
      () => writer.write(_key, _value),
      () => writer.remove(_key),
      writer.erase,
    ];
    for (var i = 0; i < mutations.length; i++) {
      runZonedGuarded<void>(() {
        expect(mutations[i], returnsNormally);
      }, (error, trace) => zoneErrors.add(error));
      await Future<void>.delayed(Duration.zero);
      expect(writerErrors, isEmpty);
      expect(zoneErrors, hasLength(i + 1));
      expect(zoneErrors.last, same(failure));
    }
    expect(watcherErrors, [
      isA<TypeMismatchError>(),
      isA<WatchError>()
          .having((e) => e.cause, _causeLabel, same(callbackFailure)),
      isA<WatchError>()
          .having((e) => e.cause, _causeLabel, same(callbackFailure)),
    ]);
  });

  test('R5 migrated snapshot watchers skip old keys and still receive clear',
      () async {
    final backend = _Backend();
    final cache = await _ready(backend);
    backend.data['$_other:$_key'] = defaultSerialize(CacheEntity(value: 99));
    final first = cache.watch<int>(_key, (_) => cache.setNamespace(_other),
        includeOwnWrites: true);
    addTearDown(first);
    final values = <int?>[];
    final second = cache.watch<int>(_key, values.add, includeOwnWrites: true);
    addTearDown(second);
    cache.write(_key, 1);
    expect(values, isEmpty);
    cache.write(_key, 2);
    expect(values, [2]);
    backend.data.clear();
    backend.change(null);
    expect(values, [2, null]);
  });

  test('R6 reentrant delayed flush failures belong to the nested writer',
      () async {
    final failure = StateError('nested save');
    final backend = _Backend()..saveError = failure;
    final firstErrors = <Object>[];
    final latestErrors = <Object>[];
    final first = await _ready(
        backend,
        CachemanOptions(
            flushDelay: _delay, onError: (_, error) => firstErrors.add(error)));
    final latest = await _ready(
        backend,
        CachemanOptions(
            flushDelay: _delay,
            onError: (_, error) => latestErrors.add(error)));
    final stop = first.watch<int>(_key, (_) => latest.write(_other, 2),
        includeOwnWrites: true);
    addTearDown(stop);
    first.write(_key, 1);
    expect(latest.read<int>(_other), 2);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(backend.saves, 1);
    expect(firstErrors, isEmpty);
    expect(latestErrors.single,
        isA<FlushError>().having((e) => e.cause, _causeLabel, same(failure)));
  });

  test('Jsonx unknown tags shape mismatch and cast errors', () {
    expect(Jsonx.decode<Object>(' {"#t":"unknown","value":1}'),
        {_tagField: 'unknown', _value: 1});
    expect(Jsonx.decode<Object>('{"#t":"DateTime","value":"x","sibling":1}'),
        {_tagField: _dateTimeTag, _value: 'x', 'sibling': 1});
    expect(() => Jsonx.decode<int>('"wrong"'), throwsA(isA<TypeError>()));
    expect(() => Jsonx.encode({1: _value}), throwsA(isA<Object>()));
  });

  test('Jsonx DateTime preserves instant and UTC mode with legacy decoding',
      () {
    for (final isUtc in [false, true]) {
      final original =
          DateTime.fromMicrosecondsSinceEpoch(1793943296123456, isUtc: isUtc);
      final encoded = Jsonx.encode(original);
      expect(jsonDecode(encoded), {
        _tagField: _dateTimeTag,
        _value: [original.microsecondsSinceEpoch, isUtc],
      });
      final decoded = Jsonx.decode<DateTime>(encoded);
      expect(decoded, original);
      expect(decoded.isUtc, isUtc);
      expect(decoded.microsecondsSinceEpoch, original.microsecondsSinceEpoch);
    }
    expect(
        Jsonx.decode<DateTime>(
            jsonEncode({_tagField: _dateTimeTag, _value: _legacyDateTime})),
        DateTime.parse(_legacyDateTime));
    for (final raw in [
      null,
      [],
      [1],
      [1, true, 2],
      ['1', true],
      [1, 0]
    ]) {
      final tagged = {_tagField: _dateTimeTag, _value: raw};
      expect(Jsonx.decode<Object>(jsonEncode(tagged)), tagged);
    }
  });

  test('Jsonx wraps internal NoSuchMethodError with its original cause', () {
    final value = _BrokenJson();
    expect(
        () => Jsonx.encode(value),
        throwsA(isA<JsonUnsupportedObjectError>().having(
            (e) => e.cause,
            _causeLabel,
            allOf(isA<NoSuchMethodError>(), same(value.failure)))));
  });

  test('Jsonx Enum encoding throws JsonUnsupportedObjectError', () {
    expect(() => Jsonx.encode(CacheOp.read),
        throwsA(isA<JsonUnsupportedObjectError>()));
  });
}
