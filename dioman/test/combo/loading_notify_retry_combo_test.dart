import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/auth_test_helpers.dart';
import '../support/fake_clock.dart';
import '../support/fake_network.dart';
import '../support/helpers.dart';
import '../support/invariant_harness.dart';


/// 验证对应主题的行为与边界。
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
}
