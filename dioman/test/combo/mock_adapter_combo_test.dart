// 组合层：DiomanMockAdapter 与 normalize / share / offline / retry 的配合
// （adapter 在传输层，位于整条拦截器链之下）
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart'
    show jsonBody, testRetry, retryBusinessFailure;
import '../support/test_server.dart';

/// 被请求的路径，同时是内联 mock 的路径部分。
const _path = '/data';

/// [_path] 对应的内联 mock 路由键。
const _route = 'GET:$_path';

/// 另一条只走内联 mock 的路径，用于离线用例。
const _localPath = '/local';

/// [_localPath] 对应的路由键。
const _localRoute = 'GET:$_localPath';

/// 响应体里区分来源的字段名。
const _field = 'v';

/// mock 给出的标记值。
const _mocked = 'mocked';

/// 真实服务给出的标记值。
const _real = 'real';

/// 并发用例的请求数。
const _burst = 4;

/// 重试次数上限，足够大才能暴露"被多次重放"。
const _maxRetries = 2;

/// 服务端错误状态码。
const _serverError = 500;

/// 成功状态码。
const _ok = 200;

/// 找不到资源的状态码，默认触发回落。
const _notFound = 404;

/// 等待超时，防止回归时用例挂死。
const _wait = Duration(seconds: 3);

/// 带调用计数的回环服务：第 n 次请求按 [reply] 给出的状态与 body 回复。
class _Counted {
  _Counted._(this.server);

  /// 底层真实 HTTP 服务。
  final TestServer server;

  /// 已收到的请求数。
  int calls = 0;

  /// 启动服务，第 n 次（从 1 开始）请求的回复由 [reply] 决定，可选延迟 [delay]。
  static Future<_Counted> start(
      ({int status, Object body}) Function(int n) reply,
      {Duration delay = Duration.zero}) async {
    late _Counted counted;
    final server = await TestServer.start((req) async {
      final r = reply(++counted.calls);
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      await respondJson(req, r.body, r.status);
    });
    counted = _Counted._(server);
    addTearDown(server.close);
    return counted;
  }

  /// 启动一个固定回复 [status]/[body] 的服务。
  static Future<_Counted> fixed(int status, Object body,
          {Duration delay = Duration.zero}) =>
      start((_) => (status: status, body: body), delay: delay);

  /// 服务根地址。
  String get baseUrl => server.baseUrl;
}

/// 返回 `{v: tag}` 的内联 mock 处理器，可选 [gate] 卡住与 [hit] 计数。
MockHandler _inline(String tag,
        {Completer<void>? gate, void Function()? hit}) =>
    (options) async {
      hit?.call();
      if (gate != null) await gate.future;
      return jsonBody({_field: tag}, _ok);
    };

/// 装好 adapter 的宿主 [Dio]，指向 [baseUrl]；用例结束自动关闭。
Dio _dio(String baseUrl,
    {Map<String, MockHandler> routes = const {}, String? mockUrl}) {
  final dio = Dio(BaseOptions(baseUrl: baseUrl));
  dio.httpClientAdapter = DiomanMockAdapter(
      inner: dio.httpClientAdapter, routes: routes, mockUrl: mockUrl);
  addTearDown(() => dio.close(force: true));
  return dio;
}

/// 发请求，成功返回 [Response]，抛错则把异常当结果返回，便于统一断言。
Future<Object> _call(Dio dio) =>
    dio.get<dynamic>(_path).then<Object>((r) => r, onError: (Object e) => e);

