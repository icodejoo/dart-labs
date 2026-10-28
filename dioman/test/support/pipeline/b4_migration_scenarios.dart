export 'b4_retry_migration_scenarios.dart';
import 'dart:async';
import 'package:dioman/pipeline.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'b3_helpers.dart';
import 'b4_helpers.dart';
import 'fake_clock.dart';
import 'fake_network.dart';
import 'helpers.dart';
import 'invariant_harness.dart';

/// 确认来源插件与内核都已回收；end/race 落败传输在事件轮结束后清理。
Future<void> b4Clean(Dioman<Result> api) async {
  await b4Turn();
  expect(api.pending, 0);
  expect(api.cancellationSubscriptions, 0);
  expect(api.plugin<DiomanShareApi>()?.activeEntries ?? 0, 0);
  expect(api.plugin<DiomanCacheApi>()?.pendingWrites ?? 0, 0);
  await api.plugin<DiomanCacheApi>()?.clear();
  api.dispose();
}

/// 凭据清除后缓存不能绕过鉴权。
Future<void> b4CacheRequiresCredentials() async {
  final tokens = TestTokens();
  final net = FakeNetwork();
  final api = testClient(
      network: net, plugins: [b3Auth(tokens), const DiomanCache<Result>()]);
  await api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true));
  tokens.clear();
  expect(
      (await api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true)))
          .reason,
      'unauthenticated');
  expect(net.sends.length, 1);
  await b4Clean(api);
}

/// 内联模拟在共享前逐调用执行。
Future<void> b4InlineRunsPerCaller() async {
  var hits = 0;
  final net = FakeNetwork();
  final api = testClient(network: net, plugins: [
    b3Auth(TestTokens()),
    DiomanMock<Result>(routes: {b4Route: (_) => ++hits}),
    const DiomanShare<Result>()
  ]);
  final r = await Future.wait([
    for (var i = 0; i < 2; i++)
      api.send<Object?>(b4Get, b4Path, call: b4Call(share: true))
  ]);
  expect(hits, 2);
  expect(net.sends, isEmpty);
  expect(r.every((r) => r.ok), isTrue);
  await b4Clean(api);
}

/// 公开请求无需凭据仍可共享。
Future<void> b4PublicRequestsShare() async {
  final gate = Completer<void>();
  final net = FakeNetwork()..routes[b4Route] = [FakeReply(gate: gate.future)];
  final api = testClient(network: net, plugins: [
    b3Auth(TestTokens(null), protected: (_) => false),
    const DiomanShare<Result>()
  ]);
  final a = api.send<Object?>(b4Get, b4Path, call: b4Call(share: true));
  final b = api.send<Object?>(b4Get, b4Path, call: b4Call(share: true));
  await b4Turn();
  gate.complete();
  expect((await a).ok, isTrue);
  expect((await b).ok, isTrue);
  expect(net.sends.length, 1);
  await b4Clean(api);
}

/// 重试通知按调用方触发且异常隔离。
Future<void> b4RetryNoticesSettle({required bool throwNotice}) async {
  final clock = FakeClock();
  final net = FakeNetwork()..routes[b4Route] = [const FakeReply(status: 500)];
  var notices = 0;
  final logs = <String>[];
  final api = testClient(clock: clock, network: net, debug: logs.add, plugins: [
    DiomanRetry<Result>(
        max: 1,
        delay: (_, __, ___) => Duration.zero,
        onRetry: (_) {
          notices++;
          if (throwNotice) throw StateError('notice');
        }),
    const DiomanShare<Result>(retries: 0)
  ]);
  final a = api.send<Object?>(b4Get, b4Path,
      call: b4Call(
          share:
              throwNotice ? DiomanSharePolicy.race : DiomanSharePolicy.retry));
  final b = api.send<Object?>(b4Get, b4Path,
      call: b4Call(
          share:
              throwNotice ? DiomanSharePolicy.race : DiomanSharePolicy.retry));
  expect((await b3Finish(a, clock)).httpStatus, 500);
  expect((await b3Finish(b, clock)).httpStatus, 500);
  expect(notices, 2);
  expect(net.sends.length, throwNotice ? 4 : 2);
  if (throwNotice) {
    expect(logs, isNotEmpty);
  }
  await b4Clean(api);
}

