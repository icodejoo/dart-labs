import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dioman/src/breaker_plugin.dart';
import 'package:dioman/src/cache_plugin.dart';
import 'package:dioman/src/filter_plugin.dart';
import 'package:dioman/src/key_plugin.dart';
import 'package:dioman/src/loading_plugin.dart';
import 'package:dioman/src/mock_plugin.dart';
import 'package:dioman/src/offline_plugin.dart';
import 'package:dioman/src/repath_plugin.dart';
import 'package:dioman/src/share_plugin.dart';
import 'package:test/test.dart';

/// 测试请求路径。
const _path = '/leaf';

/// 测试缓存键。
const _key = 'leaf-key';

/// 持久化失败信息。
const _persistFailure = 'persist failure';

/// 测试路由键。
const _route = 'GET:$_path';

/// 第二个字段名。
const _secondField = 'b';

/// 第一个字段名。
const _firstField = 'a';

/// 保留字段名。
const _keepField = 'keep';

/// 测试查询值。
const _queryValue = '1';

/// 嵌套字段名。
const _nestedField = 'nested';

/// 数值字段名。
const _valueField = 'value';

/// 写入操作标记。
const _writeOperation = 'write';

/// 清空操作标记。
const _eraseOperation = 'erase';

/// 查询字段名。
const _queryField = 'q';

/// 持久化负载字段。
const _dataField = 'data';

/// 持久化过期字段。
const _expiryField = 'expiresAt';

/// 账号 A 的非敏感缓存作用域。
const _accountA = 'account-a';

/// 账号 B 的非敏感缓存作用域。
const _accountB = 'account-b';

/// 异步隔离用例的最大等待时间。
const _namespaceTimeout = Duration(seconds: 2);

/// 旧深度键中的空查询编码。
const _emptyQueryKey = '{}';

/// 生成指定插件和单请求配置对应的键。
String _namespacedKey(DiomanKey plugin, {DiomanKeyOptions? override}) {
  final options = RequestOptions(
      path: _path,
      extra: {if (override != null) DiomanKey.pluginName: override});
  final handler = _RequestHandler();
  plugin.onRequest(options, handler);
  expect(handler.calls, 1);
  return options.extra[kKey] as String;
}

/// 等待异步入口完成。
Future<void> _pump() => Future<void>.delayed(Duration.zero);

/// 记录出口并检测重复完成。
class _RequestHandler extends RequestInterceptorHandler {
  /// 完成次数。
  int calls = 0;

  /// 缓存响应。
  Response<dynamic>? response;

  /// 拒绝异常。
  DioException? error;

  /// 记录请求放行。
  @override
  void next(RequestOptions options) {
    calls++;
  }

  /// 记录短路响应。
  @override
  void resolve(Response response,
      [bool callFollowingResponseInterceptor = false]) {
    calls++;
    this.response = response;
  }

  /// 记录错误出口。
  @override
  void reject(DioException error,
      [bool callFollowingErrorInterceptor = false]) {
    calls++;
    this.error = error;
  }
}

/// 不创建带错误的未观察 Future 的错误出口。
class _ErrorHandler extends ErrorInterceptorHandler {
  /// 消费错误出口。
  @override
  void next(DioException error) {}
}

/// 记录响应阶段的唯一出口。
class _ResponseHandler extends ResponseInterceptorHandler {
  /// 完成次数。
  int calls = 0;

  /// 持久化错误。
  DioException? error;

  /// 记录响应放行。
  @override
  void next(Response response) {
    calls++;
  }

  /// 记录错误出口。
  @override
  void reject(DioException error,
      [bool callFollowingErrorInterceptor = false]) {
    calls++;
    this.error = error;
  }
}

/// 可控持久化读取及失败。
class _Persist implements DiomanCachePersist {
  /// 可观察的持久化条目。
  final store = <String, dynamic>{};

  /// 待完成的读取。
  Completer<dynamic>? readGate;

  /// 读取次数。
  int reads = 0;

  /// 操作失败开关。
  bool fails = false;

  /// 写入闸门。
  Completer<void>? writeGate;

  /// 持久化调用顺序。
  final operations = <String>[];

  /// 返回受控读取结果。
  @override
  Future<dynamic> read(String key) async {
    reads++;
    if (fails) throw StateError(_persistFailure);
    return readGate == null ? store[key] : readGate!.future;
  }

