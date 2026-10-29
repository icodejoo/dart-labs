import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/b3_helpers.dart';
import '../support/b4_helpers.dart';
import '../support/fake_clock.dart';
import '../support/fake_network.dart';
import '../support/helpers.dart';
import '../support/invariant_harness.dart';

/// 内部重试独立于外层 retry 的重放保护和首发配置归属。
void main() {
  test(
      '[DiomanShareOptions.methods]'
      '[DiomanShare.retries] 内部重放独立保护 I7 嵌套请求体，首发次数与间隔覆盖', () async {
    final clock = FakeClock();
    final first = Completer<void>();
    final net = FakeNetwork()
      ..routes['POST:$b4Path'] = [
        FakeReply(status: 500, gate: first.future),
        const FakeReply(status: 500),
        const FakeReply()
      ];
    final h = InvariantHarness(net, clock);
    final api = testClient(network: net, clock: clock, plugins: [
      ...h.probes(),
      const DiomanShare<Result>(methods: {b4LiteralPOST})
    ]);
    api.dio.transformer = B3Transformer();
    final body = {
      b4LiteralItems: [
        {b4LiteralN: 0}
      ]
    };
    final a = h.track(
        1,
        api.send<Object?>(b4LiteralPOST, b4Path,
            data: body,
            call: DiomanCall(key: b4Key, headers: {
              invariantRequestHeader: 1
            }, options: {
              DiomanShare.option: const DiomanShareOptions(
                  policy: DiomanSharePolicy.retry, retries: 2, interval: b4Tick)
            })));
    final b = h.track(
        2,
        api.send<Object?>(b4LiteralPOST, b4Path,
            data: body,
            call: b4Call(
                share: const DiomanShareOptions(
                    policy: DiomanSharePolicy.retry,
                    retries: 0,
                    interval: Duration(days: 1)))));
    await b4Turn();
    first.complete();
    await b4Turn();
    expect(clock.pendingTimers, 1);
    clock.elapse(b4Tick);
    await b4Turn();
    expect(net.sends.length, 2);
    clock.elapse(b4Tick);
    expect((await b3Finish(a, clock)).ok, isTrue);
    expect((await b).ok, isTrue);
    expect(net.sends.length, 3);
    expect(body, {
      b4LiteralItems: [
        {b4LiteralN: 0}
      ]
    });
    h.assertAll(api);
  });
  test(
      '[DiomanShareOptions.policy][DiomanShareOptions.retries]'
      '[DiomanShare.retries] 默认内部重试三次，零负次数不重发', () async {
    for (final count in <int?>[null, 0, -1]) {
      final net = FakeNetwork()
        ..routes[b4Route] = [const FakeReply(status: 500)];
      final api =
          testClient(network: net, plugins: [const DiomanShare<Result>()]);
      expect(
          (await api.send<Object?>(b4Get, b4Path,
                  call: b4Call(
                      share: DiomanShareOptions(
                          policy: DiomanSharePolicy.retry, retries: count))))
              .httpStatus,
          500);
      expect(net.sends.length, count == null ? 4 : 1);
    }
  });
}
