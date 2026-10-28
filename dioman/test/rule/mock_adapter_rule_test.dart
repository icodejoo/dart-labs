import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';

import '../support/fake_cache_persist.dart';
import '../support/fixtures.dart'
    show jsonBody, testRetry, testAuth, TestTokens;
import '../support/test_server.dart';

const _slot = DiomanMockAdapter.extraKey;

Future<TestServer> _server(FutureOr<void> Function(HttpRequest) handler) async {
  final server = await TestServer.start(handler);
  addTearDown(server.close);
  return server;
}

Dio _dio(TestServer server,
    {Map<String, MockHandler> routes = const {},
    String? mockUrl,
    bool enabled = true,
    MockFallbackDecider fallbackWhen = defaultFallback}) {
  final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
  dio.httpClientAdapter = DiomanMockAdapter(
      inner: dio.httpClientAdapter,
      routes: routes,
      mockUrl: mockUrl,
      enabled: enabled,
      fallbackWhen: fallbackWhen);
  addTearDown(() => dio.close(force: true));
  return dio;
}

void _marked(Response<dynamic> r, bool marked) => expect(
    r.headers.value(DiomanMockAdapter.markerHeader), marked ? '1' : null);

// Real IO transport with close observation, never a fake transport.
class _ObservedIO extends IOHttpClientAdapter {
  final closed = <bool>[];
  final fetched = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    fetched.add(options);
    return super.fetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {
    closed.add(force);
    super.close(force: force);
  }
}