  /// 等待写入闸门后持久化。
  @override
  Future<void> write(String key, Map<String, dynamic> value) async {
    operations.add(_writeOperation);
    await writeGate?.future;
    if (fails) throw StateError(_persistFailure);
    store[key] = value;
  }

  /// 记录删除并报告失败。
  @override
  Future<void> remove(String key) async {
    operations.add('remove');
    if (fails) throw StateError(_persistFailure);
    store.remove(key);
  }

  /// 记录清空并报告失败。
  @override
  Future<void> erase() async {
    operations.add(_eraseOperation);
    if (fails) throw StateError(_persistFailure);
    store.clear();
  }
}

/// 按调用序号卡住读取的持久化：第 n 次读取可由 [gates] 里对应的闸门控制。
class _GatedPersist extends _Persist {
  /// 读取序号（从 1 起）到闸门的映射，没有闸门的读取直接返回。
  final gates = <int, Completer<dynamic>>{};

  /// 返回受控读取结果。
  @override
  Future<dynamic> read(String key) {
    final n = ++reads;
    if (fails) return Future<dynamic>.error(StateError(_persistFailure));
    return gates[n]?.future ?? Future<dynamic>.value(store[key]);
  }
}

/// 创建带缓存协议键的请求。
RequestOptions _options([String key = _key]) =>
    RequestOptions(path: _path, extra: {kKey: key});

/// 生成请求键。
String _requestKey(RequestOptions options) {
  const DiomanKey().onRequest(options, _RequestHandler());
  return options.extra[kKey] as String;
}

