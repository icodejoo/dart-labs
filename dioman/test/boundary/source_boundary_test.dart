import 'dart:async';
import 'package:dioman/pipeline.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/pipeline/b4_helpers.dart';
import '../support/pipeline/fake_clock.dart';
import '../support/pipeline/fake_network.dart';
import '../support/pipeline/helpers.dart';
import '../support/pipeline/invariant_harness.dart';

/// source 取消、计时和新鲜度边界。
void main() {
  test('[DiomanSharePolicy.start] 首发取消不连累跟随者，最后离开才取消且清理 I3', () async {
    final gate = Completer<void>();
    final clock = FakeClock();
    final net = FakeNetwork()..routes[b4Route] = [FakeReply(gate: gate.future)];
    final h = InvariantHarness(net, clock);
    final api = testClient(
        network: net,
        clock: clock,
        plugins: [...h.probes(), const DiomanShare<Result>()]);
    final token = CancelToken();
    final a = h.track(
        1,
        api.send<Object?>(b4Get, b4Path,
            call: DiomanCall(
                key: b4Key,
                cancelToken: token,
                receiveTimeout: b4Tick,
                options: {DiomanShare.option: true})));
    final b =
        h.track(2, api.send<Object?>(b4Get, b4Path, call: b4Call(share: true)));
    await b4Turn();
    token.cancel();
    expect((await a).kind, DiomanKind.cancel);
    expect(h.contexts.first.cancellationSubscriptions, 0,
        reason: '首发离开即摘掉监听，不等共享传输完成');
    expect(net.sends.single.options.cancelToken!.isCancelled, isFalse);
    gate.complete();
    expect((await b).ok, isTrue);
    h.assertAll(api);
    final gate2 = Completer<void>();
    net.routes[b4Route] = [FakeReply(gate: gate2.future)];
    final c = api.send<Object?>(b4Get, b4Path, call: b4Call(share: true));
    await b4Turn();
    api.cancelAll();
    expect((await c).kind, DiomanKind.cancel);
    expect(net.sends.last.options.cancelToken!.isCancelled, isTrue);
    gate2.complete();
    await b4Turn();
    expect(clock.pendingTimers, 0);
  });
  test('[DiomanSharePolicy.start] 首发三个 Dio 超时清零，各订阅者独立超时 kind timeout',
      () async {
    final clock = FakeClock();
    final gate = Completer<void>();
    final net = FakeNetwork()..routes[b4Route] = [FakeReply(gate: gate.future)];
    final api = testClient(
        clock: clock, network: net, plugins: [const DiomanShare<Result>()]);
    final a = api.send<Object?>(b4Get, b4Path,
        call: DiomanCall(
            key: b4Key,
            connectTimeout: const Duration(seconds: 3),
            sendTimeout: const Duration(seconds: 2),
            receiveTimeout: b4Tick,
            options: {DiomanShare.option: true}));
    final b = api.send<Object?>(b4Get, b4Path,
        call: DiomanCall(
            key: b4Key,
            connectTimeout: b4Tick,
            receiveTimeout: const Duration(seconds: 5),
            options: {DiomanShare.option: true}));
    await b4Turn();
    final sent = net.sends.single.options;
    expect([sent.connectTimeout, sent.sendTimeout, sent.receiveTimeout],
        everyElement(Duration.zero));
    clock.elapse(const Duration(seconds: 4));
    expect((await a).kind, DiomanKind.timeout);
    expect(sent.cancelToken!.isCancelled, isFalse);
    expect(clock.pendingTimers, 1);
    gate.complete();
    expect((await b).ok, isTrue);
    expect(clock.pendingTimers, 0);
    expect(api.cancellationSubscriptions, 0);
  });
  test('[DiomanShare.policy] 同 key 四策略互不读取，提前取消与迟到结果不污染新一轮', () async {
    final gate = Completer<void>();
    final net = FakeNetwork()..routes[b4Route] = [FakeReply(gate: gate.future)];
    final api =
        testClient(network: net, plugins: [const DiomanShare<Result>()]);
    final futures = [
      for (final p in DiomanSharePolicy.values)
        api.send<Object?>(b4Get, b4Path, call: b4Call(share: p))
    ];
    await b4Turn();
    expect(net.sends.length, 4);
    gate.complete();
    expect((await Future.wait(futures)).every((r) => r.ok), isTrue);
    for (final policy in [DiomanSharePolicy.end, DiomanSharePolicy.race]) {
      final first = Completer<void>();
      final last = Completer<void>();
      final token = CancelToken();
      final n = FakeNetwork()
        ..routes[b4Route] = [
          FakeReply(gate: first.future),
          FakeReply(gate: last.future)
        ];
      final client =
          testClient(network: n, plugins: [const DiomanShare<Result>()]);
      final a = client.send<Object?>(b4Get, b4Path,
          call: DiomanCall(
              key: b4Key,
              cancelToken: token,
              options: {DiomanShare.option: policy}));
      final b =
          client.send<Object?>(b4Get, b4Path, call: b4Call(share: policy));
      await b4Turn();
      token.cancel();
      expect((await a).kind, DiomanKind.cancel);
      expect(n.sends.last.options.cancelToken!.isCancelled, isFalse);
      last.complete();
      expect((await b).ok, isTrue);
      first.complete();
      await b4Turn();
      expect(
          (await client.send<Object?>(b4Get, b4Path,
                  call: b4Call(share: policy)))
              .ok,
          isTrue);
    }
  });
  test('[DiomanShare.setup] 到达前已取消与内层同步取消均不挂起且不泄漏', () async {
    for (final before in [true, false]) {
      final token = CancelToken();
      final net = FakeNetwork();
      final api = testClient(network: net, plugins: [
        TestPlugin(b4LiteralCancel,
            stage: before ? DiomanStage.credential : DiomanStage.source,
            handler: (ctx, next) async {
          ctx.state.cancel();
          return next();
        }),
        const DiomanShare<Result>()
      ]);
      expect(
          (await api.send<Object?>(b4Get, b4Path,
                  call: DiomanCall(
                      cancelToken: token, options: {DiomanShare.option: true})))
              .kind,
          DiomanKind.cancel);
      expect(net.sends, isEmpty);
      expect(api.cancellationSubscriptions, 0);
    }
  });
  test('[DiomanCacheApi.clear] clear 作废在途写入，屏障 finally 回收，remove 不复活',
      () async {
    for (final remove in [false, true]) {
      final gate = Completer<void>();
      final net = FakeNetwork()
        ..routes[b4Route] = [FakeReply(gate: gate.future)];
      final api =
          testClient(network: net, plugins: [const DiomanCache<Result>()]);
      final cache = api.plugin<DiomanCacheApi>()!;
      final pending =
          api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true));
      await b4Turn();
      expect(cache.pendingWrites, 1);
      if (remove) {
        await cache.remove(b4Key);
      } else {
        await cache.clear();
      }
      gate.complete();
      expect((await pending).ok, isTrue);
      expect(cache.pendingWrites, 0);
      expect(cache.entryCount, 0);
      await api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true));
      expect(net.sends.length, 2);
      api.dispose();
      expect(cache.entryCount, 0);
      expect(cache.pendingWrites, 0);
    }
  });
  test('[DiomanCache.maxEntries] 新结果淘汰后旧在途不得回写，LRU 命中提升和不限容量', () async {
    final gate = Completer<void>();
    final net = FakeNetwork()
      ..routes[b4Route] = [
        FakeReply(gate: gate.future),
        const FakeReply(body: {b4LiteralV: 2})
      ];
    final api = testClient(
        network: net, plugins: [const DiomanCache<Result>(maxEntries: 1)]);
    final a = api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true));
    await b4Turn();
    await api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true));
    await api.send<Object?>(b4Get, '/other',
        call: b4Call(cache: true, key: b4LiteralOther));
    gate.complete();
    await a;
    expect(api.plugin<DiomanCacheApi>()!.pendingWrites, 0);
    await api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true));
    expect(net.sends.length, 4);
    for (final capacity in [0, 2]) {
      final n = FakeNetwork();
      final c = testClient(
          network: n, plugins: [DiomanCache<Result>(maxEntries: capacity)]);
      for (final key in [b4LiteralA, b4LiteralB, b4LiteralA, 'c', b4LiteralA]) {
        await c.send<Object?>(b4Get, b4Path,
            call: b4Call(cache: true, key: key));
      }
      expect(n.sends.length, 3);
    }
  });
  test('[DiomanOffline.maxWait] timeout cancel flush dispose 全出口清计时与订阅 I3',
      () async {
    for (final exit in [
      b4LiteralTimeout,
      b4LiteralCancel,
      b4LiteralFlush,
      b4LiteralDispose,
      b4LiteralEject
    ]) {
      final stream = StreamController<bool>.broadcast(sync: true);
      final clock = FakeClock();
      final net = FakeNetwork();
      final api = testClient(network: net, clock: clock, plugins: [
        DiomanOffline<Result>(
            isOnline: () => false,
            onConnectivityChanged: stream.stream,
            maxWait: b4Tick)
      ]);
      final offline = api.plugin<DiomanOfflineApi>()!;
      final pending = api.send<Object?>(b4Get, b4Path);
      await b4Turn();
      expect(clock.pendingTimers, 1);
      switch (exit) {
        case b4LiteralTimeout:
          clock.elapse(b4Tick);
        case b4LiteralCancel:
          api.cancelAll();
        case b4LiteralFlush:
          offline.flush();
        case b4LiteralDispose:
          api.dispose();
        default:
          api.eject(DiomanOffline.pluginName);
      }
      final r = await pending;
      expect(
          r.kind,
          exit == b4LiteralFlush
              ? DiomanKind.ok
              : exit == b4LiteralCancel
                  ? DiomanKind.cancel
                  : DiomanKind.offline);
      if (exit == b4LiteralTimeout) {
        expect(r.reason, b4LiteralTimeout);
      }
      if (exit == b4LiteralDispose || exit == b4LiteralEject) {
        expect(r.reason, b4LiteralDisposed);
      }
      expect(clock.pendingTimers, 0);
      expect(api.cancellationSubscriptions, 0);
      expect(offline.pending, 0);
      api.dispose();
      await stream.close();
    }
  });
  test('[DiomanOffline.maxQueueSize] 队满挤出最早，0 不限，请求级覆盖上限', () async {
    final stream = StreamController<bool>.broadcast(sync: true);
    addTearDown(stream.close);
    final api = testClient(plugins: [
      DiomanOffline<Result>(
          isOnline: () => false,
          onConnectivityChanged: stream.stream,
          maxQueueSize: 1)
    ]);
    final a = api.send<Object?>(b4Get, b4Path);
    await b4Turn();
    final b = api.send<Object?>(b4Get, b4Path);
    await b4Turn();
    expect((await a).reason, b4LiteralQueueFull);
    final c = api.send<Object?>(b4Get, b4Path,
        call: b4Call(offline: const DiomanOfflineOptions(maxQueueSize: 0)));
    await b4Turn();
    expect(api.plugin<DiomanOfflineApi>()!.pending, 2);
    final d = api.send<Object?>(b4Get, b4Path,
        call: b4Call(offline: const DiomanOfflineOptions(maxQueueSize: 1)));
    await b4Turn();
    expect((await b).reason, b4LiteralQueueFull);
    expect((await c).reason, b4LiteralQueueFull);
    api.plugin<DiomanOfflineApi>()!.flush();
    expect((await d).ok, isTrue);
    api.dispose();
    final fifo = testClient(plugins: [
      DiomanOffline<Result>(
          isOnline: () => false,
          onConnectivityChanged: stream.stream,
          maxQueueSize: 2)
    ]);
    final oldest = fifo.send<Object?>(b4Get, b4Path);
    final middle = fifo.send<Object?>(b4Get, b4Path);
    await b4Turn();
    final newest = fifo.send<Object?>(b4Get, b4Path);
    await b4Turn();
    expect((await oldest).reason, b4LiteralQueueFull);
    fifo.plugin<DiomanOfflineApi>()!.flush();
    expect((await middle).ok, isTrue);
    expect((await newest).ok, isTrue);
    fifo.dispose();
  });
}
