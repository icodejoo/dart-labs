import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import 'b3_helpers.dart';
import 'b4_helpers.dart';
import 'b4_migration_scenarios.dart';
import 'fake_clock.dart';
import 'fake_network.dart';
import 'helpers.dart';

/// end 最新成功与 race 仍在途成功压过旧失败，外层不提前重试或刷新。
Future<void> b4RetryArbitration({required DiomanSharePolicy policy}) async {
  final clock = FakeClock();
  final aGate = Completer<void>();
  final bGate = Completer<void>();
  var finished = false;
  final net = FakeNetwork()
    ..routes[b4Route] = [
      const FakeReply(status: 500),
      FakeReply(
          status: policy == DiomanSharePolicy.end ? 200 : 500,
          body: b4LiteralA,
          gate: aGate.future),
      FakeReply(body: b4LiteralB, gate: bGate.future)
    ];
  final api = testClient(network: net, clock: clock, plugins: [
    DiomanRetry<Result>(max: 1, delay: (_, __, ___) => Duration.zero),
    const DiomanShare<Result>()
  ]);
  final a =
      api.send<Object?>(b4Get, b4Path, call: b4Call(share: policy)).then((r) {
    finished = true;
    return r;
  });
  await b4Turn();
  expect(clock.pendingTimers, 1);
  clock.elapse(Duration.zero);
  await b4Turn();
  expect(net.sends.length, 2);
  final b = api.send<Object?>(b4Get, b4Path, call: b4Call(share: policy));
  await b4Turn();
  expect(net.sends.length, 3);
  aGate.complete();
  await b4Turn();
  expect(finished, isFalse);
  bGate.complete();
  expect((await a).data, b4LiteralB);
  expect((await b).data, b4LiteralB);
  await b4Clean(api);
}

/// 最新成功覆盖旧鉴权失败，不提前刷新或重试。
Future<void> b4LatestSuccessSkipsRefresh() async {
  final aGate = Completer<void>();
  final bGate = Completer<void>();
  final net = FakeNetwork()
    ..routes[b4Route] = [
      FakeReply(status: 401, gate: aGate.future),
      FakeReply(gate: bGate.future)
    ];
  final api = testClient(network: net, plugins: [
    DiomanRetry<Result>(
        max: 1,
        shouldRetry: (r, n) => r.ok ? false : throw StateError('不得提前重试')),
    b3Auth(TestTokens(), refresh: (_, __) => throw StateError('不得刷新')),
    const DiomanShare<Result>()
  ]);
  const policy = DiomanSharePolicy.end;
  var finished = false;
  final a =
      api.send<Object?>(b4Get, b4Path, call: b4Call(share: policy)).then((r) {
    finished = true;
    return r;
  });
  final b = api.send<Object?>(b4Get, b4Path, call: b4Call(share: policy));
  await b4Turn();
  aGate.complete();
  await b4Turn();
  expect(finished, isFalse);
  bGate.complete();
  expect((await a).ok, isTrue);
  expect((await b).ok, isTrue);
  expect(net.sends.length, 2);
  await b4Clean(api);
}

/// 新调用加入外层 retry 的当前尝试，共享表不跨尝试占位。
Future<void> b4CallerJoinsCurrentRetry() async {
  final clock = FakeClock();
  final gate = Completer<void>();
  final secondStarted = Completer<void>();
  final net = FakeNetwork(onSend: (s) {
    if (s.options.path == b4Path && !secondStarted.isCompleted) {
      secondStarted.complete();
    }
  })
    ..routes[b4Route] = [
      const FakeReply(status: 500),
      FakeReply(gate: gate.future)
    ];
  final api = testClient(clock: clock, network: net, plugins: [
    DiomanRetry<Result>(max: 1, delay: (_, __, ___) => Duration.zero),
    const DiomanShare<Result>(retries: 0)
  ]);
  final a = api.send<Object?>(b4Get, b4Path,
      call: b4Call(share: DiomanSharePolicy.retry));
  await secondStarted.future;
  await b4Turn();
  clock.elapse(Duration.zero);
  await b4Turn();
  expect(net.sends.length, 2);
  final b = api.send<Object?>(b4Get, b4Path,
      call: b4Call(share: DiomanSharePolicy.retry));
  await b4Turn();
  expect(net.sends.length, 2);
  gate.complete();
  expect((await a).ok, isTrue);
  expect((await b).ok, isTrue);
  await b4Clean(api);
}