/// 注册本文件的组合层用例。
void main() {
  group('adapter × normalize / share', () {
    test(
        '[DiomanMockAdapter.new(routes) × DiomanNormalize.onResponse] mock 命中的信封照常被 normalize 解包，'
        '并发 follower 由 share 合并、不悬挂', () async {
      final real = await _Counted.fixed(_ok, {'should': 'not be called'});
      var hits = 0;
      final dio = _dio(real.baseUrl, routes: {
        'GET:/mocked': (_) async {
          hits++;
          return ResponseBody.fromString(
              jsonEncode({
                'code': 0,
                'data': {'x': 1},
                'message': 'ok'
              }),
              _ok,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              });
        }
      });
      final handle = Dioman.install(dio,
          key: const DiomanKey(),
          share: DiomanShare(),
          normalize: const DiomanNormalize());
      addTearDown(handle.dispose);

      final results = await Future.wait([
        dio.get<Map<String, dynamic>>('/mocked'),
        dio.get<Map<String, dynamic>>('/mocked'),
      ]).timeout(_wait);

      for (final r in results) {
        expect(r.data, {'x': 1}, reason: 'normalize 必须像对真实响应一样解包 mock 信封');
        expect(r.headers.value(DiomanMockAdapter.markerHeader), '1');
      }
      expect(hits, 1, reason: 'adapter 在 share 之下，并发请求合并成一次命中');
      expect(real.calls, 0);
    });

    test(
        '[DiomanMockAdapter.new(fallbackWhen) × DiomanShare] 并发请求在 share 层先合并，只发一次 mock 探测，'
        '回落后只打一次真实服务', () async {
      final real = await _Counted.fixed(_ok, {_field: _real},
          delay: const Duration(milliseconds: 60));
      final mockServer = await _Counted.fixed(_notFound, {_field: _mocked},
          delay: const Duration(milliseconds: 10));
      final dio = _dio(real.baseUrl, mockUrl: mockServer.baseUrl);
      final handle = Dioman.install(dio,
          key: const DiomanKey(),
          share: DiomanShare(policy: DiomanSharePolicy.start));
      addTearDown(handle.dispose);

      final results = await Future.wait([
        for (var i = 0; i < _burst; i++) dio.get<dynamic>(_path),
      ]).timeout(_wait);

      expect(results.map((r) => r.data), everyElement({_field: _real}));
      expect(mockServer.calls, 1, reason: '合并发生在 adapter 之上：探测只发一次');
      expect(real.calls, 1);
    });
  });

  group('adapter × offline', () {
    test(
        '[DiomanMockAdapter.new(routes) × DiomanOffline] adapter 在 offline 之下：离线时连内联 mock 请求也被排队，'
        '上线 flush 后才命中 mock', () async {
      final real = await _Counted.fixed(_ok, {_field: _real});
      var online = false;
      var hits = 0;
      final dio = _dio(real.baseUrl, routes: {
        _localRoute: _inline(_mocked, hit: () => hits++),
      });
      final offline = DiomanOffline(
          isOnline: () => online,
          onConnectivityChanged: const Stream<bool>.empty());
      final handle = Dioman.install(dio, offline: offline);
      addTearDown(handle.dispose);

      final pending = dio.get<dynamic>(_localPath);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(offline.pending, 1, reason: '请求在 adapter 之前就被 offline 排队');
      expect(hits, 0);

      online = true;
      offline.flush();
      final response = await pending.timeout(_wait);
      expect(response.data, {_field: _mocked});
      expect(response.headers.value(DiomanMockAdapter.markerHeader), '1');
      expect(hits, 1);
      expect(real.calls, 0);
    });
  });

  for (final withShare in [false, true]) {
    final chain = withShare ? 'key → share → retry' : 'key → retry';

    /// 按默认顺序装好 key/(share)/retry。
    Dio installed(Dio dio, DiomanRetry retry) {
      final handle = Dioman.install(dio,
          key: const DiomanKey(),
          share: withShare ? DiomanShare() : null,
          retry: retry);
      addTearDown(handle.dispose);
      return dio;
    }

    group('adapter × retry（$chain）', () {
      test(
          '[DiomanMockAdapter.new(routes) × DiomanRetry.onError] $chain：mock 的 500 照常被 retry 重试，'
          '每次重放都再次命中 mock，真实服务零次', () async {
        final real = await _Counted.fixed(_ok, {_field: _real});
        var hits = 0;
        var retries = 0;
        final dio = installed(
            _dio(real.baseUrl, routes: {
              _route: (_) async {
                hits++;
                return jsonBody({_field: _mocked}, _serverError);
              }
            }),
            testRetry(max: _maxRetries, onRetry: (_) => retries++));

        final r = await _call(dio).timeout(_wait);

        expect(r, isA<DioException>());
        expect((r as DioException).response?.statusCode, _serverError);
        expect(r.response?.data, {_field: _mocked});
        expect(hits, 1 + _maxRetries, reason: '首次 + 每次重试都经过 adapter');
        expect(retries, _maxRetries);
        expect(real.calls, 0);
      });

      test(
          '[DiomanMockAdapter.new(routes) × DiomanRetry.shouldRetry] $chain：mock 命中业务失败（HTTP 200 + 失败码），'
          'shouldRetry 判可重试就会重放并再次命中 mock', () async {
        final real = await _Counted.fixed(_ok, {_field: _real});
        var hits = 0;
        var retries = 0;
        final dio = installed(
            _dio(real.baseUrl, routes: {
              _route: (_) async {
                hits++;
                return jsonBody(
                    {'code': 1, 'data': null, 'message': 'fail'}, _ok);
              }
            }),
            testRetry(
                max: _maxRetries,
                shouldRetry: retryBusinessFailure,
                onRetry: (_) => retries++));

        final r = await _call(dio).timeout(_wait);

        expect(r, isA<Response<dynamic>>());
        expect(
            (r as Response).data, {'code': 1, 'data': null, 'message': 'fail'});
        expect(hits, 1 + _maxRetries);
        expect(retries, _maxRetries);
        expect(real.calls, 0);
      });

      test(
          '[DiomanMockAdapter.new(fallbackWhen) × DiomanRetry.onRetry] $chain：mock 服务 404 回落真实接口，'
          '真实先回 500 再回 200，重放时再次先探测 mock 再回落，重试一次拿到 200', () async {
        final real = await _Counted.start((n) => n == 1
            ? (status: _serverError, body: {_field: _real})
            : (status: _ok, body: {_field: _real}));
        final mockServer = await _Counted.fixed(_notFound, {_field: _mocked});
        var retries = 0;
        final dio = installed(_dio(real.baseUrl, mockUrl: mockServer.baseUrl),
            testRetry(max: _maxRetries, onRetry: (_) => retries++));

        final r = await _call(dio).timeout(_wait);

        expect(r, isA<Response<dynamic>>());
        expect((r as Response).statusCode, _ok);
        expect(r.data, {_field: _real});
        expect(r.headers.value(DiomanMockAdapter.markerHeader), isNull);
        expect(real.calls, 2, reason: '首次 500 + 一次重试');
        expect(mockServer.calls, 2, reason: '每次重放都再探测一次 mock');
        expect(retries, 1);
      });
    });
  }
}