/// 定向回归用例。
void main() {
  group('key namespace', () {
    test('isolates every key source and evaluates namespace once per key', () {
      for (final fastMode in [false, true]) {
        for (final override in [
          null,
          const DiomanKeyOptions(key: _key),
          DiomanKeyOptions(builder: (_) => _key),
        ]) {
          var account = _accountA;
          var calls = 0;
          final plugin = DiomanKey(
              fastMode: fastMode,
              namespace: () {
                calls++;
                return account;
              });
          final first = _namespacedKey(plugin, override: override);
          expect(_namespacedKey(plugin, override: override), first);
          account = _accountB;
          expect(_namespacedKey(plugin, override: override), isNot(first));
          expect(calls, 3);
        }
      }
      final first = _namespacedKey(DiomanKey(namespace: () => _accountA));
      expect(jsonDecode(first), [_route, _emptyQueryKey, null, _accountA]);
      expect(_namespacedKey(DiomanKey(namespace: () => '["$_accountA",null]')),
          isNot(first));
    });

    test('absent null and empty namespaces preserve exact legacy keys', () {
      for (final fastMode in [false, true]) {
        final legacy =
            fastMode ? _route : jsonEncode([_route, _emptyQueryKey, null]);
        expect(_namespacedKey(DiomanKey(fastMode: fastMode)), legacy);
        for (final namespace in [null, '']) {
          final plugin =
              DiomanKey(fastMode: fastMode, namespace: () => namespace);
          expect(_namespacedKey(plugin), legacy);
          expect(
              _namespacedKey(plugin,
                  override: const DiomanKeyOptions(key: _key)),
              _key);
          expect(
              _namespacedKey(plugin,
                  override: DiomanKeyOptions(builder: (_) => _key)),
              _key);
        }
      }
    });

    test('same account hits cache and account switches retain isolated entries',
        () async {
      for (final policy in [
        DiomanCachePolicy.memo,
        DiomanCachePolicy.persist,
        DiomanCachePolicy.both,
      ]) {
        var account = _accountA;
        var networkCalls = 0;
        final dio = Dio();
        addTearDown(dio.close);
        dio.interceptors.addAll([
          DiomanKey(namespace: () => account),
          DiomanCache(persist: _Persist(), cachePolicy: policy),
          InterceptorsWrapper(onRequest: (options, handler) {
            networkCalls++;
            handler.resolve(
                Response(
                    requestOptions: options, statusCode: 200, data: account),
                true);
          }),
        ]);
        expect((await dio.get<String>(_path)).data, _accountA);
        expect((await dio.get<String>(_path)).data, _accountA);
        expect(networkCalls, 1);
        account = _accountB;
        expect((await dio.get<String>(_path)).data, _accountB);
        expect((await dio.get<String>(_path)).data, _accountB);
        expect(networkCalls, 2);
        account = _accountA;
        expect((await dio.get<String>(_path)).data, _accountA);
        expect(networkCalls, 2);
      }
    });

    test('account switch does not join another accounts in-flight share',
        () async {
      var account = _accountA;
      final enteredA = Completer<void>();
      final enteredB = Completer<void>();
      final gateA = Completer<void>();
      final gateB = Completer<void>();
      final dio = Dio();
      addTearDown(() {
        if (!gateA.isCompleted) gateA.complete();
        if (!gateB.isCompleted) gateB.complete();
        dio.close();
      });
      dio.interceptors.addAll([
        DiomanKey(namespace: () => account),
        DiomanShare(),
        InterceptorsWrapper(onRequest: (options, handler) async {
          final owner = account;
          (owner == _accountA ? enteredA : enteredB).complete();
          await (owner == _accountA ? gateA : gateB).future;
          handler.resolve(
              Response(requestOptions: options, statusCode: 200, data: owner),
              true);
        }),
      ]);
      final first = dio.get<String>(_path);
      await enteredA.future.timeout(_namespaceTimeout);
      account = _accountB;
      final second = dio.get<String>(_path);
      await enteredB.future.timeout(_namespaceTimeout);
      gateB.complete();
      expect((await second.timeout(_namespaceTimeout)).data, _accountB);
      gateA.complete();
      expect((await first.timeout(_namespaceTimeout)).data, _accountA);
    });

    test('namespace failures reject once and reach Dio without hanging',
        () async {
      final cause = StateError(_accountA);
      final plugin = DiomanKey(namespace: () => throw cause);
      final handler = _RequestHandler();
      plugin.onRequest(_options(), handler);
      expect(handler.calls, 1);
      expect(handler.error?.error, same(cause));
      expect(handler.error?.stackTrace, isNotNull);
      final dio = Dio()..interceptors.add(plugin);
      addTearDown(dio.close);
      await expectLater(
          dio.get<dynamic>(_path).timeout(_namespaceTimeout),
          throwsA(isA<DioException>()
              .having((error) => error.error, 'cause', same(cause))));
    });

    test('disabled requests do not evaluate namespace', () {
      final plugin = DiomanKey(namespace: () => throw StateError(_accountA));
      final options = _options()
        ..extra[DiomanKey.pluginName] = const DiomanKeyOptions(enabled: false);
      final handler = _RequestHandler();
      plugin.onRequest(options, handler);
      expect(handler.calls, 1);
      expect(handler.error, isNull);
    });
  });

  test('persistence errors reach Dio caller and release loading bracket',
      () async {
    final persist = _Persist();
    final loading = DiomanLoading(onChanged: (_) {});
    final dio = Dio();
    addTearDown(dio.close);
    dio.interceptors.addAll([
      const DiomanKey(),
      DiomanCache(persist: persist, cachePolicy: DiomanCachePolicy.persist),
      loading,
      InterceptorsWrapper(onRequest: (options, handler) {
        persist.fails = true;
        handler.resolve(
            Response(requestOptions: options, statusCode: 200, data: 1), true);
      }),
    ]);
    await expectLater(
        dio.get<dynamic>(_path),
        throwsA(isA<DioException>()
            .having((error) => error.error, 'cause', isA<StateError>())));
    expect(loading.activeCount, 0);
  });

  test('remove invalidates pending reads and clear invalidates old responses',
      () async {
    final persist = _Persist()..readGate = Completer<dynamic>();
    final cache =
        DiomanCache(persist: persist, cachePolicy: DiomanCachePolicy.both);
    final pending = _RequestHandler();
    cache.onRequest(_options(), pending);
    await _pump();
    await cache.remove(_key);
    persist.readGate!.complete({
      _dataField: 'stale',
      _expiryField: DateTime.now().millisecondsSinceEpoch + 60000
    });
    await _pump();
    expect(pending.response, isNull);
    expect(pending.calls, 1);
    persist.readGate = null;
    final options = _options();
    cache.onRequest(options, _RequestHandler());
    await _pump();
    await cache.clear();
    cache.onResponse(
        Response(requestOptions: options, statusCode: 200, data: 1),
        _ResponseHandler());
    await _pump();
    expect(persist.store, isEmpty);
    final next = _RequestHandler();
    cache.onRequest(_options(), next);
    await _pump();
    expect(next.response, isNull);
  });

  test('none cache skips decisions and bookkeeping', () async {
    final cache = DiomanCache(
        persist: _Persist(),
        shouldCache: (_) => throw StateError('must not run'));
    final options = _options();
    final handler = _RequestHandler();
    cache.onRequest(options, handler);
    await _pump();
    expect(handler.calls, 1);
    expect(handler.error, isNull);
    expect(options.extra, {kKey: _key});
  });

  test('key preserves opaque body identity and merges embedded queries', () {
    final body = Object();
    final first = RequestOptions(
        path: 'https://example.com/leaf?a=1',
        queryParameters: {_secondField: 2},
        data: body);
    final second =
        RequestOptions(path: 'https://example.com/leaf?b=2&a=1', data: body);
    expect(_requestKey(first), _requestKey(second));
    second.data = Object();
    expect(_requestKey(first), isNot(_requestKey(second)));
  });

  test(
      'cache write failure rejects response once and management failures await',
      () async {
    final persist = _Persist();
    final cache =
        DiomanCache(persist: persist, cachePolicy: DiomanCachePolicy.persist);
    final options = _options();
    cache.onRequest(options, _RequestHandler());
    await _pump();
    persist.fails = true;
    final handler = _ResponseHandler();
    cache.onResponse(
        Response(requestOptions: options, data: 1, statusCode: 200), handler);
    await _pump();
    expect(handler.calls, 1);
    expect(handler.error?.error, isA<StateError>());
    await expectLater(Future<void>.sync(cache.clear), throwsStateError);
    await expectLater(
        Future<void>.sync(() => cache.remove(_key)), throwsStateError);
  });

  test('clear waits for pending write and erases afterwards', () async {
    final persist = _Persist()..writeGate = Completer<void>();
    final cache =
        DiomanCache(persist: persist, cachePolicy: DiomanCachePolicy.persist);
    final options = _options();
    cache.onRequest(options, _RequestHandler());
    await _pump();
    final handler = _ResponseHandler();
    cache.onResponse(
        Response(requestOptions: options, data: 1, statusCode: 200), handler);
    await _pump();
    var cleared = false;
    final clear = Future<void>.sync(cache.clear).then((_) => cleared = true);
    await _pump();
    expect(cleared, isFalse);
    expect(handler.calls, 0);
    persist.writeGate!.complete();
    await clear;
    await _pump();
    expect(persist.operations, [_writeOperation, _eraseOperation]);
    expect(persist.store, isEmpty);
    expect(handler.calls, 1);
  });

  test('stale breaker probe cannot close or consume a new window', () {
    final breaker = DiomanBreaker(
        failureThreshold: 1, resetDuration: Duration.zero, halfOpenMaxCalls: 2);

    /// 记录一次依赖失败。
    void fail(RequestOptions options) => breaker.onError(
        DioException(
            requestOptions: options, type: DioExceptionType.connectionError),
        _ErrorHandler());
    final initial = _options();
    breaker.onRequest(initial, _RequestHandler());
    fail(initial);
    final old = _options();
    final failingProbe = _options();
    breaker.onRequest(old, _RequestHandler());
    breaker.onRequest(failingProbe, _RequestHandler());
    fail(failingProbe);
    final fresh = _options();
    breaker.onRequest(fresh, _RequestHandler());
    breaker.onResponse(Response(requestOptions: old), _ResponseHandler());
    expect(breaker.stateOf(_route), DiomanBreakerState.halfOpen);
    breaker.onError(
        DioException(requestOptions: old, type: DioExceptionType.cancel),
        _ErrorHandler());
    breaker.onRequest(_options(), _RequestHandler());
    expect(breaker.isOpen(_options()), isTrue);
    breaker.onResponse(Response(requestOptions: fresh), _ResponseHandler());
    expect(breaker.stateOf(_route), DiomanBreakerState.closed);
  });

  test('offline flush checks cancellation before cancellation listener runs',
      () {
    final offline = DiomanOffline(
        isOnline: () => false,
        onConnectivityChanged: const Stream<bool>.empty());
    final token = CancelToken();
    final handler = _RequestHandler();
    offline.onRequest(RequestOptions(path: _path, cancelToken: token), handler);
    token.cancel();
    offline.flush();
    expect(handler.calls, 1);
    expect(handler.error?.type, DioExceptionType.cancel);
    offline.dispose();
  });

  test('loading callback stays paired across delayed hide and disposal',
      () async {
    final states = <bool>[];
    final own = <bool>[];
    final loading = DiomanLoading(
        onChanged: states.add, delayClose: const Duration(hours: 1));
    final first = _options();
    loading.onRequest(first, _RequestHandler());
    loading.onResponse(Response(requestOptions: first), _ResponseHandler());
    final second = _options()
      ..extra[DiomanLoading.pluginName] =
          DiomanLoadingOptions(onChanged: own.add);
    loading.onRequest(second, _RequestHandler());
    loading.dispose();
    loading.dispose();
    expect(states, [true, false]);
    expect(own, isEmpty);
  });

  test('key includes origin, URL query and separate query/body fields', () {
    /// 构造同一请求的不同字段。
    RequestOptions request(String url,
            {Map<String, dynamic>? query, dynamic data}) =>
        RequestOptions(path: url, queryParameters: query, data: data);
    const url = 'https://a.example/leaf';
    expect(_requestKey(request(url)),
        isNot(_requestKey(request('https://b.example/leaf'))));
    expect(_requestKey(request('$url?q=1')),
        isNot(_requestKey(request('$url?q=2'))));
    expect(
        _requestKey(request('$url?b=2&a=1')),
        _requestKey(request(url,
            query: {_firstField: _queryValue, _secondField: '2'})));
    expect(_requestKey(request(url, query: {_queryField: _queryValue})),
        isNot(_requestKey(request(url, data: {_queryField: _queryValue}))));
  });

  test('repath snapshots repeated placeholders and encodes segments', () {
    const value = 'a/b?#';
    final options = RequestOptions(
        path: '/{id}/{id}', data: const {'id': value, _keepField: 1});
    DiomanRepath().onRequest(options, _RequestHandler());
    final encoded = Uri.encodeComponent(value);
    expect(options.path, '/$encoded/$encoded');
    expect(options.data, {_keepField: 1});
  });

  test('filter copies immutable body', () {
    const body = {'empty': '', _keepField: 1};
    final options = RequestOptions(path: _path, data: body);
    const DiomanFilter().onRequest(options, _RequestHandler());
    expect(options.data, {_keepField: 1});
    expect(body.length, 2);
  });

  test('mock ordinary failure rejects once', () async {
    final mock = DiomanMock(
        enabled: true,
        routes: {_route: (_) async => throw StateError('mock failure')});
    final handler = _RequestHandler();
    mock.onRequest(_options(), handler);
    await _pump();
    expect(handler.calls, 1);
    expect(handler.error?.error, isA<StateError>());
  });

  test('cache read failure rejects once', () async {
    final cache = DiomanCache(
        persist: _Persist()..fails = true, cachePolicy: DiomanCachePolicy.both);
    final handler = _RequestHandler();
    cache.onRequest(_options(), handler);
    await _pump();
    expect(handler.calls, 1);
    expect(handler.error?.error, isA<StateError>());
  });

  test('cache deep clone isolates first response', () async {
    final cache = DiomanCache(
        persist: _Persist(),
        cachePolicy: DiomanCachePolicy.memo,
        clone: DiomanClonePolicy.deep);
    final options = _options();
    cache.onRequest(options, _RequestHandler());
    await _pump();
    final data = {
      _nestedField: {_valueField: 1}
    };
    cache.onResponse(
        Response(requestOptions: options, data: data, statusCode: 200),
        ResponseInterceptorHandler());
    data[_nestedField]![_valueField] = 2;
    final handler = _RequestHandler();
    cache.onRequest(_options(), handler);
    await _pump();
    expect(handler.response?.data, {
      _nestedField: {_valueField: 1}
    });
  });

  test('cache persistent hydration respects memory capacity', () async {
    final persist = _Persist();
    final expiry = DateTime.now().millisecondsSinceEpoch + 60000;
    for (final key in [_firstField, _secondField]) {
      persist.store[key] = {_dataField: key, _expiryField: expiry};
    }
    final cache = DiomanCache(
        persist: persist, cachePolicy: DiomanCachePolicy.both, maxEntries: 1);
    for (final key in [_firstField, _secondField, _firstField]) {
      cache.onRequest(_options(key), _RequestHandler());
      await _pump();
    }
    expect(persist.reads, 3);
  });

  test('clear prevents old read from repopulating memory', () async {
    final persist = _Persist()..readGate = Completer<dynamic>();
    final cache =
        DiomanCache(persist: persist, cachePolicy: DiomanCachePolicy.both);
    final first = _RequestHandler();
    cache.onRequest(_options(), first);
    cache.clear();
    persist.readGate!.complete({
      _dataField: 'old',
      _expiryField: DateTime.now().millisecondsSinceEpoch + 60000
    });
    await _pump();
    persist.readGate = null;
    final second = _RequestHandler();
    cache.onRequest(_options(), second);
    await _pump();
    expect(second.response, isNull);
    expect(persist.reads, 2);
  });

  test('offline cancellation immediately removes queued request', () async {
    final offline = DiomanOffline(
        isOnline: () => false,
        onConnectivityChanged: const Stream<bool>.empty(),
        maxWait: const Duration(hours: 1));
    final token = CancelToken();
    final handler = _RequestHandler();
    offline.onRequest(RequestOptions(path: _path, cancelToken: token), handler);
    expect(offline.pending, 1);
    token.cancel();
    await _pump();
    expect(offline.pending, 0);
    expect(handler.error?.type, DioExceptionType.cancel);
    offline.flush();
    offline.dispose();
    expect(handler.calls, 1);
  });

  test('breaker cancellation returns half-open slot', () {
    final breaker = DiomanBreaker(
        failureThreshold: 1, resetDuration: Duration.zero, halfOpenMaxCalls: 1);
    final failed = _options();
    breaker.onRequest(failed, _RequestHandler());
    breaker.onError(
        DioException(
            requestOptions: failed, type: DioExceptionType.connectionError),
        _ErrorHandler());
    final probe = _options();
    breaker.onRequest(probe, _RequestHandler());
    breaker.onError(
        DioException(requestOptions: probe, type: DioExceptionType.cancel),
        _ErrorHandler());
    expect(breaker.isOpen(_options()), isFalse);
  });

  test('loading closes using callback that opened display cycle', () {
    final states = <bool>[];
    final own = <bool>[];
    final loading = DiomanLoading(onChanged: states.add);
    final first = _options();
    final second = _options()
      ..extra[DiomanLoading.pluginName] =
          DiomanLoadingOptions(onChanged: own.add);
    loading.onRequest(first, _RequestHandler());
    loading.onRequest(second, _RequestHandler());
    for (final options in [first, second]) {
      loading.onResponse(
          Response(requestOptions: options), ResponseInterceptorHandler());
    }
    expect(states, [true, false]);
    expect(own, isEmpty);
  });

  test('slow read of an expired entry cannot delete a fresher same-key entry',
      () async {
    final persist = _GatedPersist()..gates[1] = Completer<dynamic>();
    final now = DateTime.now().millisecondsSinceEpoch;
    final expired = {_dataField: 'old', _expiryField: now - 1000};
    persist.store[_key] = expired;
    final cache =
        DiomanCache(persist: persist, cachePolicy: DiomanCachePolicy.both);

    // A：持久化读取被卡住。
    final optionsA = _options();
    final handlerA = _RequestHandler();
    cache.onRequest(optionsA, handlerA);
    await _pump();
    // B：读到同一个过期条目，清理后走网络并写入新缓存。
    final optionsB = _options();
    final handlerB = _RequestHandler();
    cache.onRequest(optionsB, handlerB);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(handlerB.calls, 1, reason: 'B 未命中，放行到网络');
    cache.onResponse(
        Response(requestOptions: optionsB, statusCode: 200, data: 'new'),
        _ResponseHandler());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect((persist.store[_key] as Map)[_dataField], 'new');

    // A 的慢读取此刻才带着旧的过期条目返回。
    persist.gates[1]!.complete(expired);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(handlerA.calls, 1);

    expect((persist.store[_key] as Map)[_dataField], 'new',
        reason: '持久化里的新条目不能被 A 的过期清理删掉');
    final hit = _RequestHandler();
    cache.onRequest(_options(), hit);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(hit.response?.data, 'new', reason: '内存里的新条目也还在');
  });
}
