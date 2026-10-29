import 'dart:async';
import 'dart:typed_data';
import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/b3_helpers.dart';
import '../support/b4_helpers.dart';
import '../support/fake_clock.dart';
import '../support/fake_network.dart';
import '../support/helpers.dart';

const _result = 'result';
const _maxHeader = '60';
const _retry = 'retry';
const _auth = 'auth';
const _mock = 'mock';
const _share = 'share';
const _path = '/b8';
const _get = 'GET';
const _put = 'PUT';
const _route = '$_put:$_path';
const _second = Duration(seconds: 1);

void main() {
  for (final body in [
    Uint8List.fromList([1, 2]),
    <int>[1, 2]
  ]) {
    test('[DiomanContext.markReplayable] B8 字节体重放保留类型 ${body.runtimeType}',
        () async {
      final net = FakeNetwork();
      final api = testClient(network: net, plugins: [
        TestPlugin('bytes', handler: (ctx, next) async {
          ctx.markReplayable();
          await next();
          return next();
        })
      ]);
      await api.send<dynamic>(_put, _path, data: body);
      expect(net.sends.length, 2);
      for (final send in net.sends) {
        expect(send.options.data, isA<List<int>>());
        expect(send.options.data, [1, 2]);
        if (body is Uint8List) expect(send.options.data, isA<Uint8List>());
      }
      api.dispose();
    });
  }
  for (final useStream in [false, true]) {
    test(
        '[DiomanContext.canReplay] B8 auth ready 的实际体决定重放 useStream=$useStream',
        () async {
      final body = Stream<Uint8List>.value(Uint8List.fromList([1, 2]));
      final net = FakeNetwork()
        ..routes[_route] = [const FakeReply(status: 401), const FakeReply()];
      var refreshes = 0;
      final api = testClient(network: net, plugins: [
        b3Auth(TestTokens(),
            ready: (_, __) => RequestPatch(data: useStream ? body : {'a': 1}),
            refresh: (tm, _) {
              refreshes++;
              tm.setTokens(accessToken: b3Fresh);
            })
      ]);
      final r =
          await api.send<dynamic>(_put, _path, data: useStream ? null : body);
      expect(r.status, useStream ? 401 : 200);
      expect(net.sends.length, useStream ? 1 : 2);
      expect(refreshes, useStream ? 0 : 1);
      api.dispose();
    });
  }
  for (final disk in [false, true]) {
    test('[DiomanCache.clone] B8 命中返回边界重查取消 disk=$disk', () async {
      final token = CancelToken();
      var cancelOnClone = false;
      final ctx = testContext(token: token);
      final persist = B4Persist();
      final plugin = DiomanCache<Result>(
          persist: persist,
          cachePolicy:
              disk ? DiomanCachePolicy.persist : DiomanCachePolicy.memo,
          clone: (Object? data) {
            if (cancelOnClone) token.cancel();
            return data;
          }).setup(ctx.client);
      final request = DiomanRequest(RequestOptions(path: _path),
          call: DiomanCall(options: {DiomanCache.option: true}));
      final cached = testContext(token: token, request: request);
      Future<Result> next([RequestPatch? patch]) async =>
          cached.factory.normalize(request,
              raw: Response<dynamic>(
                  requestOptions: request.toRequestOptions(), statusCode: 200));
      await plugin.handle(cached, next);
      cancelOnClone = true;
      final r = await plugin.handle(cached, next);
      expect(r.kind, DiomanKind.cancel);
      plugin.dispose();
      ctx.client.dispose();
      cached.client.dispose();
    });
  }
  for (final replace in [false, true]) {
    for (final override in [false, true]) {
      test(
          '[DiomanAuth.refreshTimeout][DiomanAuthOptions.refreshTimeout] B8 刷新超时 replace=$replace override=$override',
          () async {
        final clock = FakeClock();
        final tokens = TestTokens();
        var notices = 0;
        var refreshes = 0;
        final api = testClient(clock: clock, plugins: [
          DiomanAuth<Result>(
              tokenManager: tokens,
              onRefresh: (_, __) {
                refreshes++;
                return Completer<void>().future;
              },
              onAccessExpired: (_, __) => notices++),
          TestPlugin(_result,
              stage: DiomanStage.source,
              handler: (ctx, next) async => ctx.fail(DiomanFailure(
                  kind: DiomanKind.http,
                  status: tokens.accessToken == b3Fresh ? 200 : 401)))
        ]);
        final call = DiomanCall(options: {
          if (override)
            DiomanAuth.option: const DiomanAuthOptions(refreshTimeout: _second)
        });
        final requests = [
          api.send<dynamic>(_get, _path, call: call),
          api.send<dynamic>(_get, _path, call: call)
        ];
        for (var i = 0; i < 10 && refreshes == 0; i++) {
          await b3Turn();
        }
        expect(refreshes, 1);
        if (replace) tokens.setTokens(accessToken: b3Fresh);
        clock.elapse(override ? _second : const Duration(seconds: 30));
        final results = await Future.wait(requests);
        expect(results.map((r) => r.status), everyElement(replace ? 200 : 0));
        expect(results.map((r) => r.kind),
            everyElement(replace ? DiomanKind.http : DiomanKind.auth));
        expect(notices, replace ? 0 : 1);
        expect(clock.pendingTimers, 0);
        api.dispose();
      });
    }
  }

  test('[DiomanAuth.refreshTimeout] B8 刷新异常遇到新登录继续当前 token', () async {
    final tokens = TestTokens();
    final gate = Completer<void>();
    var notices = 0;
    final api = testClient(plugins: [
      DiomanAuth<Result>(
          tokenManager: tokens,
          onRefresh: (_, __) => gate.future,
          onAccessExpired: (_, __) => notices++),
      TestPlugin(_result,
          stage: DiomanStage.source,
          handler: (ctx, next) async => ctx.fail(DiomanFailure(
              kind: DiomanKind.http,
              status: tokens.accessToken == b3Fresh ? 200 : 401)))
    ]);
    final pending = api.send<dynamic>(_get, _path);
    for (var i = 0; i < 5; i++) {
      await b3Turn();
    }
    tokens.setTokens(accessToken: b3Fresh);
    gate.completeError(StateError('refresh'));
    expect((await pending).status, 200);
    expect(notices, 0);
    api.dispose();
  });

  for (final header in ['61', 'Thu, 01 Jan 1970 00:01:01 GMT', _maxHeader]) {
    test('[DiomanRetry.retryAfterMax] B8 服务端等待超限不重试 $header', () async {
      final clock = FakeClock();
      var sends = 0;
      final api = testClient(clock: clock, plugins: [
        DiomanRetry<Result>(
            max: 1,
            jitter: (_) => throw StateError('jitter'),
            delayMax: Duration.zero),
        TestPlugin(_result, stage: DiomanStage.source,
            handler: (ctx, next) async {
          sends++;
          return ctx.factory.normalize(ctx.request,
              raw: Response<dynamic>(
                  requestOptions: ctx.request.toRequestOptions(),
                  statusCode: 503,
                  headers: Headers.fromMap({
                    'retry-after': [header]
                  })));
        })
      ]);
      final pending = api.send<dynamic>(_get, _path);
      await b3Turn();
      expect(sends, 1);
      clock.elapse(const Duration(seconds: 60));
      expect((await pending).status, 503);
      expect(sends, header == _maxHeader ? 2 : 1);
      expect(clock.pendingTimers, 0);
      api.dispose();
    });
  }

  test('[DiomanCache.clone] B8 命中 clone 时取消不能返回成功', () async {
    final token = CancelToken();
    var hit = false;
    final net = FakeNetwork();
    final api = testClient(network: net, plugins: [
      DiomanCache<Result>(clone: (Object? data) {
        if (hit) token.cancel();
        return data;
      })
    ]);
    final options = {DiomanCache.option: true};
    await api.send<dynamic>(_get, _path, call: DiomanCall(options: options));
    hit = true;
    final r = await api.send<dynamic>(_get, _path,
        call: DiomanCall(options: options, cancelToken: token));
    expect(r.kind, DiomanKind.cancel);
    expect(net.sends.length, 1);
    api.dispose();
  });

  for (final mode in [_retry, _auth, _mock, _share]) {
    test('[DiomanContext.canReplay] B8 一次性体 $mode 只发送一次', () async {
      final net = FakeNetwork()
        ..routes[_route] = [const FakeReply(status: 503)];
      final clock = FakeClock();
      final api = testClient(network: net, clock: clock, plugins: [
        if (mode == _retry)
          DiomanRetry<Result>(max: 2, delay: (_, __, ___) => Duration.zero),
        if (mode == _auth)
          b3Auth(TestTokens(),
              failure: (_, __) => DiomanAuthFailureAction.refresh),
        if (mode == _mock)
          DiomanMock<Result>(
              mockUrl: 'https://mock.test', fallbackWhen: (_) => true),
        if (mode == _share)
          const DiomanShare<Result>(
              policy: DiomanSharePolicy.retry, methods: {_put})
      ]);
      final body = Stream<Uint8List>.value(Uint8List.fromList([1, 2]));
      final pending = api.send<dynamic>(_put, _path,
          data: body,
          call: DiomanCall(key: 'stream', options: {DiomanShare.option: true}));
      await b3Finish(pending, clock);
      expect(net.sends.length, 1);
      api.dispose();
    });
  }
}
