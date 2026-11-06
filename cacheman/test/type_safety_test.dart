import 'package:cacheman/cacheman.dart';
import 'package:flutter_test/flutter_test.dart';

/// Error matcher label. / 错误断言标签。
const _causeLabel = 'cause';

/// Shared logical key. / 共用逻辑键。
const _key = 'entry';

/// Expired entry used to observe purge. / 用于观察清理的过期条目。
const _expired = 'expired';

/// Common payload. / 共用负载。
const _value = 'Ada';

/// Default accessor lifetime. / 访问器默认寿命。
const _ttl = 60000;

/// Explicit ttl override. / 显式 ttl 覆盖。
const _overrideTtl = 10000;

/// Must never execute in raw mode. / raw 模式绝不执行。
const _ignoredAdapter = 'must ignore';

/// Business value deliberately lacking toJson. / 故意没有 toJson 的业务值。
class _Profile {
  const _Profile(this.name);

  /// Business name. / 业务名称。
  final String name;
}

/// Explicit business conversion. / 显式业务转换。
final _profileAdapter = ValueAdapter<_Profile>(
  toJson: (value) => {_key: value.name},
  fromJson: (json) => _Profile((json as Map)[_key] as String),
);

/// Backend counters and injected failures shared by both test facades.
/// 两种测试薄层共用的底层计数和故障注入。
class _State {
  /// Raw strings, including deliberately corrupted envelopes. / 原始字符串（含损坏信封）。
  final data = <String, Object?>{};

  /// Actual enumeration/removal/write counts. / 实际枚举、删除、写入次数。
  int scans = 0, removes = 0, writes = 0;

  /// Remaining primitive failures. / 剩余原语失败次数。
  int failures = 0;

  /// Return a failed Future instead of throwing. / 返回失败 Future 而非同步抛错。
  bool background = false;

  /// Stable original failure. / 稳定的原始异常。
  final failure = StateError('backend');

  /// Original thrown stack. / 原始抛错堆栈。
  final trace = StackTrace.current;

  /// Updates memory before returning, unless a foreground failure is injected.
  /// 除注入前台失败外，返回前更新内存。
  Future<void> set(String key, String value) {
    writes++;
    if (failures > 0) {
      failures--;
      if (background) return Future<void>.error(failure, trace);
      Error.throwWithStackTrace(failure, trace);
    }
    data[key] = value;
    return Future<void>.value();
  }

  /// Seeds expired marked data without timing races. / 无时序竞争地植入过期信封。
  void seedExpired() {
    data[_expired] =
        defaultSerialize(CacheEntity(value: _value, createdAt: 1, expireAt: 1));
  }
}

/// Synchronous test primitive facade, never opens get_storage.
/// 同步测试原语薄层，从不打开 get_storage。
class _Sync extends Cacheman {
  _Sync(this.state, {super.options}) : super.custom();

  /// State for raw operations. / 原语状态。
  final _State state;
  @override
  Future<void> initRaw(CacheContext ctx) async {}
  @override
  Object? getRaw(CacheContext ctx, String key) => state.data[key];
  @override
  Iterable<String> keysRaw(CacheContext ctx) {
    state.scans++;
    return state.data.keys;
  }

  @override
  Future<void> setRaw(CacheContext ctx, String key, String value) =>
      state.set(key, value);
  @override
  Future<void> removeRaw(CacheContext ctx, String key) {
    state.removes++;
    state.data.remove(key);
    return Future<void>.value();
  }
}

/// Awaited test primitive facade using the same failure budgets.
/// 使用相同故障预算的异步测试原语薄层。
class _Async extends AsyncCacheman {
  _Async(this.state, {super.options});

  /// State for raw operations. / 原语状态。
  final _State state;
  @override
  Future<Object?> getRaw(CacheContext ctx, String key) async => state.data[key];
  @override
  Future<Iterable<String>> keysRaw(CacheContext ctx) async {
    state.scans++;
    return state.data.keys;
  }

