import 'package:dioman/src/diagnostics.dart';
import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/b4_helpers.dart';
import '../support/fake_clock.dart';
import '../support/fake_network.dart';
import '../support/helpers.dart';

/// 终审累计超时与在线判定回归。
void main() {
  test('[DiomanShare.option] 连接五秒接收三十秒的跟随者在传输十秒完成时成功', () async {
    final clock = FakeClock();
    final gate = Completer<void>();
    final net = FakeNetwork()..routes[b4Route] = [FakeReply(gate: gate.future)];
    final api = testClient(
        clock: clock, network: net, plugins: [const DiomanShare<Result>()]);
    final leader = api.send<Object?>(b4Get, b4Path, call: b4Call(share: true));
    await b4Turn();
    var settled = false;
    final follower = api
        .send<Object?>(b4Get, b4Path,
            call: DiomanCall(
                key: b4Key,
                connectTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 30),
                options: {DiomanShare.option: true}))
        .then((r) {
      settled = true;
      return r;
    });
    await b4Turn();
    expect(clock.pendingTimers, 1);
    clock.elapse(const Duration(seconds: 10));
    await b4Turn();
    expect(settled, isFalse);
    gate.complete();
    expect((await leader).ok, isTrue);
    expect((await follower).ok, isTrue);
    expect(net.sends.length, 1);
    expect(clock.pendingTimers, 0);
    expect(api.cancellationSubscriptions, 0);
    expect(api.plugin<DiomanShareApi>()!.activeEntries, 0);
    api.dispose();
  });
  test('[DiomanShare.option] 连接接收或有请求体的发送阶段为无限时则整体不限时', () async {
    for (final stage in [
      (connect: null, receive: b4Tick, send: b4Tick, body: false),
      (connect: b4Tick, receive: null, send: b4Tick, body: false),
      (connect: Duration.zero, receive: b4Tick, send: b4Tick, body: false),
      (connect: b4Tick, receive: Duration.zero, send: b4Tick, body: false),
      (connect: b4Tick, receive: b4Tick, send: null, body: true),
      (connect: b4Tick, receive: b4Tick, send: Duration.zero, body: true),
    ]) {
      final clock = FakeClock();
      final gate = Completer<void>();
      final net = FakeNetwork()
        ..routes[b4Route] = [FakeReply(gate: gate.future)];
      final api = testClient(
          clock: clock, network: net, plugins: [const DiomanShare<Result>()]);
      final leader =
          api.send<Object?>(b4Get, b4Path, call: b4Call(share: true));
      await b4Turn();
      final follower = api.send<Object?>(b4Get, b4Path,
          data: stage.body ? {} : null,
          call: DiomanCall(
              key: b4Key,
              connectTimeout: stage.connect,
              receiveTimeout: stage.receive,
              sendTimeout: stage.send,
              options: {DiomanShare.option: true}));
      await b4Turn();
      expect(clock.pendingTimers, 0);
      clock.elapse(const Duration(days: 1));
      gate.complete();
      expect((await leader).ok, isTrue);
      expect((await follower).ok, isTrue);
      expect(net.sends.length, 1);
      expect(api.cancellationSubscriptions, 0);
      expect(api.plugin<DiomanShareApi>()!.activeEntries, 0);
      api.dispose();
    }
  });
  test('[DiomanShare.option] 请求体非空时累计发送超时且无请求体时忽略发送阶段', () async {
    for (final withBody in [false, true]) {
      final clock = FakeClock();
      final gate = Completer<void>();
      final net = FakeNetwork()
        ..routes[b4Route] = [FakeReply(gate: gate.future)];
      final api = testClient(
          clock: clock, network: net, plugins: [const DiomanShare<Result>()]);
      final leader =
          api.send<Object?>(b4Get, b4Path, call: b4Call(share: true));
      await b4Turn();
      var settled = false;
      final follower = api
          .send<Object?>(b4Get, b4Path,
              data: withBody ? {} : null,
              call: DiomanCall(
                  key: b4Key,
                  connectTimeout: b4Tick * 2,
                  receiveTimeout: b4Tick * 3,
                  sendTimeout: b4Tick * 4,
                  options: {DiomanShare.option: true}))
          .then((r) {
        settled = true;
        return r;
      });
      await b4Turn();
      clock.elapse(b4Tick * 5);
      await b4Turn();
      expect(settled, !withBody);
      if (withBody) {
        expect(clock.pendingTimers, 1);
        clock.elapse(b4Tick * 4);
      }
      expect((await follower).kind, DiomanKind.timeout);
      expect(net.sends.single.options.cancelToken!.isCancelled, isFalse);
      gate.complete();
      expect((await leader).ok, isTrue);
      expect(clock.pendingTimers, 0);
      expect(api.cancellationSubscriptions, 0);
      api.dispose();
    }
  });
  test(
      '[DiomanOffline.new(isOnline)][DiomanOffline.new(onConnectivityChanged)][DiomanOfflineApi.pending]'
      '[DiomanOffline.shouldQueue] 在线直接放行且不调用排队判定回调', () async {
    final stream = StreamController<bool>.broadcast(sync: true);
    addTearDown(stream.close);
    final net = FakeNetwork();
    var checks = 0;
    final api = testClient(network: net, plugins: [
      DiomanOffline<Result>(
          isOnline: () => true,
          onConnectivityChanged: stream.stream,
          shouldQueue: (_) {
            checks++;
            throw StateError(b4LiteralEmpty);
          })
    ]);
    expect((await api.send<Object?>(b4Get, b4Path)).ok, isTrue);
    expect(checks, 0);
    expect(net.sends.length, 1);
    expect(api.plugin<DiomanOfflineApi>()!.pending, 0);
    expect(api.cancellationSubscriptions, 0);
    api.dispose();
  });
  test(
      '[INV-context-lifecycle]'
      '[DiomanShare.policy × Dioman.cancelAll] 胜出后落败传输随订阅退出取消，之后取消或销毁幂等',
      () async {
    for (final policy in [DiomanSharePolicy.end, DiomanSharePolicy.race]) {
      for (final dispose in [false, true]) {
        final gate = Completer<void>();
        final net = FakeNetwork()
          ..routes[b4Route] = [FakeReply(gate: gate.future), const FakeReply()];
        final api =
            testClient(network: net, plugins: [const DiomanShare<Result>()]);
        final loser =
            api.send<Object?>(b4Get, b4Path, call: b4Call(share: policy));
        await b4Turn();
        final winner =
            api.send<Object?>(b4Get, b4Path, call: b4Call(share: policy));
        expect((await loser).ok, isTrue);
        expect((await winner).ok, isTrue);
        expect(api.pending, 0);
        expect(api.plugin<DiomanShareApi>()!.activeEntries, 0);
        final token = net.sends.first.options.cancelToken!;
        expect(token.isCancelled, isTrue);
        await b4Turn();
        if (dispose) {
          api.dispose();
        } else {
          expect(api.cancelAll(), 0);
        }
        expect(token.isCancelled, isTrue);
        gate.complete();
        await b4Turn();
        expect(api.cancelAll(), 0);
        expect(api.cancellationSubscriptions, 0);
        api.dispose();
      }
    }
  });
  test(
      '[DiomanResponseFactory.derive]'
      '[DiomanCache.clone] 显式缓存失败时深拷贝隔离来源首返回和后续命中数据', () async {
    for (final policy in DiomanCachePolicy.values) {
      final body = <int, dynamic>{
        1: <int>[2]
      };
      final api = testClient(plugins: [
        DiomanCache<Result>(
            persist: B4Persist(),
            cachePolicy: policy,
            shouldStore: (_) => true,
            clone: DiomanClonePolicy.deep),
        TestPlugin(b4LiteralSource,
            stage: DiomanStage.source,
            handler: (ctx, next) async => ctx.fail(DiomanFailure(
                kind: DiomanKind.biz,
                status: 409,
                reason: b4LiteralSource,
                data: body)))
      ]);
      final first =
          await api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true));
      body[1][0] = 9;
      (first.data as Map)[1][0] = 7;
      final hit =
          await api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true));
      expect(hit.data, {
        1: [2]
      });
      expect([hit.ok, hit.kind, hit.status, hit.reason],
          [false, DiomanKind.biz, 409, b4LiteralSource]);
      (hit.data as Map)[1][0] = 8;
      expect(
          (await api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true)))
              .data,
          {
            1: [2]
          });
      expect(api.plugin<DiomanCacheApi>()!.pendingWrites, 0);
      api.dispose();
    }
  });
}
