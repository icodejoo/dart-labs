import '../support/response_contract.dart';
import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/auth_test_helpers.dart';
import '../support/fake_clock.dart';
import '../support/fake_network.dart';
import '../support/helpers.dart';


/// 验证对应主题的行为与边界。
void main() {
  test(
      '[DiomanBreaker.idleTtl] open halfOpen 与 closed 在途桶不回收，安全桶回收后同键从 closed 开始',
      () async {
    final clock = FakeClock();
    final gates = <Completer<void>>[];
    var hold = false;
    var failed = false;
    final api = testClient(clock: clock, plugins: [
      const DiomanBreaker(
          failureThreshold: 1,
          resetDuration: b3Tick,
          idleTtl: Duration.zero,
          maxBuckets: 1),
      TestPlugin(b3ValueResult, stage: DiomanStage.source,
          handler: (ctx, next) async {
        if (hold) {
          final gate = Completer<void>();
          gates.add(gate);
          await gate.future;
        }
        return scriptedResult(ctx, failed ? diomanTestNetwork : diomanTestHttp,
            status: 200);
      })
    ]);
    final m = api.plugin<DiomanBreakerApi>()!;
    await api.send<Object?>(b3ValueGet, b3Path);
    clock.elapse(b3Tick);
    await api.send<Object?>(b3ValueGet, b3ValueCustom);
    expect(m.bucketCount, 1);
    expect(m.stateOf(b3Route), DiomanBreakerState.closed);
    hold = true;
    final pending = api.send<Object?>(b3ValueGet, b3Path);
    await b3Turn();
    hold = false;
    failed = true;
    await api.send<Object?>(b3ValueGet, b3ValueCustom);
    expect(m.bucketCount, 2);
    expect(m.stateOf('GET:custom'), DiomanBreakerState.open);
    clock.elapse(b3Tick);
    hold = true;
    final probe = api.send<Object?>(b3ValueGet, b3ValueCustom);
    await b3Turn();
    hold = false;
    await api.send<Object?>(b3ValueGet, b3ValueResult);
    expect(m.bucketCount, 3);
    expect(m.stateOf('GET:custom'), DiomanBreakerState.halfOpen);
    failed = false;
    gates[0].complete();
    gates[1].complete();
    await Future.wait([pending, probe]);
    api.dispose();
  });
  test('[DiomanBreaker.shouldTrip] Dio 连接与三种超时只计一次，成功清连续失败且非正数不钳制', () async {
    for (final type in [
      DioExceptionType.connectionError,
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout
    ]) {
      final net = FakeNetwork()
        ..failOn[1] = DioException(
            requestOptions: RequestOptions(path: b3Path), type: type);
      final api = testClient(
          network: net, plugins: [const DiomanBreaker(failureThreshold: 2)]);
      await api.send<Object?>(b3ValueGet, b3Path);
      expect(api.plugin<DiomanBreakerApi>()!.stateOf(b3Route),
          DiomanBreakerState.closed);
      await api.send<Object?>(b3ValueGet, b3Path);
      net.failOn[3] = net.failOn[1]!;
      await api.send<Object?>(b3ValueGet, b3Path);
      expect(api.plugin<DiomanBreakerApi>()!.stateOf(b3Route),
          DiomanBreakerState.closed);
      api.dispose();
    }
    for (final value in [0, -1]) {
      final clock = FakeClock();
      final api = testClient(clock: clock, plugins: [
        DiomanBreaker(
            failureThreshold: value,
            halfOpenMaxCalls: value,
            resetDuration: Duration(seconds: value)),
        TestPlugin(b3ValueResult,
            stage: DiomanStage.source,
            handler: (ctx, next) async =>
                scriptedResult(ctx, diomanTestNetwork))
      ]);
      await api.send<Object?>(b3ValueGet, b3Path);
      expect(outcomeOf((await api.send<Object?>(b3ValueGet, b3Path))),
          diomanTestBreaker);
      expect(api.plugin<DiomanBreakerApi>()!.stateOf(b3Route),
          DiomanBreakerState.halfOpen);
      api.dispose();
    }
  });
}
