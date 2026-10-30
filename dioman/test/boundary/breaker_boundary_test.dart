import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/b3_helpers.dart';
import '../support/fake_clock.dart';
import '../support/helpers.dart';

/// 熔断名额、窗口隔离与安全回收边界。
void main() {
  test('[DiomanBreakerApi.retryableAt] 保存开启时请求冷却，查询到期不迁移，半开重开关闭与 reset',
      () async {
    final clock = FakeClock();
    const cooldown = Duration(seconds: 7);
    var outcome = DiomanKind.network;
    final transitions = <DiomanBreakerState>[];
    final api = testClient(clock: clock, plugins: [
      DiomanBreaker(
          failureThreshold: 1,
          resetDuration: b3Tick,
          onStateChange: (_, from, to) => transitions.add(to)),
      TestPlugin(b3ValueResult,
          stage: DiomanStage.source,
          handler: (ctx, next) async => ctx.fail(DiomanFailure(kind: outcome)))
    ]);
    final m = api.plugin<DiomanBreakerApi>()!;
    final call = DiomanCall(options: {
      DiomanBreaker.option: const DiomanBreakerOptions(resetDuration: cooldown)
    });
    final opened = clock.now();
    final r = await api.send<Object?>(b3ValueGet, b3Path, call: call);
    final key = m.keyOf(r.request);
    final deadline = opened.add(cooldown);
    expect(m.retryableAt(key), deadline);
    // 同桶其他请求的配置不能覆盖开启快照。
    await api.send<Object?>(b3ValueGet, b3Path);
    expect(m.retryableAt(key), deadline);
    clock.elapse(cooldown);
    expect(m.retryableAt(key), deadline);
    expect(m.stateOf(key), DiomanBreakerState.open);
    expect(transitions, [DiomanBreakerState.open]);
    outcome = DiomanKind.cancel;
    await api.send<Object?>(b3ValueGet, b3Path, call: call);
    expect(m.stateOf(key), DiomanBreakerState.halfOpen);
    expect(m.retryableAt(key), isNull);
    outcome = DiomanKind.network;
    await api.send<Object?>(b3ValueGet, b3Path);
    expect(m.retryableAt(key), clock.now().add(b3Tick));
    clock.elapse(b3Tick);
    outcome = DiomanKind.ok;
    await api.send<Object?>(b3ValueGet, b3Path);
    expect(m.stateOf(key), DiomanBreakerState.closed);
    expect(m.retryableAt(key), isNull);
    outcome = DiomanKind.network;
    await api.send<Object?>(b3ValueGet, b3Path);
    m.reset();
    expect(m.retryableAt(key), isNull);
    expect(m.bucketCount, 0);
    api.dispose();
  });
  test(
      '[DiomanBreaker.resetDuration][DiomanBreakerState.halfOpen]'
      '[DiomanBreaker.shouldTrip] cancel 只归还名额，不清连续失败也不计失败，半开可继续探测', () async {
    final clock = FakeClock();
    var outcome = DiomanKind.network;
    var trips = 0;
    final api = testClient(clock: clock, plugins: [
      DiomanBreaker(
          failureThreshold: 2,
          resetDuration: b3Tick,
          halfOpenMaxCalls: 1,
          shouldTrip: (r) {
            trips++;
            return null;
          }),
      TestPlugin(b3ValueResult,
          stage: DiomanStage.source,
          handler: (ctx, next) async => ctx.fail(DiomanFailure(kind: outcome)))
    ]);
    final m = api.plugin<DiomanBreakerApi>()!;
    await api.send<Object?>(b3ValueGet, b3Path);
    outcome = DiomanKind.cancel;
    await api.send<Object?>(b3ValueGet, b3Path);
    expect(m.stateOf(b3Route), DiomanBreakerState.closed);
    expect(trips, 1);
    outcome = DiomanKind.network;
    await api.send<Object?>(b3ValueGet, b3Path);
    expect(m.stateOf(b3Route), DiomanBreakerState.open);
    clock.elapse(b3Tick);
    outcome = DiomanKind.cancel;
    await api.send<Object?>(b3ValueGet, b3Path);
    expect(m.stateOf(b3Route), DiomanBreakerState.halfOpen);
    outcome = DiomanKind.ok;
    await api.send<Object?>(b3ValueGet, b3Path);
    expect(m.stateOf(b3Route), DiomanBreakerState.closed);
    api.dispose();
  });
  test('[DiomanBreaker.halfOpenMaxCalls] 真实取消探测释放槽位，旧窗口结果不污染新窗口', () async {
    final clock = FakeClock();
    var mode = 'fail';
    final gates = <Completer<void>>[];
    final api = testClient(clock: clock, plugins: [
      const DiomanBreaker(
          failureThreshold: 1, resetDuration: b3Tick, halfOpenMaxCalls: 2),
      TestPlugin(b3ValueResult, stage: DiomanStage.source,
          handler: (ctx, next) async {
        if (mode == b3ValueGate) {
          final gate = Completer<void>();
          final index = gates.length;
          gates.add(gate);
          await ctx.wait(gate.future);
          return ctx.cancelled() ??
              ctx.fail(DiomanFailure(
                  kind: index == 2 ? DiomanKind.network : DiomanKind.http,
                  status: 200));
        }
        return ctx.fail(const DiomanFailure(kind: DiomanKind.network));
      })
    ]);
    final m = api.plugin<DiomanBreakerApi>()!;
    final request = (await api.send<Object?>(b3ValueGet, b3Path)).request;
    clock.elapse(b3Tick);
    mode = b3ValueGate;
    final token = CancelToken();
    final a = api.send<Object?>(b3ValueGet, b3Path,
        call: DiomanCall(cancelToken: token));
    final b = api.send<Object?>(b3ValueGet, b3Path);
    await b3Turn();
    expect(m.isOpen(request), isTrue);
    expect(
        (await api.send<Object?>(b3ValueGet, b3Path)).kind, DiomanKind.breaker);
    token.cancel();
    expect((await a).kind, DiomanKind.cancel);
    expect(m.isOpen(request), isFalse);
    final c = api.send<Object?>(b3ValueGet, b3Path);
    await b3Turn();
    gates[1].complete();
    await b;
    expect(m.stateOf(b3Route), DiomanBreakerState.closed);
    gates[2].complete();
    await c;
    expect(m.stateOf(b3Route), DiomanBreakerState.closed);
    gates[0].complete();
    api.dispose();
  });
  test(
      '[DiomanBreakerState.closed]'
      '[DiomanBreakerApi.reset] reset 之后旧请求不写新桶，internal 不计数且释放名额', () async {
    final gate = Completer<void>();
    var old = true;
    final bug = StateError(b3ValueInternal);
    final api = testClient(plugins: [
      const DiomanBreaker(failureThreshold: 1),
      TestPlugin(b3ValueResult, stage: DiomanStage.source,
          handler: (ctx, next) async {
        if (old) {
          await gate.future;
          return ctx.fail(const DiomanFailure(kind: DiomanKind.network));
        }
        throw bug;
      })
    ]);
    final p = api.send<Object?>(b3ValueGet, b3Path);
    await b3Turn();
    final m = api.plugin<DiomanBreakerApi>()!;
    m.reset();
    old = false;
    await expectLater(
        api.send<Object?>(b3ValueGet, b3Path), throwsA(same(bug)));
    gate.complete();
    await p;
    expect(m.stateOf(b3Route), DiomanBreakerState.closed);
    api.dispose();
  });
  test(
      '[DiomanBreaker.maxBuckets]'
      '[DiomanBreaker.idleTtl] TTL 与软上限只淘汰安全桶，保留失败和打开半开在途桶', () async {
    for (final ttl in [false, true]) {
      final clock = FakeClock();
      var failed = false;
      final api = testClient(clock: clock, plugins: [
        DiomanBreaker(
            maxBuckets: ttl ? 100 : 2,
            idleTtl: b3Tick,
            clock: clock.now,
            failureThreshold: 2),
        TestPlugin(b3ValueResult,
            stage: DiomanStage.source,
            handler: (ctx, next) async => ctx.fail(DiomanFailure(
                kind: failed ? DiomanKind.network : DiomanKind.http,
                status: 200)))
      ]);
      final m = api.plugin<DiomanBreakerApi>()!;
      await api.send<Object?>(b3ValueGet, '/safe1');
      clock.elapse(const Duration(milliseconds: 1));
      await api.send<Object?>(b3ValueGet, '/safe2');
      expect(m.bucketCount, 2);
      if (ttl) clock.elapse(const Duration(seconds: 2));
      await api.send<Object?>(b3ValueGet, '/safe3');
      expect(m.bucketCount, ttl ? 1 : 2);
      failed = true;
      await api.send<Object?>(b3ValueGet, '/failure1');
      await api.send<Object?>(b3ValueGet, '/failure2');
      await api.send<Object?>(b3ValueGet, '/failure3');
      expect(m.bucketCount, greaterThanOrEqualTo(3));
      clock.elapse(const Duration(days: 2));
      await api.send<Object?>(b3ValueGet, '/failure4');
      expect(m.bucketCount, 4);
      api.dispose();
    }
  });
}
