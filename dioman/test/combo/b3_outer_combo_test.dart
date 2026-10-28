import 'dart:async';
import 'package:dioman/pipeline.dart';
import 'package:test/test.dart';
import '../support/pipeline/b3_helpers.dart';
import '../support/pipeline/fake_clock.dart';
import '../support/pipeline/fake_network.dart';
import '../support/pipeline/helpers.dart';
import '../support/pipeline/invariant_harness.dart';

/// 验证重发、重放与本地拒绝的外层收尾。
void main() {
  test(
      '[DiomanLoadingApi.activeCount × DiomanNotify.notify × DiomanRetry.max] 重试全过程 loading 一对，最终失败一次通知成功零次',
      () async {
    for (final success in [false, true]) {
      final net = FakeNetwork()
        ..routes[b3Route] = [
          const FakeReply(status: 500),
          FakeReply(status: success ? 200 : 500)
        ];
      final clock = FakeClock();
      final h = InvariantHarness(net, clock);
      final api = testClient(network: net, clock: clock, plugins: [
        h.loadingPlugin(),
        h.notifyPlugin(),
        const DiomanRetry(max: 1),
        ...h.probes()
      ]);
      final pending = h.track(1, api.send<Object?>(b3ValueGet, b3Path));
      await b3Turn();
      expect(h.loading.values.single, [true]);
      expect(api.plugin<DiomanLoadingApi>()!.activeCount, 1);
      clock.elapse(const Duration(seconds: 3));
      expect((await b3Finish(pending, clock)).ok, success);
      expect(h.loading.values.single, [true, false]);
      expect(h.notifications.length, success ? 0 : 1);
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
          return ctx
              .fail(const DiomanFailure(kind: DiomanKind.http, status: 401));
        }
        started.complete();
        await ctx.wait(gate.future);
        return ctx.cancelled()!;
      })
    ]);
    final pending = h.track(1, api.send<Object?>(b3ValueGet, b3Path));
    await started.future;
    expect(api.cancelAll(), 1);
    expect((await pending).kind, DiomanKind.cancel);
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
    expect(r.reason, b3ValueUnauthenticated);
    expect(h.notifications, {1: 1});
    expect(net.sends, isEmpty);
    h.assertAll(api);
    api.dispose();
  });
}
