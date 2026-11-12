import '../support/response_contract.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/auth_test_helpers.dart';
import '../support/fake_clock.dart';
import '../support/fake_network.dart';
import '../support/helpers.dart';


/// 验证对应主题的行为与边界。
void main() {
  test(
      '[DiomanBreaker.new(clock)][DiomanFailureKind.breaker]'
      '[DiomanRetry.max × DiomanBreaker.failureThreshold] 每次尝试计数，打开返回 breaker 后停止重试，无需接线',
      () async {
    final net = FakeNetwork()..routes[b3Route] = [const FakeReply(status: 500)];
    final clock = FakeClock();
    final api = testClient(
        statusOf: businessStatus,
        network: net,
        clock: clock,
        plugins: [
          const DiomanBreaker(failureThreshold: 2),
          const DiomanRetry(max: 5)
        ]);
    expect(api.inspect().map((p) => p.$2), ['dioman:retry', 'dioman:breaker']);
    final r = await b3Finish(api.send<Object?>(b3ValueGet, b3Path), clock);
    expect(outcomeOf(r), diomanTestBreaker);
    expect(failureOf(r)?.reason, b3ValueOpen);
    expect(net.sends.length, 2);
    api.dispose();
  });
}