  @override
  Future<void> setRaw(CacheContext ctx, String key, String value) =>
      state.set(key, value);
  @override
  Future<void> removeRaw(CacheContext ctx, String key) async {
    state.removes++;
    state.data.remove(key);
  }
}

/// Creates either facade; dynamic keeps identical assertions on both APIs.
/// 创建任一薄层；dynamic 让两种 API 使用完全相同的断言。
Future<dynamic> _ready(
    bool asynchronous, _State state, CachemanOptions options) async {
  final dynamic cache = asynchronous
      ? _Async(state, options: options)
      : _Sync(state, options: options);
  await cache.ensureInitialized();
  return cache;
}

/// Codec whose encoding deterministically fails. / 编码确定性失败的 codec。
class _BrokenCodec implements Codec {
  _BrokenCodec(this.failure);

  /// Original encoding exception. / 原始编码异常。
  final Object failure;
  @override
  String encode(String value) => throw failure;
  @override
  String decode(String value) => value;
}

void main() {
  for (final asynchronous in [false, true]) {
    test(
        'read mismatches retain data defaults and exact numeric types (async=$asynchronous)',
        () async {
      final errors = <Object>[];
      final state = _State();
      final cache = await _ready(asynchronous, state,
          CachemanOptions(onError: (_, e) => errors.add(e)));
      await cache.write(_key, [_value]);
      const fallback = <String>[];
      expect(await cache.read<List<String>>(_key, fallback), same(fallback));
      final mismatch = errors.single as TypeMismatchError;
      expect(mismatch.key, _key);
      expect(mismatch.expected, List<String>);
      expect(mismatch.actual, <dynamic>[].runtimeType);
      expect(mismatch.cause, isA<TypeError>());
      expect(mismatch.stackTrace, isNotNull);
      expect(state.data, contains(_key));
      expect(state.removes, 0);
      expect(await cache.read<dynamic>(_key), [_value]);
      expect(await cache.read<Object?>(_key), [_value]);
      expect(await cache.readAll([_key]), [
        [_value]
      ]);
      expect(errors, hasLength(1));
      await cache.write(_key, 1);
      expect(await cache.read<double>(_key, 2.0), 2.0);
      expect((errors.last as TypeMismatchError).actual, int);
      expect((errors.last as TypeMismatchError).expected, double);
      expect(await cache.read<num>(_key), 1);
      await cache.write(_key, 1.5);
      expect(await cache.read<int>(_key, 2), 2);
      expect(state.removes, 0);
    });

    test('corrupt entries report dropped cause and trace (async=$asynchronous)',
        () async {
      final errors = <Object>[];
      final state = _State()..data[_key] = _value;
      final cache = await _ready(asynchronous, state,
          CachemanOptions(onError: (_, e) => errors.add(e)));
      expect(await cache.read<String>(_key), isNull);
      final error = errors.single as CorruptEntryError;
      expect(error.dropped, isTrue);
      expect(error.cause, isA<FormatException>());
      expect(error.stackTrace, isNotNull);
      expect(state.removes, 1);
      expect(error.toString(), contains(_key));
      expect(error.toString(), contains(error.cause.toString()));
    });

    test(
        'raw ignores write adapters and keeps String storage (async=$asynchronous)',
        () async {
      final state = _State();
      final cache =
          await _ready(asynchronous, state, const CachemanOptions(raw: true));
      final adapter = ValueAdapter<String>(
          toJson: (_) => throw StateError(_ignoredAdapter),
          fromJson: (_) => throw StateError(_ignoredAdapter));
      await cache.write<String>(_key, _value, adapter: adapter);
      expect(state.data[_key], _value);
      expect(await cache.read<String>(_key), _value);
      expect(await cache.readWith<String>(_key, adapter: adapter), _value);
      final errors = <Object>[];
      final mismatch = await _ready(asynchronous, state,
          CachemanOptions(raw: true, onError: (_, e) => errors.add(e)));
      expect(await mismatch.read<int>(_key, 3), 3);
      expect(errors.single, isA<TypeMismatchError>());
    });

    test(
        'typed adapters roundtrip collections and business values (async=$asynchronous)',
        () async {
      final state = _State();
      final errors = <Object>[];
      final cache = await _ready(asynchronous, state,
          CachemanOptions(onError: (_, e) => errors.add(e)));
      final lists = ValueAdapter.listOf<String>();
      await cache.write(_key, [_value]);
      final names = await cache.readWith<List<String>>(_key, adapter: lists);
      expect(names, isA<List<String>>());
      expect(names, [_value]);
      final maps = ValueAdapter.mapOf<int>();
      await cache.write<Map<String, int>>(_key, <String, int>{_value: 1},
          adapter: maps);
      expect(await cache.read<Map<String, int>>(_key, const <String, int>{}),
          isEmpty);
      expect(await cache.readWith<Map<String, int>>(_key, adapter: maps),
          {_value: 1});
      expect(errors.single, isA<TypeMismatchError>());
      errors.clear();
      await cache.write<_Profile>(_key, const _Profile(_value),
          adapter: _profileAdapter);
      expect(
          (await cache.readWith<_Profile>(_key, adapter: _profileAdapter)).name,
          _value);
      final before = state.data[_key];
      final failure = FormatException('business conversion');
      const fallback = _Profile(_expired);
      final broken = ValueAdapter<_Profile>(
          toJson: _profileAdapter.toJson, fromJson: (_) => throw failure);
      expect(
          await cache.readWith<_Profile>(_key,
              defaultValue: fallback, adapter: broken),
          same(fallback));
      final error = errors.single as TypeMismatchError;
      expect(error.cause, same(failure));
      expect(error.expected, _Profile);
      expect(error.actual, <String, dynamic>{}.runtimeType);
      expect(state.data[_key], before);
      expect(state.removes, 0);
      expect(await cache.readWith<String>(_key, defaultValue: _value), _value);
      expect(
          await cache.readWith<String>(_expired, defaultValue: _value), _value);
      final nullable =
          ValueAdapter<String?>(toJson: (_) => null, fromJson: (_) => null);
      await cache.write<String?>(_key, null, adapter: nullable);
      expect(await cache.readWith<String?>(_key, adapter: nullable), isNull);
      await cache.write(_key, [1]);
      expect(
          await cache.readWith<List<String>>(_key,
              defaultValue: const <String>[], adapter: lists),
          isEmpty);
      expect(
          errors.last,
          isA<TypeMismatchError>()
              .having((e) => e.cause, _causeLabel, isA<TypeError>()));
      await cache.write(_key, 1);
      final doubles = ValueAdapter<double>(
          toJson: (v) => v, fromJson: (j) => (j as num).toDouble());
      expect(await cache.readWith<double>(_key, adapter: doubles), 1.0);
    });

    test('encoding failures never scan remove or retry (async=$asynchronous)',
        () async {
      final failure = FormatException('encode');
      final badAdapter = ValueAdapter<String>(
          toJson: (_) => throw failure, fromJson: (j) => j as String);
      for (final mode in [0, 1, 2]) {
        var builds = 0;
        final errors = <Object>[];
        final state = _State()..seedExpired();
        final cache = await _ready(
            asynchronous,
            state,
            CachemanOptions(
              serialize: (e) {
                builds++;
                if (mode == 0) throw failure;
                return defaultSerialize(e);
              },
              codeable: mode == 1,
              codec: _BrokenCodec(failure),
              onError: (_, e) => errors.add(e),
            ));
        await cache.write<String>(_key, _value,
            adapter: mode == 2 ? badAdapter : null);
        expect(state.writes, 0);
        expect(state.scans, 0);
        expect(state.removes, 0);
        expect(state.data, contains(_expired));
        expect(builds, mode == 2 ? 0 : 1);
        expect(
            errors.single,
            isA<SerializeError>()
                .having((e) => e.cause, _causeLabel, same(failure))
                .having((e) => e.stackTrace, 'trace', isNotNull));
      }
    });

    test(
        'backend retries reuse one build and classify final failures (async=$asynchronous)',
        () async {
      for (final force in [true, false]) {
        for (final failures in [1, 2]) {
          final state = _State()
            ..failures = failures
            ..background = asynchronous
            ..seedExpired();
          var builds = 0;
          final errors = <Object>[];
          final cache = await _ready(
              asynchronous,
              state,
              CachemanOptions(
                  force: force,
                  serialize: (e) {
                    builds++;
                    return defaultSerialize(e);
                  },
                  onError: (_, e) => errors.add(e)));
          await cache.write(_key, _value);
          expect(builds, 1);
          expect(state.writes, force ? 2 : 1);
          expect(state.scans, force ? 1 : 0);
          expect(state.removes, force ? 1 : 0);
          if (force && failures == 1) {
            expect(errors, isEmpty);
            expect(await cache.read<String>(_key), _value);
          } else {
            final error = errors.single as WriteError;
            expect(error.key, _key);
            expect(error.cause, same(state.failure));
            expect(error.stackTrace, isNotNull);
          }
        }
      }
    });
  }

  test('fast lazy and batch accessors adapt values and apply default ttl',
      () async {
    final state = _State();
    final cache = _Sync(state);
    await cache.ensureInitialized();
    final names = fast<List<String>>(cache, _key,
        adapter: ValueAdapter.listOf<String>(), ttl: _ttl);
    names.set([_value]);
    expect(names.get(), [_value]);
    var entity = defaultDeserialize(state.data[_key] as String);
    expect(entity.ttl, _ttl);
    expect(entity.expireAt, entity.createdAt! + _ttl);
    names.set([_value], ttl: _overrideTtl);
    entity = defaultDeserialize(state.data[_key] as String);
    expect(entity.ttl, _overrideTtl);
    final business =
        lazy<_Profile>(cache, _key, adapter: _profileAdapter, ttl: _ttl);
    expect(business(), same(business()));
    business().set(const _Profile(_value));
    expect(business().get()!.name, _value);
    expect(defaultDeserialize(state.data[_key] as String).ttl, _ttl);
    final batch = batchFast<Map<String, int>>(cache, [_key, _expired],
        adapter: ValueAdapter.mapOf<int>(), ttl: _ttl);
    for (final accessor in batch.values) {
      accessor.set({_value: 1});
      expect(accessor.get(), {_value: 1});
    }
    expect(defaultDeserialize(state.data[_expired] as String).ttl, _ttl);
    final errors = <Object>[];
    final typed = _Sync(state,
        options: CachemanOptions(onError: (_, e) => errors.add(e)));
    await typed.ensureInitialized();
    cache.write(_key, [_value]);
    expect(fast<List<String>>(typed, _key).get(const []), isEmpty);
    expect(lazy<List<String>>(typed, _key)().get(const []), isEmpty);
    expect(errors, everyElement(isA<TypeMismatchError>()));
    expect(state.data, contains(_key));
  });

  test('collection adapters eagerly validate and copy JSON structures', () {
    final lists = ValueAdapter.listOf<String>();
    final maps = ValueAdapter.mapOf<int>();
    expect(lists.toJson([_value]), [_value]);
    expect(maps.toJson({_key: 1}), {_key: 1});
    final input = <dynamic>[_value];
    final output = lists.fromJson(input);
    input.clear();
    expect(output, [_value]);
    expect(maps.fromJson(<String, dynamic>{_key: 1}), {_key: 1});
    expect(() => lists.fromJson([1]), throwsA(isA<TypeError>()));
    expect(() => maps.fromJson({_key: _value}), throwsA(isA<TypeError>()));
  });

  test('sync failed mutation Future is FlushError without retry', () async {
    final state = _State()
      ..failures = 1
      ..background = true;
    final errors = <Object>[];
    final cache = await _ready(
        false, state, CachemanOptions(onError: (_, e) => errors.add(e)));
    cache.write(_key, _value);
    await Future<void>.delayed(Duration.zero);
    final error = errors.single as FlushError;
    expect(error.cause, same(state.failure));
    expect(error.stackTrace, same(state.trace));
    expect(state.writes, 1);
    expect(state.scans, 0);
  });
}
