import 'package:dioman/src/diagnostics.dart';
import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'b3_helpers.dart';
import 'fake_clock.dart';
import 'fake_network.dart';
import 'helpers.dart';
import 'invariant_harness.dart';

/// loading 插件在组合表中的名称。
const loadingName = 'loading';

/// notify 插件在组合表中的名称。
const notifyName = 'notify';

/// retry 插件在组合表中的名称。
const retryName = 'retry';

/// breaker 插件在组合表中的名称。
const breakerName = 'breaker';

/// auth 插件在组合表中的名称。
const authName = 'auth';

/// mock 插件在组合表中的名称。
const mockName = 'mock';

/// share 插件在组合表中的名称。
const shareName = 'share';

/// cache 插件在组合表中的名称。
const cacheName = 'cache';

/// offline 插件在组合表中的名称。
const offlineName = 'offline';

/// repath 插件在组合表中的名称。
const repathName = 'repath';

/// filter 插件在组合表中的名称。
const filterName = 'filter';

/// timeout 插件在组合表中的名称。
const timeoutName = 'timeout';

/// envs 插件在组合表中的名称。
const envsName = 'envs';

/// 九个独立安装的交互插件，无真实安装依赖。
const interactionNames = [
  loadingName,
  notifyName,
  retryName,
  breakerName,
  authName,
  mockName,
  shareName,
  cacheName,
  offlineName
];

/// 全集掩码及子集规模。
const subsetCount = 512;

/// 流程共用地址与网络时间。
const flowPath = '/powerset';
const mockUrl = 'https://mock.test';
const tick = Duration(milliseconds: 10);
const flowGet = 'GET';
const flowCode = 'code';
const flowData = 'data';
const flowItems = 'items';
const flowN = 'n';
const flowKey = 'same';

/// 位掩码枚举；合成依赖表也走同一实现。
List<int> subsets(int size, [Map<int, Set<int>> needs = const {}]) => [
      for (var mask = 0; mask < 1 << size; mask++)
        if (needs.entries.every((e) =>
            mask & (1 << e.key) == 0 ||
            e.value.every((i) => mask & (1 << i) != 0)))
          mask
    ];

/// 流程和无插件时逐调用的类别；类别断言只在独立 baseline 中使用。
enum PowerFlow {
  success([DiomanKind.ok, DiomanKind.ok]),
  http([DiomanKind.http]),
  flaky([DiomanKind.http]),
  auth([DiomanKind.biz, DiomanKind.biz, DiomanKind.biz]),
  network([DiomanKind.network]),
  concurrent([DiomanKind.ok, DiomanKind.ok]),
  cancelAll([DiomanKind.cancel, DiomanKind.cancel]),
  cancelLeader([DiomanKind.cancel, DiomanKind.ok]),
  recovery([DiomanKind.ok, DiomanKind.ok]);

  const PowerFlow(this.baseline);
  final List<DiomanKind> baseline;
}

/// 每条用例独占网络、时钟、凭证、流、插件和调用记录。
class PowerFixture {
  PowerFixture(this.mask, this.flow) {
    net = FakeNetwork(onSend: (send) {
      final request = send.options;
      final probe = request.path.startsWith(mockUrl);
      final hit = ++realHits;
      final status = probe
          ? 404
          : flow == PowerFlow.http || flow == PowerFlow.flaky && hit <= 2
              ? 500
              : 200;
      if (probe) realHits--;
      final gate = Completer<void>();
      clock.createTimer(tick, gate.complete);
      net.routes['${request.method}:${request.path}'] = [
        FakeReply(
          status: status,
          body: {
            flowCode: flow == PowerFlow.auth &&
                    request.headers[b3Header] != 'Bearer $b3Fresh'
                ? 401
                : 0,
            flowData: null
          },
          error: !probe && flow == PowerFlow.network
              ? DioException(
                  requestOptions: request,
                  type: DioExceptionType.connectionError)
              : null,
          gate: gate.future,
        )
      ];
    });
    h = InvariantHarness(net, clock);
    api = testClient(
        network: net, clock: clock, plugins: [...h.probes(), ...plugins()]);
    api.dio.transformer = B3Transformer();
  }

  final int mask;
  final PowerFlow flow;
  final clock = FakeClock();
  final tokens = TestTokens();
  final connectivity = StreamController<bool>.broadcast(sync: true);
  late final FakeNetwork net;
  late final InvariantHarness h;
  late final Dioman<Result> api;
  final requests = <Future<Result>>[];

  /// 调用方刚离开时的订阅快照，避免最终 dispose 清表掩盖首发泄漏。
  final leavingSubscriptions = <int>[];
  bool online = true;
  int realHits = 0;

