import 'package:dioman/src/diagnostics.dart';
import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/b4_helpers.dart';
import '../support/fake_clock.dart';
import '../support/fake_network.dart';
import '../support/helpers.dart';
import '../support/invariant_harness.dart';

/// 其余迁移行的 key、外层收尾与归一化组合。
void main() {
  test('[DiomanCache.shouldStore] 归一化判定表与请求级覆盖优先级', () async {
    for (final pluginJudge in <bool?>[null, false, true]) {
      for (final requestJudge in <bool?>[null, false, true]) {
        for (final success in [false, true]) {
          final net = FakeNetwork()
            ..routes[b4Route] = [
              FakeReply(body: {
                b4LiteralCode: success ? 0 : 500,
                b4LiteralData: {b4LiteralV: 1}
              })
            ];
          final seen = <DiomanResponse<dynamic>>[];
          final api = testClient(network: net, plugins: [
            DiomanCache<Result>(
                shouldStore: pluginJudge == null
                    ? null
                    : (r) {
                        seen.add(r);
                        return pluginJudge;
                      })
          ]);
          final call = b4Call(
              cache: DiomanCacheOptions(
                  shouldStore: requestJudge == null
                      ? null
                      : (r) {
                          seen.add(r);
                          return requestJudge;
                        }));
          final a = await api.send<Object?>(b4Get, b4Path, call: call);
          final b = await api.send<Object?>(b4Get, b4Path, call: call);
          expect(a.ok, success);
          expect(b.ok, success);
          expect(net.sends.length,
              (requestJudge ?? pluginJudge ?? success) ? 1 : 2);
          expect(
              seen.every((r) =>
                  r.data is Map && (r.data as Map).containsKey(b4LiteralV)),
              isTrue);
          expect(api.plugin<DiomanCacheApi>()!.pendingWrites, 0);
        }
      }
    }
  });
  test(
      '[DiomanCall.envelope][Envelope.code][Envelope.data]'
      '[DiomanResponseFactory.envelope × DiomanCache.option] 信封开关自定义成功和单层解包',
      () async {
    for (final mode in [
      b4LiteralPlain,
      b4LiteralDisabled,
      b4LiteralCallDisabled,
      b4LiteralSuccess,
      b4LiteralField,
      b4LiteralPredicate,
      b4LiteralNested,
      b4LiteralScalar
    ]) {
      final Object body = mode == b4LiteralPlain
          ? {b4LiteralCode: 500}
          : mode == b4LiteralScalar
              ? b4LiteralPlain
              : mode == b4LiteralNested
                  ? {
                      b4LiteralCode: 0,
                      b4LiteralData: {
                        b4LiteralCode: 0,
                        b4LiteralData: b4LiteralNested
                      }
                    }
                  : {
                      b4LiteralCode: 500,
                      b4LiteralRet: 0,
                      b4LiteralData: b4LiteralValue
                    };
      final net = FakeNetwork()..routes[b4Route] = [FakeReply(body: body)];
      final api = testClient(
          network: net,
          response: DiomanResponseFactory<Result>(
              envelope: mode == b4LiteralDisabled
                  ? null
                  : mode == b4LiteralField
                      ? const Envelope(code: b4LiteralRet)
                      : const Envelope(),
              isSuccess: mode == b4LiteralSuccess ? (_) => true : null,
              isEnvelope: mode == b4LiteralPredicate ? (_) => false : null),
          plugins: [const DiomanShare<Result>(), const DiomanCache<Result>()]);
      final call = DiomanCall(
          envelope: mode == b4LiteralCallDisabled ? false : null,
          options: {DiomanCache.option: true, DiomanShare.option: true});
      final a = await api.send<Object?>(b4Get, b4Path, call: call);
      final b = await api.send<Object?>(b4Get, b4Path, call: call);
      expect(a.ok, isTrue);
      expect(b.ok, isTrue);
      expect(net.sends.length, 1);
      if (mode == b4LiteralNested) {
        expect(b.data, {b4LiteralCode: 0, b4LiteralData: b4LiteralNested});
      }
    }
  });
  test(
      '[DiomanKeyOptions.namespace × DiomanCache.option × DiomanShare.option] 账号隔离和 prepare 后请求体区分',
      () async {
    var account = b4LiteralA;
    final gate = Completer<void>();
    final net = FakeNetwork()..routes[b4Route] = [FakeReply(gate: gate.future)];
    final api = testClient(
        network: net,
        key: DiomanKeyOptions(namespace: () => account),
        plugins: [const DiomanShare<Result>(), const DiomanCache<Result>()]);
    final call = b4Call(cache: true, share: true, key: null);
    final a = api.send<Object?>(b4Get, b4Path, call: call);
    await b4Turn();
    account = b4LiteralB;
    final b = api.send<Object?>(b4Get, b4Path, call: call);
    await b4Turn();
    expect(net.sends.length, 2);
    gate.complete();
    await a;
    await b;
    account = b4LiteralA;
    await api.send<Object?>(b4Get, b4Path, call: call);
    expect(net.sends.length, 2);
    for (final body in [
      {b4LiteralX: 1},
      {b4LiteralX: 2},
      {b4LiteralX: 1}
    ]) {
      await api.send<Object?>(b4Get, b4Path, data: body, call: call);
    }
    expect(net.sends.length, 4);
  });
  test(
      '[DiomanLoadingApi.activeCount × DiomanCache.option × DiomanShare.option] 缓存命中和跟随者均计逻辑请求，失败释放外层',
      () async {
    for (final policy in DiomanSharePolicy.values) {
      final clock = FakeClock();
      final gate = Completer<void>();
      final net = FakeNetwork()
        ..routes[b4Route] = [FakeReply(status: 500, gate: gate.future)];
      final h = InvariantHarness(net, clock);
      final api = testClient(network: net, clock: clock, plugins: [
        ...h.probes(),
        h.loadingPlugin(),
        h.notifyPlugin(),
        const DiomanShare<Result>(retries: 0),
        const DiomanCache<Result>()
      ]);
      final a = h.track(
          1,
          api.send<Object?>(b4Get, b4Path,
              call: b4Call(share: policy, cache: true)));
      final b = h.track(
          2,
          api.send<Object?>(b4Get, b4Path,
              call: b4Call(share: policy, cache: true)));
      await b4Turn();
      expect(api.plugin<DiomanLoadingApi>()!.activeCount, 2);
      gate.complete();
      await a;
      await b;
      await b4Turn();
      h.assertAll(api);
      expect(h.notifications.values, everyElement(1));
    }
    final store = B4Persist()..error = StateError('storage');
    final values = <bool>[];
    final api = testClient(plugins: [
      DiomanLoading<Result>(onChanged: values.add),
      DiomanCache<Result>(
          persist: store, cachePolicy: DiomanCachePolicy.persist)
    ]);
    await expectLater(
        api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true)),
        throwsStateError);
    expect(values, [true, false]);
    expect(api.plugin<DiomanLoadingApi>()!.activeCount, 0);
    final hits = <bool>[];
    final cached = testClient(plugins: [
      DiomanLoading<Result>(onChanged: hits.add),
      const DiomanCache<Result>()
    ]);
    await cached.send<Object?>(b4Get, b4Path, call: b4Call(cache: true));
    await cached.send<Object?>(b4Get, b4Path, call: b4Call(cache: true));
    expect(hits, [true, false, true, false]);
  });
  test(
      '[DiomanShare.methods]'
      '[DiomanSharePolicy.start] FormData 首发取消跟随者沿用传输，嵌套信封只拆一层', () async {
    final gate = Completer<void>();
    final net = FakeNetwork()
      ..routes['POST:$b4Path'] = [
        FakeReply(body: {
          b4LiteralCode: 0,
          b4LiteralData: {b4LiteralCode: 0, b4LiteralData: b4LiteralNested}
        }, gate: gate.future)
      ];
    final token = CancelToken();
    final api = testClient(network: net, plugins: [
      const DiomanShare<Result>(methods: {b4LiteralPOST})
    ]);
    final a = api.send<Object?>(b4LiteralPOST, b4Path,
        data: FormData.fromMap({b4LiteralField: b4LiteralValue}),
        call: DiomanCall(
            key: b4Key,
            cancelToken: token,
            options: {DiomanShare.option: true}));
    final b = api.send<Object?>(b4LiteralPOST, b4Path,
        data: FormData.fromMap({b4LiteralField: b4LiteralValue}),
        call: b4Call(share: true));
    await b4Turn();
    token.cancel();
    expect((await a).kind, DiomanKind.cancel);
    gate.complete();
    expect((await b).data, {b4LiteralCode: 0, b4LiteralData: b4LiteralNested});
    expect(net.sends.length, 1);
  });
  test(
      '[DiomanCache.expires]'
      '[DiomanCache.clock] 插件级 DiomanClock 控制 TTL，零负有效期不钳制', () async {
    for (final ttl in [Duration.zero, const Duration(seconds: -1), b4Tick]) {
      final clock = FakeClock();
      final net = FakeNetwork();
      final api = testClient(
          network: net,
          plugins: [DiomanCache<Result>(clock: clock, expires: ttl)]);
      await api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true));
      clock.elapse(b4Tick);
      await api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true));
      expect(net.sends.length, 2);
    }
  });
}
