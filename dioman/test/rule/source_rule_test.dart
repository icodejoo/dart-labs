import 'dart:async';
import 'package:dioman/pipeline.dart';
import 'package:test/test.dart';
import '../support/pipeline/b4_helpers.dart';
import '../support/pipeline/fake_clock.dart';
import '../support/pipeline/fake_network.dart';
import '../support/pipeline/helpers.dart';

/// 四个 source 插件的公开规则。
void main() {
  test('[DiomanMock.routes] 默认生效，内联数据经工厂识别 business 且零触网', () async {
    final net = FakeNetwork();
    final api = testClient(network: net, plugins: [
      DiomanMock<Result>(routes: {
        b4Route: (_) => {b4LiteralCode: 401, b4LiteralData: null}
      })
    ]);
    expect((await api.send<Object?>(b4Get, b4Path)).kind, DiomanKind.biz);
    expect(net.sends, isEmpty);
    expect(
        (await api.send<Object?>(b4Get, b4Path, call: b4Call(mock: false))).ok,
        isTrue);
    expect(net.sends.length, 1);
  });
  test('[DiomanMock.mockUrl] 404 与 network 默认回落，500 保留，缺地址 debug 告警', () async {
    for (final status in [404, 500]) {
      final net = FakeNetwork()
        ..routes['GET:https://mock.test$b4Path'] = [FakeReply(status: status)];
      final api = testClient(
          network: net,
          plugins: [const DiomanMock<Result>(mockUrl: 'https://mock.test/')]);
      final r = await api.send<Object?>(b4Get, b4Path);
      expect(r.httpStatus, status == 404 ? 200 : 500);
      expect(net.sends.length, status == 404 ? 2 : 1);
    }
    final logs = <String>[];
    final api =
        testClient(debug: logs.add, plugins: [const DiomanMock<Result>()]);
    await api.send<Object?>(b4Get, b4Path);
    expect(logs.join(), contains('mockUrl'));
  });
  test('[DiomanShare.policy] start 只发一次，跟随者为相同只读 R，省略不开启', () async {
    final gate = Completer<void>();
    final net = FakeNetwork()..routes[b4Route] = [FakeReply(gate: gate.future)];
    final api =
        testClient(network: net, plugins: [const DiomanShare<Result>()]);
    final a = api.send<Object?>(b4Get, b4Path, call: b4Call(share: true));
    final b = api.send<Object?>(b4Get, b4Path, call: b4Call(share: true));
    await b4Turn();
    expect(net.sends.length, 1);
    gate.complete();
    final results = await Future.wait([a, b]);
    expect(identical(results[0], results[1]), isTrue);
    await api.send<Object?>(b4Get, b4Path);
    await api.send<Object?>(b4Get, b4Path);
    expect(net.sends.length, 3);
  });
  test('[DiomanShare.policy] end 最新失败归所有，race 首成功与全失败最后结果', () async {
    for (final policy in [DiomanSharePolicy.end, DiomanSharePolicy.race]) {
      for (final successful in [false, true]) {
        final first = Completer<void>();
        final second = Completer<void>();
        final net = FakeNetwork()
          ..routes[b4Route] = [
            FakeReply(status: 500, gate: first.future),
            FakeReply(status: successful ? 200 : 503, gate: second.future)
          ];
        final api =
            testClient(network: net, plugins: [const DiomanShare<Result>()]);
        final a = api.send<Object?>(b4Get, b4Path, call: b4Call(share: policy));
        final b = api.send<Object?>(b4Get, b4Path, call: b4Call(share: policy));
        await b4Turn();
        first.complete();
        await b4Turn();
        second.complete();
        final r = await Future.wait([a, b]);
        expect(
            r.map((r) => r.httpStatus), everyElement(successful ? 200 : 503));
        expect(identical(r[0], r[1]), isTrue);
      }
    }
  });
  test('[DiomanShare.retries] 内部 retry 只暴露最终结果，间隔计时可清理', () async {
    final clock = FakeClock();
    final net = FakeNetwork()
      ..routes[b4Route] = [const FakeReply(status: 500), const FakeReply()];
    final api = testClient(network: net, clock: clock, plugins: [
      const DiomanShare<Result>(
          policy: DiomanSharePolicy.retry, interval: b4Tick)
    ]);
    final a = api.send<Object?>(b4Get, b4Path, call: b4Call(share: true));
    final b = api.send<Object?>(b4Get, b4Path, call: b4Call(share: true));
    await b4Turn();
    expect(clock.pendingTimers, 1);
    clock.elapse(b4Tick);
    expect((await a).ok, isTrue);
    expect((await b).ok, isTrue);
    expect(net.sends.length, 2);
    expect(clock.pendingTimers, 0);
  });
  test(
      '[DiomanCache.option] true 继承 clone expires shouldCache，Duration 与覆盖选项生效',
      () async {
    final net = FakeNetwork();
    final clock = FakeClock();
    var clones = 0;
    final api = testClient(network: net, clock: clock, plugins: [
      DiomanCache<Result>(
          expires: b4Tick,
          clone: (Object? data) {
            clones++;
            return data;
          },
          shouldCache: (_) => true)
    ]);
    final call = b4Call(cache: true);
    await api.send<Object?>(b4Get, b4Path, call: call);
    await api.send<Object?>(b4Get, b4Path, call: call);
    expect(net.sends.length, 1);
    expect(clones, 3);
    clock.elapse(b4Tick);
    await api.send<Object?>(b4Get, b4Path,
        call: b4Call(cache: const Duration(seconds: 2)));
    clock.elapse(b4Tick);
    await api.send<Object?>(b4Get, b4Path, call: call);
    expect(net.sends.length, 2);
    await api.plugin<DiomanCacheApi>()!.remove(b4Key);
    await api.send<Object?>(b4Get, b4Path,
        call: b4Call(
            cache: const DiomanCacheOptions(clone: DiomanClonePolicy.none)));
    expect(clones, 6);
    expect(net.sends.length, 3);
    await api.plugin<DiomanCacheApi>()!.clear();
    expect(api.plugin<DiomanCacheApi>()!.entryCount, 0);
  });
  test('[DiomanCache.shouldStore] business 失败不存储且不经过用户 clone，GET HEAD 默认允许',
      () async {
    final net = FakeNetwork()
      ..routes[b4Route] = [
        const FakeReply(body: {b4LiteralCode: 500, b4LiteralData: null})
      ];
    final api = testClient(network: net, plugins: [
      DiomanCache<Result>(clone: (Object? data) => throw StateError('不该克隆'))
    ]);
    for (var i = 0; i < 2; i++) {
      expect(
          (await api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true)))
              .kind,
          DiomanKind.biz);
    }
    expect(net.sends.length, 2);
    expect(api.plugin<DiomanCacheApi>()!.pendingWrites, 0);
    final head = testClient(
        network: net,
        plugins: [const DiomanCache<Result>(clone: DiomanClonePolicy.none)]);
    await head.send<Object?>(b4LiteralHEAD, b4Path, call: b4Call(cache: true));
    await head.send<Object?>(b4LiteralHEAD, b4Path, call: b4Call(cache: true));
    expect(net.sends.length, 3);
  });
  test('[DiomanCache.cachePolicy] memo persist both 分层，持久化命中提升且惰性过期', () async {
    for (final policy in DiomanCachePolicy.values) {
      final store = B4Persist();
      final clock = FakeClock();
      final net = FakeNetwork();
      final api = testClient(network: net, clock: clock, plugins: [
        DiomanCache<Result>(
            persist: store, cachePolicy: policy, expires: b4Tick)
      ]);
      await api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true));
      await api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true));
      expect(net.sends.length, 1);
      expect(store.writes, policy == DiomanCachePolicy.memo ? 0 : 1);
      clock.elapse(b4Tick);
      await api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true));
      expect(net.sends.length, 2);
      await api.plugin<DiomanCacheApi>()!.remove(b4Key);
      await api.plugin<DiomanCacheApi>()!.clear();
      expect(store.values, isEmpty);
      expect(api.plugin<DiomanCacheApi>()!.pendingWrites, 0);
    }
  });
  test('[DiomanOfflineApi.flush] 离线排队恢复和手动 flush，shouldQueue false 放行',
      () async {
    final stream = StreamController<bool>.broadcast(sync: true);
    addTearDown(stream.close);
    var online = false;
    final net = FakeNetwork();
    final api = testClient(network: net, plugins: [
      DiomanOffline<Result>(
          isOnline: () => online, onConnectivityChanged: stream.stream)
    ]);
    final a = api.send<Object?>(b4Get, b4Path);
    await b4Turn();
    expect(api.plugin<DiomanOfflineApi>()!.pending, 1);
    expect(net.sends, isEmpty);
    stream.add(false);
    await b4Turn();
    expect(net.sends, isEmpty);
    online = true;
    stream.add(true);
    expect((await a).ok, isTrue);
    online = false;
    final b = api.send<Object?>(b4Get, b4Path);
    await b4Turn();
    api.plugin<DiomanOfflineApi>()!.flush();
    expect((await b).ok, isTrue);
    await api.send<Object?>(b4Get, b4Path,
        call: b4Call(offline: DiomanOfflineOptions(shouldQueue: (_) => false)));
    online = true;
    await api.send<Object?>(b4Get, b4Path);
    expect(net.sends.length, 4);
    api.dispose();
  });
}
