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
      final api = testClient(
          statusOf: businessStatus,
          network: net,
          clock: clock,
          plugins: [
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
}