  /// 查询本次安装表。
  bool has(String name) => mask & (1 << interactionNames.indexOf(name)) != 0;

  /// 创建本次独占的插件对象。
  List<DiomanPlugin<Result>> plugins() {
    final factories = <String, DiomanPlugin<Result> Function()>{
      loadingName: () => h.loadingPlugin(delayClose: tick),
      notifyName: () => h.notifyPlugin(),
      retryName: () =>
          DiomanRetry<Result>(max: 2, delay: (_, __, ___) => Duration.zero),
      breakerName: () => DiomanBreaker<Result>(failureThreshold: 2),
      authName: () => b3Auth(tokens,
          refresh: h.refreshInRound(0, (tm, r) async {
            final gate = Completer<void>();
            clock.createTimer(tick, gate.complete);
            await gate.future;
            tm.setTokens(accessToken: b3Fresh);
          })),
      mockName: () => DiomanMock<Result>(mockUrl: mockUrl),
      shareName: () => DiomanShare<Result>(),
      cacheName: () => DiomanCache<Result>(),
      offlineName: () => DiomanOffline<Result>(
          isOnline: () => online, onConnectivityChanged: connectivity.stream),
    };
    return [
      for (final name in interactionNames)
        if (has(name)) factories[name]!()
    ];
  }

  /// 登记嵌套载荷与逻辑请求标记；同 key 请求不靠标记参与构键。
  void launch({String key = flowKey, CancelToken? token}) {
    final id = requests.length + 1;
    requests.add(h.track(
        id,
        api
            .send<dynamic>(flowGet, flowPath,
                data: {
                  flowItems: [
                    {flowN: 0}
                  ]
                },
                call: DiomanCall(key: key, cancelToken: token, headers: {
                  invariantRequestHeader: id
                }, options: {
                  DiomanShare.option: true,
                  DiomanCache.option: true,
                }))
            .whenComplete(() {
          leavingSubscriptions.add(h.contexts
              .singleWhere((ctx) => ctx.id == id)
              .cancellationSubscriptions);
        })));
  }

  /// 让网络到达阻塞点，只推进微任务和事件队列。
  Future<void> turn() async {
    await b3Turn();
    await b3Turn();
  }

  /// 有上限地驱动假时间；超出预算明确失败而不是永久挂起。
  Future<void> drain() async {
    var done = false;
    final pending = Future.wait(requests);
    pending.then<void>((_) => done = true,
        onError: (Object e, StackTrace s) => done = true);
    for (var i = 0; i < 100 && !done; i++) {
      await turn();
      clock.elapse(tick);
    }
    expect(done, isTrue, reason: '假时钟流程必须有界落定');
    await pending;
    for (var i = 0; i < 4; i++) {
      await turn();
      clock.elapse(tick);
    }
  }

  /// 九条流程只发请求、改变连接状态、取消和推进假时钟。
  Future<void> run() async {
    switch (flow) {
      case PowerFlow.success:
        launch();
        await drain();
        launch();
      case PowerFlow.auth:
        if (has(authName)) h.beginRefreshRound(0);
        launch();
        launch();
        launch(key: 'other');
      case PowerFlow.concurrent:
        launch();
        launch();
      case PowerFlow.cancelAll:
        launch();
        launch();
        await turn();
        api.cancelAll();
      case PowerFlow.cancelLeader:
        final token = CancelToken();
        launch(token: token);
        launch();
        await turn();
        token.cancel();
      case PowerFlow.recovery:
        online = false;
        launch();
        launch();
        await turn();
        clock.elapse(Duration.zero);
        online = true;
        connectivity.add(true);
      case PowerFlow.http:
      case PowerFlow.flaky:
      case PowerFlow.network:
        launch();
    }
    await drain();
  }

  /// 正常收尾即检查内部诊断，再清缓存与销毁，最后再检查一次。
  Future<void> check() async {
    h.assertAll(api);
    expect(leavingSubscriptions, everyElement(0), reason: 'I3 离开当时已摘监听');
    final cache = api.plugin<DiomanCacheApi>();
    final share = api.plugin<DiomanShareApi>();
    expect(share?.activeEntries ?? 0, 0);
    expect(cache?.pendingWrites ?? 0, 0);
    await cache?.clear();
    expect(cache?.entryCount ?? 0, 0);
    expect(cache?.pendingWrites ?? 0, 0);
    api.dispose();
    expect(share?.activeEntries ?? 0, 0);
    expect(cache?.entryCount ?? 0, 0);
    expect(cache?.pendingWrites ?? 0, 0);
  }

  /// 失败时也释放流和客户端。
  Future<void> dispose() async {
    api.dispose();
    await connectivity.close();
  }
}