/// 刷新与外层重试重新进入来源阶段，并验证逻辑请求不变量。
Future<void> b4RefreshAndRetry(
    {bool auth = false,
    bool refresh = false,
    bool extraFailure = false,
    bool reinstallShare = false,
    bool internalRetry = false,
    bool cache = false,
    bool singleSubscriber = false,
    bool assertCached = false}) async {
  final clock = FakeClock();
  final net = FakeNetwork();
  final tokens = TestTokens();
  var refreshes = 0;
  final h = InvariantHarness(net, clock);
  final gate = Completer<void>();
  net.routes[b4Route] = [
    FakeReply(
        status: refresh ? 401 : 200,
        body: refresh ? null : {b4LiteralCode: 500, b4LiteralData: null},
        gate: gate.future),
    if (extraFailure) const FakeReply(status: 500),
    const FakeReply()
  ];
  final api = testClient(network: net, clock: clock, plugins: [
    ...h.probes(),
    h.loadingPlugin(),
    h.notifyPlugin(),
    DiomanRetry<Result>(max: 1, delay: (_, __, ___) => Duration.zero),
    if (auth)
      b3Auth(tokens, refresh: (tm, r) {
        refreshes++;
        tm.setTokens(accessToken: b3Fresh);
      }),
    const DiomanShare<Result>(retries: 0),
    const DiomanCache<Result>()
  ]);
  if (reinstallShare) {
    api.eject(DiomanShare.pluginName);
    api.use(const DiomanShare<Result>(retries: 0));
  }
  final call = b4Call(
      share: internalRetry ? DiomanSharePolicy.retry : true, cache: cache);
  final a = h.track(1, api.send<Object?>(b4Get, b4Path, call: call));
  final b = singleSubscriber
      ? null
      : h.track(2, api.send<Object?>(b4Get, b4Path, call: call));
  await b4Turn();
  gate.complete();
  expect((await b3Finish(a, clock)).ok, isTrue);
  if (b != null) {
    expect((await b3Finish(b, clock)).ok, isTrue);
  }
  expect(refreshes, refresh ? 1 : 0);
  expect(net.sends.length, extraFailure ? 3 : 2);
  if (extraFailure) {
    expect(net.sends[2].options.headers['Authorization'], 'Bearer $b3Fresh');
  }
  if (assertCached) {
    final count = net.sends.length;
    await h.track(
        b == null ? 2 : 3, api.send<Object?>(b4Get, b4Path, call: call));
    expect(net.sends.length, count);
  }
  h.assertAll(api);
  await b4Clean(api);
}

/// 程序错误注入位置。
enum B4BugSite {
  /// 就绪回调。
  ready,

  /// 到期读取。
  expiresAt,

  /// 保护判定。
  isProtected,

  /// 客户端时钟。
  clock,

  /// 失败通知。
  onFailure,

  /// 重试判定。
  shouldRetry,
}

/// 回调错误必须穿过真实共享插件并保留原始错误，通知错误则隔离。
Future<void> b4CallbackBugSettles(
    {required B4BugSite throwIn,
    DiomanSharePolicy policy = DiomanSharePolicy.start}) async {
  final boom = StateError('migration bug');
  final net = FakeNetwork()
    ..routes[b4Route] = [const FakeReply(status: _retryStatus)];
  final isRetry = throwIn == B4BugSite.shouldRetry;
  final api = testClient(
      network: net,
      clock: throwIn == B4BugSite.clock ? _MigrationClock(boom) : null,
      plugins: [
        if (isRetry)
          DiomanRetry<Result>(max: 1, shouldRetry: (r, n) => throw boom),
        if (!isRetry)
          DiomanAuth<Result>(
              tokenManager: TestTokens(),
              onRefresh: (tm, r) {},
              onAccessExpired: (tm, r) {},
              isProtected:
                  throwIn == B4BugSite.isProtected ? (_) => throw boom : null,
              ready: throwIn == B4BugSite.ready ? (_, __) => throw boom : null,
              expiresAt: throwIn == B4BugSite.expiresAt
                  ? (_) => throw boom
                  : throwIn == B4BugSite.clock
                      ? (_) => DateTime.fromMillisecondsSinceEpoch(0)
                      : null,
              onFailure: throwIn == B4BugSite.onFailure
                  ? (_, __) => throw boom
                  : null),
        const DiomanShare<Result>(),
        const DiomanCache<Result>()
      ]);
  if (!isRetry) {
    net.routes[b4Route] = [const FakeReply(status: 401)];
  }
  final a = api.send<Object?>(b4Get, b4Path, call: b4Call(share: policy));
  final b = api.send<Object?>(b4Get, b4Path, call: b4Call(share: policy));
  await Future.wait([
    expectLater(a, throwsA(same(boom))),
    expectLater(b, throwsA(same(boom)))
  ]);
  await b4Clean(api);
}

/// 重试判定回归的 HTTP 状态。
const _retryStatus = 500;