void main() {
  test(
      '[DiomanMockAdapter.fetch] direct forwarding cancellation never falls back',
      () async {
    final started = Completer<void>();
    final gate = Completer<void>();
    final server = await _server((r) async {
      started.complete();
      await gate.future;
      await respondJson(r, 'mock', 200);
    });
    final inner = _ObservedIO();
    addTearDown(() => inner.close(force: true));
    DioException? seen;
    final adapter = DiomanMockAdapter(
        inner: inner,
        mockUrl: server.baseUrl,
        fallbackWhen: ({response, error}) {
          seen = error;
          return defaultFallback(response: response, error: error);
        });
    final cancel = Completer<void>();
    final future = adapter.fetch(
        RequestOptions(path: '${server.baseUrl}/pets'), null, cancel.future);
    final check = expectLater(
        future,
        throwsA(isA<DioException>()
            .having((e) => e.type, 'type', DioExceptionType.cancel)));
    await started.future;
    cancel.complete();
    await check.timeout(const Duration(seconds: 2));
    gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(seen?.type, DioExceptionType.cancel);
    expect(inner.fetched, hasLength(1));
  });

  test('[DiomanMockAdapter.new(routes)] inline errors never invoke fallback',
      () async {
    var realCalls = 0;
    var decisions = 0;
    final real = await _server((r) => respondJson(r, ++realCalls, 200));
    late DioException expected;
    final dio = _dio(real, mockUrl: real.baseUrl, routes: {
      'GET:/pets': (options) async {
        expected = DioException(requestOptions: options, error: 'inline');
        throw expected;
      }
    }, fallbackWhen: ({response, error}) {
      decisions++;
      return true;
    });
    await expectLater(dio.get<dynamic>('/pets'),
        throwsA(predicate((e) => identical(e, expected))));
    expect(realCalls, 0);
    expect(decisions, 0);
  });

  test(
      '[DiomanMockAdapter.markerHeader] immutable mixed-case headers are normalized',
      () async {
    final real = await _server((r) => respondJson(r, 'real', 200));
    final dio = _dio(real, routes: {
      'GET:/pets': (_) async =>
          ResponseBody.fromString('mock', 200, headers: const {
            'X-Dioman-Mock': ['old'],
            'other': ['kept']
          })
    });
    final r = await dio.get<dynamic>('/pets');
    _marked(r, true);
    expect(r.headers.value('other'), 'kept');
  });

  test('[DiomanMockAdapter.fetch] transport error fallback preserves POST body',
      () async {
    String? received;
    final real = await _server((r) async {
      received = await utf8.decoder.bind(r).join();
      await respondJson(r, 'real', 200);
    });
    final dead = await TestServer.start((r) => respondJson(r, 'unused', 200));
    final url = dead.baseUrl;
    await dead.close();
    final dio = _dio(real, mockUrl: url);
    final r = await dio.post<dynamic>('/pets',
        data: 'complete body', options: Options(contentType: 'text/plain'));
    expect(received, 'complete body');
    _marked(r, false);
  });

  test(
      '[DiomanMockAdapter.fetch] body buffering can be interrupted before forwarding',
      () async {
    var calls = 0;
    final real = await _server((r) => respondJson(r, ++calls, 200));
    final dio = _dio(real, mockUrl: real.baseUrl);
    final stream = StreamController<Uint8List>();
    final cancel = Completer<void>();
    final future = dio.httpClientAdapter.fetch(
        RequestOptions(path: '${real.baseUrl}/pets', method: 'POST'),
        stream.stream,
        cancel.future);
    final check = expectLater(
        future,
        throwsA(isA<DioException>()
            .having((e) => e.type, 'type', DioExceptionType.cancel)));
    stream.add(Uint8List.fromList([1, 2]));
    cancel.complete();
    await check.timeout(const Duration(seconds: 2));
    await stream.close();
    expect(calls, 0);
  });

  test(
      '[DiomanMockAdapter.new(routes)][DiomanMockAdapter.new(inner)][DiomanMockAdapter.fetch] inline match, resolved path and passthrough',
      () async {
    var real = 0;
    final server = await _server((r) => respondJson(r, ++real, 200));
    final dio = _dio(server, routes: {
      'GET:/pets': (_) async => jsonBody(['mock'], 200)
    });
    final mock = await dio.get<dynamic>('${server.baseUrl}/pets?q=1');
    expect(mock.data, ['mock']);
    _marked(mock, true);
    final live = await dio.get<dynamic>('/other');
    expect(live.data, 1);
    _marked(live, false);
    expect(real, 1);
  });

  test(
      '[DiomanMockAdapter.new(mockUrl)] rewrites base path and query exactly once',
      () async {
    final real = await _server((r) => respondJson(r, 'real', 200));
    final mock = await _server((r) => respondJson(r, r.uri.toString(), 200));
    final dio = _dio(real, mockUrl: '${mock.baseUrl}/prefix///');
    final r = await dio.get<dynamic>('/pets', queryParameters: {'q': 'a b'});
    expect(Uri.parse(r.data as String).path, '/prefix/pets');
    expect(Uri.parse(r.data as String).queryParametersAll, {
      'q': ['a b']
    });
    _marked(r, true);
  });

  test(
      '[DiomanMockAdapter.new(fallbackWhen)] default 404 falls back, 500 stays mock',
      () async {
    var realCalls = 0;
    final real = await _server((r) => respondJson(r, ++realCalls, 200));
    final mock = await _server(
        (r) => respondJson(r, 'mock', r.uri.path == '/404' ? 404 : 500));
    final dio = _dio(real, mockUrl: mock.baseUrl);
    final r = await dio.get<dynamic>('/404');
    _marked(r, false);
    await expectLater(
        dio.get<dynamic>('/500'),
        throwsA(isA<DioException>()
            .having(
                (e) =>
                    e.response?.headers.value(DiomanMockAdapter.markerHeader),
                'marker',
                '1')
            .having((e) => e.response?.statusCode, 'status', 500)));
    expect(realCalls, 1);
  });

  test(
      '[DiomanMockAdapter.new(fallbackWhen)][DiomanMockOptions.fallbackWhen] custom response and error decisions',
      () async {
    final real = await _server((r) => respondJson(r, 'real', 200));
    final mock = await _server((r) => respondJson(r, 'mock', 503));
    Response<dynamic>? seen;
    final dio =
        _dio(real, mockUrl: mock.baseUrl, fallbackWhen: ({response, error}) {
      seen = response;
      return response?.statusCode == 503;
    });
    final r = await dio.get<dynamic>('/pets');
    expect(r.data, 'real');
    _marked(r, false);
    expect(seen?.data, isA<ResponseBody>());
    await mock.close();
    DioException? seenError;
    final fallback = await dio.get<dynamic>('/pets',
        options: Options(extra: {
          _slot: DiomanMockOptions(fallbackWhen: ({response, error}) {
            seenError = error;
            return true;
          })
        }));
    expect(fallback.data, 'real');
    expect(seenError, isA<DioException>());
    await expectLater(
        dio.get<dynamic>('/pets',
            options: Options(extra: {
              _slot:
                  DiomanMockOptions(fallbackWhen: ({response, error}) => false)
            })),
        throwsA(isA<DioException>()));
  });

  test(
      '[DiomanMockAdapter.extraKey][DiomanMockAdapter.new(enabled)][DiomanMockOptions.enabled][DiomanMockOptions.routes] enabled, false, routes merge and URL override',
      () async {
    final real = await _server((r) => respondJson(r, 'real', 200));
    final mock = await _server((r) => respondJson(r, 'forwarded', 200));
    final dio = _dio(real, enabled: false, routes: {
      'GET:/pets': (_) async => jsonBody('base', 200),
      'GET:/kept': (_) async => jsonBody('kept', 200),
    });
    expect((await dio.get<dynamic>('/pets')).data, 'real');
    final extra = {
      _slot: DiomanMockOptions(
          enabled: true,
          mockUrl: mock.baseUrl,
          routes: {'GET:/pets': (_) async => jsonBody('override', 200)})
    };
    for (final item in {
      '/pets': 'override',
      '/kept': 'kept',
      '/new': 'forwarded'
    }.entries) {
      final r =
          await dio.get<dynamic>(item.key, options: Options(extra: extra));
      expect(r.data, item.value);
      _marked(r, true);
    }
    final active =
        _dio(real, routes: {'GET:/pets': (_) async => jsonBody('mock', 200)});
    for (final off in [false, const DiomanMockOptions(enabled: false)]) {
      final r = await active.get<dynamic>('/pets',
          options: Options(extra: {_slot: off}));
      expect(r.data, 'real');
      _marked(r, false);
    }
  });

  test('[DiomanMockAdapter.fetch] POST body complete on forward and fallback',
      () async {
    final receivedMock = <String>[];
    final receivedReal = <String>[];
    final real = await _server((r) async {
      receivedReal.add(await utf8.decoder.bind(r).join());
      await respondJson(r, 'real', 200);
    });
    final mock = await _server((r) async {
      receivedMock.add(await utf8.decoder.bind(r).join());
      await respondJson(r, 'mock', r.uri.path == '/fallback' ? 404 : 200);
    });
    final dio = _dio(real, mockUrl: mock.baseUrl);
    final data = List.generate(10000, (i) => '$i中文').join();
    for (final path in ['/forward', '/fallback']) {
      final r = await dio.post<dynamic>(path,
          data: Stream.fromIterable([
            Uint8List.fromList(utf8.encode(data.substring(0, 100))),
            Uint8List.fromList(utf8.encode(data.substring(100))),
          ]),
          options: Options(contentType: 'text/plain'));
      _marked(r, path == '/forward');
    }
    expect(receivedMock, [data, data]);
    expect(receivedReal, [data]);
  });

  test(
      '[DiomanMockAdapter.fetch] inline handler interrupted without completion',
      () async {
    final real = await _server((r) => respondJson(r, 'real', 200));
    final started = Completer<void>();
    final gate = Completer<ResponseBody>();
    final dio = _dio(real, routes: {
      'GET:/pets': (_) {
        started.complete();
        return gate.future;
      }
    });
    final token = CancelToken();
    // Call adapter directly so Dio's outer cancellation cannot hide a hang.
    final future = dio.httpClientAdapter.fetch(
        RequestOptions(path: '${real.baseUrl}/pets', cancelToken: token),
        null,
        token.whenCancel);
    final check = expectLater(
        future,
        throwsA(isA<DioException>()
            .having((e) => e.type, 'type', DioExceptionType.cancel)));
    await started.future;
    token.cancel('stop');
    await check.timeout(const Duration(seconds: 2));
    gate.completeError(StateError('late handler error is consumed'));
  });

  test(
      '[DiomanMockAdapter.fetch] forwards cancellation to inner without fallback',
      () async {
    var realCalls = 0;
    final real = await _server((r) => respondJson(r, ++realCalls, 200));
    final started = Completer<void>();
    final gate = Completer<void>();
    final mock = await _server((r) async {
      started.complete();
      await gate.future;
      await respondJson(r, 'mock', 200);
    });
    final dio = _dio(real, mockUrl: mock.baseUrl);
    final token = CancelToken();
    final future = dio.get<dynamic>('/pets', cancelToken: token);
    final check = expectLater(
        future,
        throwsA(isA<DioException>()
            .having((e) => e.type, 'type', DioExceptionType.cancel)));
    await started.future;
    token.cancel();
    await check.timeout(const Duration(seconds: 2));
    gate.complete();
    expect(realCalls, 0);
  });

  test('[DiomanMockAdapter.close] delegates force to real IO adapter',
      () async {
    final real = await _server((r) => respondJson(r, 'real', 200));
    for (final force in [false, true]) {
      final inner = _ObservedIO();
      final adapter = DiomanMockAdapter(inner: inner);
      final dio = Dio()..httpClientAdapter = adapter;
      expect((await dio.get<dynamic>(real.baseUrl)).data, 'real');
      adapter.close(force: force);
      expect(inner.closed, [force]);
      await expectLater(
          dio.get<dynamic>(real.baseUrl), throwsA(isA<DioException>()));
    }
  });

  for (final policy in [
    DiomanCachePolicy.memo,
    DiomanCachePolicy.persist,
    DiomanCachePolicy.both
  ]) {
    test(
        '[DiomanMockAdapter.fetch] $policy mock on then off uses real, fallback caches',
        () async {
      var realCalls = 0;
      var mockCalls = 0;
      var judges = 0;
      final real = await _server((r) => respondJson(r, ++realCalls, 200));
      final mock = await _server((r) => respondJson(r, 'missing', 404));
      final dio = _dio(real,
          routes: {
            'GET:/pets': (_) async {
              mockCalls++;
              return jsonBody('mock', 200);
            }
          },
          mockUrl: mock.baseUrl);
      final persist = FakeCachePersist();
      final handle = Dioman.install(dio,
          key: const DiomanKey(),
          cache: DiomanCache(
              persist: persist,
              cachePolicy: policy,
              shouldStore: (_) {
                judges++;
                return true;
              }));
      addTearDown(handle.dispose);
      for (var i = 0; i < 2; i++) {
        final r = await dio.get<dynamic>('/pets',
            options: Options(extra: {
              DiomanCache.pluginName: DiomanCacheOptions(shouldStore: (_) {
                judges++;
                return true;
              })
            }));
        _marked(r, true);
      }
      expect(mockCalls, 2);
      expect(judges, 0, reason: 'marker veto precedes both user judges');
      expect(persist.store, isEmpty);
      final live = await dio.get<dynamic>('/pets',
          options: Options(extra: {_slot: false}));
      expect(live.data, 1);
      _marked(live, false);
      expect(
          (await dio.get<dynamic>('/pets',
                  options: Options(extra: {_slot: false})))
              .data,
          1);
      final fallback = await dio.get<dynamic>('/fallback');
      _marked(fallback, false);
      expect((await dio.get<dynamic>('/fallback')).data, 2);
      expect(realCalls, 2);
    });
  }

  test('[DiomanMockAdapter.fetch] forwarded mock marker vetoes cache writes',
      () async {
    var calls = 0;
    final real = await _server((r) => respondJson(r, 'real', 200));
    final mock = await _server((r) => respondJson(r, ++calls, 200));
    final dio = _dio(real, mockUrl: mock.baseUrl);
    final handle = Dioman.install(dio,
        key: const DiomanKey(),
        cache: DiomanCache(
            persist: FakeCachePersist(),
            cachePolicy: DiomanCachePolicy.both,
            shouldStore: (_) => true));
    addTearDown(handle.dispose);
    for (var i = 1; i <= 2; i++) {
      final r = await dio.get<dynamic>('/pets');
      expect(r.data, i);
      _marked(r, true);
    }
    expect(
        (await dio.get<dynamic>('/pets',
                options: Options(extra: {_slot: false})))
            .data,
        'real');
  });

  test('[DiomanMockAdapter.fetch] mock 500 retries hit mock again', () async {
    var realCalls = 0;
    var mockCalls = 0;
    final real = await _server((r) => respondJson(r, ++realCalls, 200));
    final dio = _dio(real, routes: {
      'GET:/pets': (_) async {
        mockCalls++;
        return jsonBody('mock', 500);
      }
    });
    final handle = Dioman.install(dio, retry: testRetry(max: 2));
    addTearDown(handle.dispose);
    await expectLater(
        dio.get<dynamic>('/pets'),
        throwsA(isA<DioException>()
            .having((e) => e.response?.statusCode, 'status', 500)));
    expect(mockCalls, 3);
    expect(realCalls, 0);
  });

  test('[DiomanMockAdapter.fetch] 401 refresh replay passes adapter again',
      () async {
    var calls = 0;
    var realCalls = 0;
    final real = await _server((r) => respondJson(r, ++realCalls, 200));
    final dio = _dio(real, routes: {
      'GET:/pets': (o) async {
        calls++;
        return jsonBody(o.headers['Authorization'], calls == 1 ? 401 : 200);
      }
    });
    final handle = Dioman.install(dio, auth: testAuth(TestTokens('old')));
    addTearDown(handle.dispose);
    final r = await dio.get<dynamic>('/pets');
    expect(r.data, 'Bearer t1');
    _marked(r, true);
    expect(calls, 2);
    expect(realCalls, 0);
  });

  test('[DiomanMockAdapter.fetch] concurrent identical mock requests merge',
      () async {
    var calls = 0;
    final real = await _server((r) => respondJson(r, 'real', 200));
    final started = Completer<void>();
    final gate = Completer<void>();
    final dio = _dio(real, routes: {
      'GET:/pets': (_) async {
        calls++;
        started.complete();
        await gate.future;
        return jsonBody('mock', 200);
      }
    });
    final handle =
        Dioman.install(dio, key: const DiomanKey(), share: DiomanShare());
    addTearDown(handle.dispose);
    final requests = List.generate(3, (_) => dio.get<dynamic>('/pets'));
    await started.future;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    gate.complete();
    for (final r in await Future.wait(requests)) {
      expect(r.data, 'mock');
      _marked(r, true);
    }
    expect(calls, 1);
  });

  test('[defaultFallback] 404 或非取消错误回落；取消、其它状态码、全空都不回落', () {
    final opts = RequestOptions(path: '/x');
    Response<dynamic> status(int code) =>
        Response<dynamic>(requestOptions: opts, statusCode: code);
    expect(defaultFallback(response: status(404)), isTrue);
    expect(defaultFallback(response: status(200)), isFalse);
    expect(defaultFallback(response: status(500)), isFalse);
    expect(
        defaultFallback(
            error: DioException(
                requestOptions: opts, type: DioExceptionType.connectionError)),
        isTrue);
    expect(
        defaultFallback(
            error: DioException(
                requestOptions: opts, type: DioExceptionType.cancel)),
        isFalse);
    expect(defaultFallback(), isFalse);
    // 只传 error 时，连 badResponse(500) 也算"非取消错误"而回落；
    // 两者同时给出以 response 为准。
    final badResponse = DioException(
        requestOptions: opts,
        response: status(500),
        type: DioExceptionType.badResponse);
    expect(defaultFallback(error: badResponse), isTrue);
    expect(defaultFallback(response: status(500), error: badResponse), isFalse);
  });

  test(
      '[DiomanMockAdapter.extraKey][DiomanMockOptions][DiomanExtraKeys.mockAdapterOwner] 键常量与默认值',
      () {
    expect(DiomanMockAdapter.extraKey, 'dioman:mock');
    expect(DiomanExtraKeys.lookup(DiomanMockAdapter.extraKey)?.owner,
        DiomanExtraKeys.mockAdapterOwner);
    const o = DiomanMockOptions();
    expect(
        [o.enabled, o.mockUrl, o.routes, o.fallbackWhen], everyElement(isNull));
  });

  test(
      '[DiomanMockAdapter.new(mockUrl)][DiomanMockOptions.mockUrl] 默认转发地址被继承，单请求地址只覆盖那一次',
      () async {
    final real = await _server((r) => respondJson(r, 'real', 200));
    final primary = await _server((r) => respondJson(r, 'primary', 200));
    final override = await _server((r) => respondJson(r, 'override', 200));
    final dio = _dio(real, mockUrl: primary.baseUrl);
    final extra = {_slot: DiomanMockOptions(mockUrl: override.baseUrl)};
    expect((await dio.get<dynamic>('/pets')).data, 'primary');
    expect(
        (await dio.get<dynamic>('/pets', options: Options(extra: extra))).data,
        'override');
    expect((await dio.get<dynamic>('/pets')).data, 'primary');
  });

  test(
      '[DiomanMockAdapter.new(routes)] 内联处理器抛普通异常：被 Dio 包成 DioException，不回落、只失败一次',
      () async {
    var realCalls = 0;
    var decisions = 0;
    final real = await _server((r) => respondJson(r, ++realCalls, 200));
    final dio = _dio(real, mockUrl: real.baseUrl, routes: {
      'GET:/pets': (_) async => throw StateError('mock failure'),
    }, fallbackWhen: ({response, error}) {
      decisions++;
      return true;
    });
    await expectLater(
        dio.get<dynamic>('/pets'),
        throwsA(isA<DioException>()
            .having((e) => e.error, 'error', isA<StateError>())));
    expect(realCalls, 0);
    expect(decisions, 0);
  });

  test('[DiomanMockAdapter.close] 强制关闭会中止在途的 mock 转发', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final mock = await _server((r) async {
      if (!entered.isCompleted) entered.complete();
      await release.future;
      await respondJson(r, 'mock', 200);
    });
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    final dio = _dio(mock,
        mockUrl: mock.baseUrl, fallbackWhen: ({response, error}) => false);
    final pending = dio.get<dynamic>('/pets');
    final failed = expectLater(pending, throwsA(isA<DioException>()));
    await entered.future.timeout(const Duration(seconds: 2));
    dio.httpClientAdapter.close(force: true);
    await failed.timeout(const Duration(seconds: 2));
  });

  test(
      '[DiomanMockAdapter.new(fallbackWhen)][DiomanMockAdapter.fetch] 转发时传输层抛普通异常：包装成 DioException 交给 fallbackWhen，回落后拿到真实响应',
      () async {
    final inner = _PlainErrorThenOk();
    DioException? judged;
    final dio = Dio(BaseOptions(baseUrl: 'http://real.invalid'))
      ..httpClientAdapter = DiomanMockAdapter(
          inner: inner,
          mockUrl: 'http://mock.invalid',
          fallbackWhen: ({response, error}) {
            judged = error;
            return error != null;
          });
    final r = await dio.get<dynamic>('/pets');
    expect(r.data, {'from': 'real'});
    expect(r.headers.value(DiomanMockAdapter.markerHeader), isNull,
        reason: '回落拿到的是真实响应，不带 mock 标记');
    expect(judged, isA<DioException>());
    expect(judged!.error, isA<StateError>(), reason: '原始异常保留在 error 里');
    expect(
        inner.seen, ['http://mock.invalid/pets', 'http://real.invalid/pets']);
  });
}

/// 转发阶段抛普通异常（非 DioException）、回落阶段正常返回的传输层替身。
class _PlainErrorThenOk implements HttpClientAdapter {
  /// 记录每次到达的请求地址。
  final seen = <String>[];

  /// 第一次（转发到 mock 服务）抛 StateError，之后返回 200。
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    seen.add(options.uri.toString());
    if (seen.length == 1) throw StateError('plain transport failure');
    return ResponseBody.fromString('{"from":"real"}', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  /// 无资源可释放。
  @override
  void close({bool force = false}) {}
}
