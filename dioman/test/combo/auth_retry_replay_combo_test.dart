import '../support/response_contract.dart';
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
      final api = testClient(
          statusOf: businessStatus,
          network: net,
          clock: clock,
          plugins: [
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
}
