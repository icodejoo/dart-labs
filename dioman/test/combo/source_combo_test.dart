import 'dart:async';
import 'package:dioman/pipeline.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/pipeline/b3_helpers.dart';
import '../support/pipeline/b4_helpers.dart';
import '../support/pipeline/fake_clock.dart';
import '../support/pipeline/fake_network.dart';
import '../support/pipeline/helpers.dart';
import '../support/pipeline/invariant_harness.dart';

/// source 与外层尝试、凭证阶段的真实装配。
void main() {
  test(
      '[DiomanMock.mockUrl × DiomanCache.option × DiomanShare.option] 探测不缓存不共享，回落恢复两者',
      () async {
    final gate = Completer<void>();
    final net = FakeNetwork()
      ..routes['GET:https://mock.test$b4Path'] = [
        FakeReply(status: 404, gate: gate.future)
      ];
    final api = testClient(network: net, plugins: [
      const DiomanMock<Result>(mockUrl: b4LiteralHttpsMockTest),
      const DiomanShare<Result>(),
      const DiomanCache<Result>()
    ]);
    final a = api.send<Object?>(b4Get, b4Path,
        call: b4Call(cache: true, share: true));
    final b = api.send<Object?>(b4Get, b4Path,
        call: b4Call(cache: true, share: true));
    await b4Turn();
    expect(net.sends.length, 2);
    expect(api.plugin<DiomanCacheApi>()!.entryCount, 0);
    expect(api.plugin<DiomanShareApi>()!.activeEntries, 0);
    gate.complete();
    expect((await a).ok, isTrue);
    expect((await b).ok, isTrue);
    expect(net.sends.length, 3);
    await api.send<Object?>(b4Get, b4Path,
        call: b4Call(cache: true, share: true));
    expect(net.sends.length, 4);
    await b4Turn();
    expect(api.plugin<DiomanCacheApi>()!.pendingWrites, 0);
    expect(api.plugin<DiomanShareApi>()!.activeEntries, 0);
  });
  test('[DiomanMock.routes × DiomanShare.option] 内联优先于 share 每个逻辑调用均处理，不触网',
      () async {
    var hits = 0;
    final net = FakeNetwork();
    final api = testClient(network: net, plugins: [
      DiomanMock<Result>(routes: {b4Route: (_) => ++hits}),
      const DiomanShare<Result>()
    ]);
    final r = await Future.wait([
      for (var i = 0; i < 3; i++)
        api.send<Object?>(b4Get, b4Path, call: b4Call(share: true))
    ]);
    expect(r.map((r) => r.data), [1, 2, 3]);
    expect(net.sends, isEmpty);
  });
  test('[DiomanShare.option × DiomanCache.option] 并发一次发送缓存一次，下一轮零触网', () async {
    final gate = Completer<void>();
    final net = FakeNetwork()..routes[b4Route] = [FakeReply(gate: gate.future)];
    final api = testClient(network: net, plugins: [
      const DiomanShare<Result>(),
      const DiomanCache<Result>(clone: DiomanClonePolicy.none)
    ]);
    final a = api.send<Object?>(b4Get, b4Path,
        call: b4Call(share: true, cache: true));
    final b = api.send<Object?>(b4Get, b4Path,
        call: b4Call(share: true, cache: true));
    await b4Turn();
    gate.complete();
    expect(identical(await a, await b), isTrue);
    await api.send<Object?>(b4Get, b4Path,
        call: b4Call(share: true, cache: true));
    expect(net.sends.length, 1);
  });
  test('[DiomanCache.option × DiomanOffline.maxWait] 离线缓存命中照常返回，未命中恢复后写缓存',
      () async {
    var online = true;
    final stream = StreamController<bool>.broadcast(sync: true);
    addTearDown(stream.close);
    final net = FakeNetwork();
    final api = testClient(network: net, plugins: [
      const DiomanCache<Result>(),
      DiomanOffline<Result>(
          isOnline: () => online, onConnectivityChanged: stream.stream)
    ]);
    await api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true));
    online = false;
    expect(
        (await api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true))).ok,
        isTrue);
    expect(api.plugin<DiomanOfflineApi>()!.pending, 0);
    final pending = api.send<Object?>(b4Get, b4Path,
        call: b4Call(cache: true, key: b4LiteralOther));
    await b4Turn();
    expect(api.plugin<DiomanOfflineApi>()!.pending, 1);
    stream.add(true);
    await pending;
    expect(net.sends.length, 2);
    api.dispose();
  });
  test('[DiomanSharePolicy.start × DiomanOffline.maxWait] 首发离场仍等恢复，最后离场清离线等待与 I3',
      () async {
    final stream = StreamController<bool>.broadcast(sync: true);
    addTearDown(stream.close);
    final net = FakeNetwork();
    final clock = FakeClock();
    final token = CancelToken();
    final h = InvariantHarness(net, clock);
    final api = testClient(network: net, clock: clock, plugins: [
      ...h.probes(),
      const DiomanShare<Result>(),
      DiomanOffline<Result>(
          isOnline: () => false,
          onConnectivityChanged: stream.stream,
          maxWait: b4Tick)
    ]);
    final a = h.track(
        1,
        api.send<Object?>(b4Get, b4Path,
            call: DiomanCall(
                key: b4Key,
                cancelToken: token,
                options: {DiomanShare.option: true})));
    final b =
        h.track(2, api.send<Object?>(b4Get, b4Path, call: b4Call(share: true)));
    await b4Turn();
    token.cancel();
    expect((await a).kind, DiomanKind.cancel);
    expect(api.plugin<DiomanOfflineApi>()!.pending, 1);
    expect(clock.pendingTimers, 1);
    stream.add(true);
    expect((await b).ok, isTrue);
    h.assertAll(api);
    final c = api.send<Object?>(b4Get, b4Path, call: b4Call(share: true));
    await b4Turn();
    api.cancelAll();
    expect((await c).kind, DiomanKind.cancel);
    await b4Turn();
    expect(api.plugin<DiomanOfflineApi>()!.pending, 0);
    expect(clock.pendingTimers, 0);
    expect(api.plugin<DiomanShareApi>()!.activeEntries, 0);
    api.dispose();
  });
  test(
      '[DiomanRetry.max × DiomanShare.option × DiomanCache.option] 每次尝试重新进入，失败不缓存，跟随者最终恢复',
      () async {
    for (final policy in DiomanSharePolicy.values) {
      final gate = Completer<void>();
      final net = FakeNetwork()
        ..routes[b4Route] = [
          FakeReply(status: 500, gate: gate.future),
          const FakeReply()
        ];
      final clock = FakeClock();
      final api = testClient(network: net, clock: clock, plugins: [
        DiomanRetry<Result>(max: 1, delay: (_, __, ___) => Duration.zero),
        const DiomanShare<Result>(retries: 0),
        const DiomanCache<Result>()
      ]);
      final a = api.send<Object?>(b4Get, b4Path,
          call: b4Call(share: policy, cache: true));
      final b = api.send<Object?>(b4Get, b4Path,
          call: b4Call(share: policy, cache: true));
      await b4Turn();
      gate.complete();
      expect((await b3Finish(a, clock)).ok, isTrue);
      expect((await b).ok, isTrue);
      expect(api.plugin<DiomanShareApi>()!.activeEntries, 0);
      await b4Turn();
      expect(api.plugin<DiomanCacheApi>()!.pendingWrites, 0);
      final count = net.sends.length;
      await api.send<Object?>(b4Get, b4Path,
          call: b4Call(share: policy, cache: true));
      expect(net.sends.length, count);
    }
  });
  test(
      '[DiomanAuth.onRefresh × DiomanShare.option × DiomanCache.option] 并发 business401 单飞刷新后重放穿过来源',
      () async {
    for (final policy in DiomanSharePolicy.values) {
      final gate = Completer<void>();
      final tokens = TestTokens();
      var refreshed = 0;
      final net = FakeNetwork()
        ..routes[b4Route] = [
          FakeReply(
              body: {b4LiteralCode: 401, b4LiteralData: null},
              gate: gate.future),
          if (policy == DiomanSharePolicy.end ||
              policy == DiomanSharePolicy.race)
            FakeReply(
                body: {b4LiteralCode: 401, b4LiteralData: null},
                gate: gate.future),
          const FakeReply()
        ];
      final api = testClient(network: net, plugins: [
        b3Auth(tokens, refresh: (tm, r) {
          refreshed++;
          tm.setTokens(accessToken: b3Fresh);
        }),
        const DiomanShare<Result>(retries: 0),
        const DiomanCache<Result>()
      ]);
      final a = api.send<Object?>(b4Get, b4Path,
          call: b4Call(share: policy, cache: true));
      final b = api.send<Object?>(b4Get, b4Path,
          call: b4Call(share: policy, cache: true));
      await b4Turn();
      gate.complete();
      expect((await a).ok, isTrue);
      expect((await b).ok, isTrue);
      expect(refreshed, 1);
      expect(api.plugin<DiomanShareApi>()!.activeEntries, 0);
      await b4Turn();
      expect(api.plugin<DiomanCacheApi>()!.pendingWrites, 0);
    }
  });
  test('[DiomanRetry.max × DiomanMock.mockUrl] 每次尝试探测回落且 I7 嵌套请求体独立', () async {
    for (final retry in [false, true]) {
      final net = FakeNetwork()
        ..routes['POST:https://mock.test$b4Path'] = [
          const FakeReply(status: 404)
        ]
        ..routes['POST:$b4Path'] = [
          FakeReply(status: retry ? 500 : 200),
          const FakeReply()
        ];
      final clock = FakeClock();
      final h = InvariantHarness(net, clock);
      final api = testClient(network: net, clock: clock, plugins: [
        ...h.probes(),
        if (retry)
          DiomanRetry<Result>(
              max: 1,
              methods: [b4LiteralPOST],
              delay: (_, __, ___) => Duration.zero),
        const DiomanMock<Result>(mockUrl: b4LiteralHttpsMockTest)
      ]);
      api.dio.transformer = B3Transformer();
      final data = {
        b4LiteralItems: [
          {b4LiteralN: 0}
        ]
      };
      expect(
          (await b3Finish(
                  h.track(
                      1,
                      api.send<Object?>(b4LiteralPOST, b4Path,
                          data: data,
                          call: const DiomanCall(
                              headers: {invariantRequestHeader: 1}))),
                  clock))
              .ok,
          isTrue);
      expect(net.sends.length, retry ? 4 : 2);
      expect((data[b4LiteralItems]!.single)[b4LiteralN], 0);
      h.assertAll(api);
    }
  });
}
