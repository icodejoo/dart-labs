import '../support/constants.dart';
import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/fake_clock.dart';
import '../support/fake_network.dart';
import '../support/helpers.dart';
import '../support/invariant_harness.dart';

/// 夹具自身也须证明脚本、时间和不变量不会空跑。
void main() {
  test(
      '[DiomanClock.createTimer][DiomanClock.now]'
      '[DiomanClock] FakeClock 到期顺序、取消、重入和系统时钟', () async {
    final clock = FakeClock();
    final events = <int>[];
    final timer =
        clock.createTimer(const Duration(seconds: 2), () => events.add(2));
    final cancelled = clock.createTimer(Duration.zero, () => events.add(0))
      ..cancel();
    clock.createTimer(const Duration(seconds: 1), () {
      events.add(1);
      clock.createTimer(Duration.zero, () => events.add(3));
    });
    clock.elapse(const Duration(seconds: 3));
    expect(events, [1, 3, 2]);
    expect(timer.tick, 1);
    expect(cancelled.tick, 0);
    expect(clock.pendingTimers, 0);
    expect(clock.now().millisecondsSinceEpoch, 3000);
    const system = DiomanClock.system();
    expect(system.now().year, greaterThan(2020));
    final done = Completer<void>();
    system.createTimer(Duration.zero, done.complete);
    await done.future;
  });

  test('[Dioman.send] FakeNetwork 路由、序列、第 n 次失败、gate 和记录', () async {
    final net = FakeNetwork();
    final api = testClient(network: net);
    net.routes['GET:/s'] = [
      const FakeReply(status: 500),
      const FakeReply(body: {pipelineTestCode: 0, pipelineTestData: 9})
    ];
    expect((await api.send<Object?>(pipelineTestGetMethod, pipelineTestS)).kind,
        DiomanKind.http);
    expect(await api.get<int>(pipelineTestS), 9);
    expect(await api.get<int>(pipelineTestS), 9);
    net.failOn[4] = StateError('script');
    await expectLater(api.get<Object?>(pipelineTestFail), throwsStateError);
    final gate = Completer<void>();
    net.routes['GET:/gate'] = [FakeReply(gate: gate.future)];
    final pending = api.get<Object?>('/gate');
    await flush();
    expect(api.pending, 1);
    gate.complete();
    await pending;
    expect(net.sends.length, 5);
    net.close();
    expect(net.closed, isTrue);
  });

  test('[DiomanContext.id]' '[Dioman.send] InvariantHarness 拒绝空跑、重复落定和泄漏证据',
      () async {
    final network = FakeNetwork();
    final clock = FakeClock();
    final h = InvariantHarness(network, clock);
    final api = testClient(network: network, clock: clock, plugins: h.probes());
    expect(() => h.assertAll(api), throwsA(isA<TestFailure>()));
    await h.track(1, api.get<Object?>(pipelineTestRootPath));
    h.assertAll(api);
    h.settlements[1] = 2;
    expect(() => h.assertAll(api), throwsA(isA<TestFailure>()));
    h.settlements[1] = 1;
    h.loading[pipelineTestCallback] = [true, false];
    h.notifications[1] = 1;
    h.refreshRounds[1] = 1;
    h.assertAll(api);
    h.notifications[1] = 2;
    expect(() => h.assertAll(api), throwsA(isA<TestFailure>()));
    h.notifications.clear();
    h.loading[pipelineTestCallback] = [true];
    expect(() => h.assertAll(api), throwsA(isA<TestFailure>()));
  });
}