/// 首发取消与刷新取消，跟随者独立完成或受 cancelAll 控制。
Future<void> b4CancellationSettles(
    {bool chained = false,
    bool businessFailure = false,
    bool cancelBeforeReply = false,
    bool retryWithoutRefresh = false,
    bool cancelAll = false}) async {
  final clock = FakeClock();
  final gate = Completer<void>();
  final refreshing = Completer<void>();
  final release = Completer<void>();
  final tokens = TestTokens();
  final token = CancelToken();
  final net = FakeNetwork()
    ..routes[b4Route] = [
      FakeReply(
          status: businessFailure
              ? 200
              : chained || retryWithoutRefresh
                  ? 500
                  : 401,
          body: businessFailure
              ? {b4LiteralCode: 500, b4LiteralData: null}
              : null,
          gate: gate.future),
      if (chained) const FakeReply(status: 401),
      const FakeReply()
    ];
  final api = testClient(clock: clock, network: net, plugins: [
    DiomanRetry<Result>(max: 1, delay: (_, __, ___) => Duration.zero),
    b3Auth(tokens, refresh: (tm, r) async {
      refreshing.complete();
      await release.future;
      tm.setTokens(accessToken: b3Fresh);
    }),
    const DiomanShare<Result>(),
    const DiomanCache<Result>()
  ]);
  final a = api.send<Object?>(b4Get, b4Path,
      call: DiomanCall(
          key: b4Key, cancelToken: token, options: {DiomanShare.option: true}));
  final b = api.send<Object?>(b4Get, b4Path, call: b4Call(share: true));
  await b4Turn();
  if (cancelBeforeReply) {
    token.cancel();
    expect((await a).kind, DiomanKind.cancel);
  }
  gate.complete();
  if (!retryWithoutRefresh) {
    for (var i = 0; i < 100 && !refreshing.isCompleted; i++) {
      await b4Turn();
      clock.elapse(Duration.zero);
    }
    expect(refreshing.isCompleted, isTrue);
    await refreshing.future;
  }
  if (cancelAll) {
    api.cancelAll();
    expect((await a).kind, DiomanKind.cancel);
    expect((await b).kind, DiomanKind.cancel);
    release.complete();
    await b4Turn();
  } else {
    if (chained) {
      token.cancel();
      expect((await a).kind, DiomanKind.cancel);
    }
    release.complete();
    expect((await b3Finish(b, clock)).ok, isTrue);
  }
  await b4Clean(api);
}

/// mock 回落每次尝试重新进入；内联 HTTP/业务失败可由 retry 恢复。
Future<void> b4MockRetryRecovers(
    {bool fallback = false,
    bool inlineBusiness = false,
    bool withShare = false}) async {
  final clock = FakeClock();
  final net = FakeNetwork();
  var hits = 0;
  net.routes['GET:https://mock.test$b4Path'] = [const FakeReply(status: 404)];
  net.routes[b4Route] = [const FakeReply(status: 500), const FakeReply()];
  final api = testClient(clock: clock, network: net, plugins: [
    DiomanRetry<Result>(
        max: 1,
        delay: (_, __, ___) => Duration.zero,
        shouldRetry: inlineBusiness ? (r, n) => !r.ok : null),
    DiomanMock<Result>(
        mockUrl: fallback ? b4LiteralHttpsMockTest : null,
        routes: fallback
            ? {}
            : {
                b4Route: (_) {
                  hits++;
                  if (!inlineBusiness) {
                    return Response<dynamic>(
                        requestOptions: RequestOptions(path: b4Path),
                        statusCode: hits == 1 ? 500 : 200,
                        data: {
                          b4LiteralCode: 0,
                          b4LiteralData: b4LiteralRecovered
                        });
                  }
                  return hits == 1
                      ? {b4LiteralCode: 500, b4LiteralData: null}
                      : {b4LiteralCode: 0, b4LiteralData: b4LiteralRecovered};
                }
              }),
    if (withShare) const DiomanShare<Result>()
  ]);
  expect(
      (await b3Finish(
              api.send<Object?>(b4Get, b4Path, call: b4Call(share: true)),
              clock))
          .ok,
      isTrue);
  expect(net.sends.length, fallback ? 4 : 0);
  expect(hits, fallback ? 0 : 2);
  await b4Clean(api);
}

/// 复现客户端时钟的程序错误，不恢复已删除的请求级 now。
class _MigrationClock extends FakeClock {
  /// 保存同一个原始错误以断言身份。
  _MigrationClock(this.error);

  /// 原始错误。
  final Object error;

  /// 鉴权主动过期检查读取时钟时抛错。
  @override
  DateTime now() => throw error;
}
