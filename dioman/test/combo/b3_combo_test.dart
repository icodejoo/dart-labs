import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/b3_helpers.dart';
import '../support/fake_clock.dart';
import '../support/fake_network.dart';
import '../support/helpers.dart';
import '../support/invariant_harness.dart';

/// 验证跨插件的不变量和重发边界。
void main() {
  test(
      '[DiomanBreaker.new(clock)][DiomanKind.breaker]'
      '[DiomanRetry.max × DiomanBreaker.failureThreshold] 每次尝试计数，打开返回 breaker 后停止重试，无需接线',
      () async {
    final net = FakeNetwork()..routes[b3Route] = [const FakeReply(status: 500)];
    final clock = FakeClock();
    final api = testClient(network: net, clock: clock, plugins: [
      const DiomanBreaker(failureThreshold: 2),
      const DiomanRetry(max: 5)
    ]);
    expect(api.inspect().map((p) => p.$2), ['dioman:retry', 'dioman:breaker']);
    final r = await b3Finish(api.send<Object?>(b3ValueGet, b3Path), clock);
    expect(r.kind, DiomanKind.breaker);
    expect(r.reason, b3ValueOpen);
    expect(net.sends.length, 2);
    api.dispose();
  });
  test(
      '[DiomanRetry.max × DiomanAuth.onRefresh] 刷新不占重试预算，isProtected 每次尝试一次，重放不重算',
      () async {
    for (final business in [false, true]) {
      final net = FakeNetwork()
        ..routes[b3Route] = [
          for (final status in [401, 500, 200])
            FakeReply(status: business ? 200 : status, body: {
              b3ValueCode: business && status != 200 ? status : 0,
              b3ValueData: null
            })
        ];
      final clock = FakeClock();
      var protected = 0;
      var refresh = 0;
      final api = testClient(network: net, clock: clock, plugins: [
        b3Auth(TestTokens(), protected: (r) {
          protected++;
          return true;
        }, refresh: (t, r) {
          refresh++;
          t.setTokens(accessToken: b3Fresh);
        }),
        const DiomanRetry(max: 1)
      ]);
      expect((await b3Finish(api.send<Object?>(b3ValueGet, b3Path), clock)).ok,
          isTrue);
      expect(protected, 2);
      expect(refresh, 1);
      expect(net.sends.length, 3);
      api.dispose();
    }
  });
  test('[DiomanAuth.onRefresh] 两刷新轮各一次，loading 包含刷新等待，notify 成功零次最终失败一次',
      () async {
    for (final success in [false, true]) {
      final net = FakeNetwork();
      final clock = FakeClock();
      final h = InvariantHarness(net, clock);
      final tm = TestTokens();
      final gates = <Completer<void>>[];
      final started = <Completer<void>>[];
      var round = 0;
      h.beginRefreshRound(1);
      h.beginRefreshRound(2);
      for (var i = 0; i < 2; i++) {
        gates.add(Completer<void>());
        started.add(Completer<void>());
      }
      final refresh = <DiomanAuthRefresh>[
        for (var i = 0; i < 2; i++)
          h.refreshInRound(i + 1, (t, r) async {
            started[i].complete();
            await gates[i].future;
            if (!success) throw StateError(b3ValueRefresh);
            t.setTokens(accessToken: b3Fresh);
          })
      ];
      final api = testClient(network: net, clock: clock, plugins: [
        h.loadingPlugin(),
        h.notifyPlugin(),
        b3Auth(tm, refresh: (t, r) => refresh[round](t, r)),
        ...h.probes()
      ]);
      for (var i = 0; i < 2; i++) {
        round = i;
        tm.setTokens(accessToken: b3Old);
        net.routes[b3Route] = [
          const FakeReply(status: 401),
          if (success) const FakeReply()
        ];
        net.counts.clear();
        final a = h.track(i * 2 + 1, api.send<Object?>(b3ValueGet, b3Path));
        await started[i].future;
        final b = h.track(i * 2 + 2, api.send<Object?>(b3ValueGet, b3Path));
        await b3Turn();
        expect(api.plugin<DiomanLoadingApi>()!.activeCount, 2);
        expect(h.loading.values.single.last, isTrue);
        gates[i].complete();
        final results = await Future.wait([a, b]);
        expect(results.every((r) => r.ok), success);
      }
      expect(h.refreshRounds, {1: 1, 2: 1});
      expect(h.notifications.length, success ? 0 : 4);
      h.assertAll(api);
      api.dispose();
    }
  });
  test(
      '[DiomanContext.markReplayable] retry 与 auth 各自保护嵌套请求体，Transformer 原地修改不污染重放',
      () async {
    for (final auth in [false, true]) {
      final net = FakeNetwork()
        ..routes['POST:$b3Path'] = [
          FakeReply(status: auth ? 401 : 500),
          const FakeReply()
        ];
      final clock = FakeClock();
      final h = InvariantHarness(net, clock);
      final api = testClient(network: net, clock: clock, plugins: [
        if (auth)
          b3Auth(TestTokens())
        else
          const DiomanRetry(max: 1, methods: [b3ValuePost5]),
        ...h.probes()
      ]);
      api.dio.transformer = B3Transformer();
      final body = {
        b3ValueItems: [
          {b3ValueN: 0}
        ]
      };
      final r = await b3Finish(
          h.track(
              1,
              api.send<Object?>(b3ValuePost5, b3Path,
                  data: body,
                  call:
                      const DiomanCall(headers: {invariantRequestHeader: 1}))),
          clock);
      expect(r.ok, isTrue);
      expect(net.sends, hasLength(2));
      expect(net.sends.map((s) => s.body), [
        {
          b3ValueItems: [
            {b3ValueN: 1}
          ]
        },
        {
          b3ValueItems: [
            {b3ValueN: 1}
          ]
        }
      ]);
      expect(body, {
        b3ValueItems: [
          {b3ValueN: 0}
        ]
      });
      h.assertAll(api);
      api.dispose();
    }
  });
  test('[DiomanRetry.option] 请求级关闭不恢复，旧请求失败不恢复别的逻辑调用', () async {
    final net = FakeNetwork()
      ..routes[b3Route] = [const FakeReply(status: 500), const FakeReply()];
    final clock = FakeClock();
    final api = testClient(
        network: net, clock: clock, plugins: [const DiomanRetry(max: 1)]);
    final a = await api.send<Object?>(b3ValueGet, b3Path,
        call: DiomanCall(options: {DiomanRetry.option: false}));
    expect(a.status, 500);
    expect(net.sends.length, 1);
    expect((await b3Finish(api.send<Object?>(b3ValueGet, b3Path), clock)).ok,
        isTrue);
    expect(a.status, 500);
    api.dispose();
  });
}
