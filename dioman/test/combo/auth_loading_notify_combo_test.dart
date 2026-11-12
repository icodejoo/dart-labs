import '../support/response_contract.dart';
import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/auth_test_helpers.dart';
import '../support/fake_clock.dart';
import '../support/fake_network.dart';
import '../support/helpers.dart';
import '../support/invariant_harness.dart';


/// 验证对应主题的行为与边界。
void main() {
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
      final api = testClient(
          statusOf: businessStatus,
          network: net,
          clock: clock,
          plugins: [
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
  test('[Dioman.cancelAll] 重放等待时 cancelAll 完整注销，loading 配对且 notify 不通知',
      () async {
    final net = FakeNetwork();
    final clock = FakeClock();
    final h = InvariantHarness(net, clock);
    var sends = 0;
    final started = Completer<void>();
    final gate = Completer<void>();
    final api = testClient(network: net, clock: clock, plugins: [
      h.loadingPlugin(),
      h.notifyPlugin(),
      b3Auth(TestTokens()),
      ...h.probes(),
      TestPlugin(b3ValueResult, stage: DiomanStage.source,
          handler: (ctx, next) async {
        sends++;
        if (sends == 1) {
          return scriptedResult(ctx, diomanTestHttp, status: 401);
        }
        started.complete();
        await ctx.wait(gate.future);
        return ctx.cancelled()!;
      })
    ]);
    final pending = h.track(1, api.send<Object?>(b3ValueGet, b3Path));
    await started.future;
    expect(api.cancelAll(), 1);
    expect(outcomeOf((await pending)), diomanTestCancel);
    expect(sends, 2);
    expect(h.notifications, isEmpty);
    h.assertAll(api);
    gate.complete();
    api.dispose();
  });
  test('[DiomanAuth.onAccessDenied] 本地无凭证拒绝也释放 loading 与 pending，最终通知一次',
      () async {
    final net = FakeNetwork();
    final clock = FakeClock();
    final h = InvariantHarness(net, clock);
    final api = testClient(network: net, clock: clock, plugins: [
      h.loadingPlugin(),
      h.notifyPlugin(),
      b3Auth(TestTokens(null)),
      ...h.probes()
    ]);
    final r = await h.track(1, api.send<Object?>(b3ValueGet, b3Path));
    expect(failureOf(r)?.reason, b3ValueUnauthenticated);
    expect(h.notifications, {1: 1});
    expect(net.sends, isEmpty);
    h.assertAll(api);
    api.dispose();
  });
}
