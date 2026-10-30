import 'package:dioman/src/diagnostics.dart';
import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/b4_helpers.dart';
import '../support/fake_clock.dart';
import '../support/fake_network.dart';
import '../support/helpers.dart';

/// 每客户端隔离、取消结果归属及在途生命周期。
void main() {
  test('[DiomanSharePolicy.end] 最新调用取消后撤回，旧请求继续产生自己的结果', () async {
    final old = Completer<void>();
    final latest = Completer<void>();
    final token = CancelToken();
    final net = FakeNetwork()
      ..routes[b4Route] = [
        FakeReply(gate: old.future),
        FakeReply(gate: latest.future)
      ];
    final api =
        testClient(network: net, plugins: [const DiomanShare<Result>()]);
    final a = api.send<Object?>(b4Get, b4Path,
        call: b4Call(share: DiomanSharePolicy.end));
    final b = api.send<Object?>(b4Get, b4Path,
        call: DiomanCall(
            key: b4Key,
            cancelToken: token,
            options: {DiomanShare.option: DiomanSharePolicy.end}));
    await b4Turn();
    token.cancel();
    expect((await b).kind, DiomanKind.cancel);
    old.complete();
    expect((await a).kind, DiomanKind.ok);
    latest.complete();
    await b4Turn();
    expect(api.plugin<DiomanShareApi>()!.activeEntries, 0);
  });
  test(
      '[INV-source-diagnostics]'
      '[DiomanCache.shouldStore] 取消的在途响应不缓存且屏障回收', () async {
    final gate = Completer<void>();
    final net = FakeNetwork()..routes[b4Route] = [FakeReply(gate: gate.future)];
    final api = testClient(network: net, plugins: [
      DiomanCache<Result>(shouldStore: (_) => throw StateError(b4LiteralEmpty))
    ]);
    final pending = api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true));
    await b4Turn();
    api.cancelAll();
    expect((await pending).kind, DiomanKind.cancel);
    gate.complete();
    await b4Turn();
    expect(api.plugin<DiomanCacheApi>()!.entryCount, 0);
    expect(api.plugin<DiomanCacheApi>()!.pendingWrites, 0);
  });
  test('[DiomanPlugin.setup] 同一 source 配置装两客户端，活动表缓存队列独立', () async {
    var online = true;
    final stream = StreamController<bool>.broadcast(sync: true);
    addTearDown(stream.close);
    final plugins = <DiomanPlugin<Result>>[
      const DiomanShare<Result>(),
      const DiomanCache<Result>(),
      DiomanOffline<Result>(
          isOnline: () => online, onConnectivityChanged: stream.stream)
    ];
    final n1 = FakeNetwork();
    final n2 = FakeNetwork();
    final a = testClient(network: n1, plugins: plugins);
    final b = testClient(network: n2, plugins: plugins);
    await a.send<Object?>(b4Get, b4Path,
        call: b4Call(cache: true, share: true));
    await b.send<Object?>(b4Get, b4Path,
        call: b4Call(cache: true, share: true));
    expect(n1.sends.length, 1);
    expect(n2.sends.length, 1);
    await a.plugin<DiomanCacheApi>()!.clear();
    expect(b.plugin<DiomanCacheApi>()!.entryCount, 1);
    online = false;
    final pausedA = a.send<Object?>(b4Get, b4Path);
    final pausedB = b.send<Object?>(b4Get, b4Path);
    await b4Turn();
    a.eject(DiomanOffline.pluginName);
    expect((await pausedA).reason, b4LiteralDisposed);
    expect(b.plugin<DiomanOfflineApi>()!.pending, 1);
    stream.add(true);
    expect((await pausedB).ok, isTrue);
    a.dispose();
    b.dispose();
  });
  test(
      '[DiomanCall.connectTimeout][DiomanCall.receiveTimeout]'
      '[DiomanSharePolicy.end × DiomanOffline.maxWait] 订阅者超时撤回并取消自己的底层排队',
      () async {
    final clock = FakeClock();
    final stream = StreamController<bool>.broadcast(sync: true);
    addTearDown(stream.close);
    final net = FakeNetwork();
    final api = testClient(network: net, clock: clock, plugins: [
      const DiomanShare<Result>(),
      DiomanOffline<Result>(
          isOnline: () => false,
          onConnectivityChanged: stream.stream,
          maxWait: const Duration(seconds: 5))
    ]);
    final pending = api.send<Object?>(b4Get, b4Path,
        call: DiomanCall(
            connectTimeout: b4Tick,
            receiveTimeout: b4Tick,
            options: {DiomanShare.option: DiomanSharePolicy.end}));
    await b4Turn();
    clock.elapse(b4Tick * 2);
    expect((await pending).kind, DiomanKind.timeout);
    await b4Turn();
    expect(api.plugin<DiomanOfflineApi>()!.pending, 0);
    stream.add(true);
    await b4Turn();
    expect(net.sends.length, 0);
    expect(api.plugin<DiomanOfflineApi>()!.pending, 0);
    expect(clock.pendingTimers, 0);
  });
}
