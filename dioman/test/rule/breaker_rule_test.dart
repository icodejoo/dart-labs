import 'package:dioman/pipeline.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/pipeline/b3_helpers.dart';
import '../support/pipeline/fake_clock.dart';
import '../support/pipeline/fake_network.dart';
import '../support/pipeline/helpers.dart';

/// 熔断状态机与请求级配置规则。
void main() {
  test('[DiomanBreakerApi.keyOf] 默认键与请求覆盖只计算桶键，不建桶不改状态', () async {
    for (final custom in [false, true]) {
      final api = testClient(plugins: [
        DiomanBreaker(keyBuilder: custom ? (_) => b3ValueKey : null)
      ]);
      final m = api.plugin<DiomanBreakerApi>()!;
      for (final option in [
        null,
        false,
        true,
        const DiomanBreakerOptions(enabled: false),
        DiomanBreakerOptions(enabled: false, keyBuilder: (_) => b3ValueCustom)
      ]) {
        final r = DiomanRequest(
            RequestOptions(method: b3ValueGet, path: b3Path),
            call: DiomanCall(options: {DiomanBreaker.option: option}));
        expect(
            m.keyOf(r),
            option is DiomanBreakerOptions && option.keyBuilder != null
                ? b3ValueCustom
                : custom
                    ? b3ValueKey
                    : b3Route);
        expect(m.bucketCount, 0);
        expect(m.retryableAt(m.keyOf(r)), isNull);
      }
      api.dispose();
    }
  });
  test('[DiomanBreaker.defaultMaxBuckets] 默认回收一小时和一千桶软上限', () {
    expect(DiomanBreaker.defaultIdleTtl, const Duration(hours: 1));
    expect(DiomanBreaker.defaultMaxBuckets, 1000);
  });
  test('[DiomanBreakerApi] 连续失败、冷却、半开成功关闭与失败重开，HTTP business 一致', () async {
    for (final business in [false, true]) {
      for (final recover in [false, true]) {
        final clock = FakeClock();
        final net = FakeNetwork();
        var status = 500;
        final changes = <DiomanBreakerState>[];
        final api = testClient(clock: clock, network: net, plugins: [
          DiomanBreaker(
              failureThreshold: 2,
              resetDuration: b3Tick,
              onStateChange: (key, from, to) {
                expect(key, b3Route);
                changes.add(to);
              }),
          TestPlugin(b3ValueResult, stage: DiomanStage.source,
              handler: (ctx, next) async {
            net.routes[b3Route] = [
              FakeReply(status: business ? 200 : status, body: {
                b3ValueCode: business && status != 200 ? status : 0,
                b3ValueData: null
              })
            ];
            return next();
          })
        ]);
        final management = api.plugin<DiomanBreakerApi>()!;
        final request = DiomanRequest(
            (await api.send<Object?>(b3ValueGet, b3Path))
                .request
                .toRequestOptions());
        expect(management.stateOf('unknown'), DiomanBreakerState.closed);
        expect(management.isOpen(request), isFalse);
        await api.send<Object?>(b3ValueGet, b3Path);
        expect(management.stateOf(b3Route), DiomanBreakerState.open);
        expect(management.isOpen(request), isTrue);
        expect(
            (await api.send<Object?>(b3ValueGet, b3Path)).reason, b3ValueOpen);
        expect(net.sends.length, 2);
        clock.elapse(b3Tick);
        expect(management.isOpen(request), isFalse);
        status = recover ? 200 : 500;
        final r = await api.send<Object?>(b3ValueGet, b3Path);
        expect(r.ok, recover);
        expect(management.stateOf(b3Route),
            recover ? DiomanBreakerState.closed : DiomanBreakerState.open);
        expect(changes, [
          DiomanBreakerState.open,
          DiomanBreakerState.halfOpen,
          recover ? DiomanBreakerState.closed : DiomanBreakerState.open
        ]);
        management.reset();
        expect(management.bucketCount, 0);
        api.dispose();
        expect(management.bucketCount, 0);
      }
    }
  });
  test('[DiomanBreaker.shouldTrip] 默认类别与逻辑状态、自定义 true false null', () async {
    for (final custom in [null, true, false]) {
      for (final kind in [
        DiomanKind.network,
        DiomanKind.timeout,
        DiomanKind.parse,
        DiomanKind.http,
        DiomanKind.biz
      ]) {
        for (final status in [0, 200, 429, 500]) {
          final api = testClient(plugins: [
            DiomanBreaker(failureThreshold: 1, shouldTrip: (r) => custom),
            TestPlugin(b3ValueResult,
                stage: DiomanStage.source,
                handler: (ctx, next) async =>
                    ctx.fail(DiomanFailure(kind: kind, status: status)))
          ]);
          await api.send<Object?>(b3ValueGet, b3Path);
          final failed = custom ??
              ([DiomanKind.network, DiomanKind.timeout].contains(kind) ||
                  status >= 500 ||
                  status == 429);
          expect(api.plugin<DiomanBreakerApi>()!.stateOf(b3Route),
              failed ? DiomanBreakerState.open : DiomanBreakerState.closed);
          api.dispose();
        }
      }
    }
  });
  test('[DiomanBreaker.option] 四种写法、继承覆盖、非法类型、默认常量与安装关闭', () async {
    expect(const DiomanBreaker().idleTtl, DiomanBreaker.defaultIdleTtl);
    expect(const DiomanBreaker().maxBuckets, DiomanBreaker.defaultMaxBuckets);
    expect(const DiomanBreaker().failureThreshold, 10);
    expect(const DiomanBreaker().halfOpenMaxCalls, 3);
    expect(const DiomanBreaker().resetDuration, const Duration(seconds: 30));
    for (final option in <Object?>[
      null,
      true,
      false,
      const DiomanBreakerOptions(enabled: false),
      const DiomanBreakerOptions(
          failureThreshold: 1,
          resetDuration: Duration.zero,
          halfOpenMaxCalls: 0,
          keyBuilder: _key,
          shouldTrip: _trip),
      b3ValueBad
    ]) {
      final net = FakeNetwork()
        ..routes[b3Route] = [const FakeReply(status: 500)];
      final api = testClient(
          network: net, plugins: [const DiomanBreaker(failureThreshold: 1)]);
      final call = DiomanCall(options: {DiomanBreaker.option: option});
      final p = api.send<Object?>(b3ValueGet, b3Path, call: call);
      if (option == b3ValueBad) {
        await expectLater(p, throwsArgumentError);
      } else {
        final request = (await p).request;
        final m = api.plugin<DiomanBreakerApi>()!;
        if (option == false ||
            option is DiomanBreakerOptions && option.enabled == false) {
          expect(m.bucketCount, 0);
          expect(m.isOpen(request), isFalse);
        } else {
          expect(m.bucketCount, 1);
          await api.send<Object?>(b3ValueGet, b3Path, call: call);
          expect(net.sends.length, 1);
        }
      }
      api.dispose();
    }
    final api = testClient(plugins: [const DiomanBreaker(enabled: false)]);
    expect(api.inspect(), isEmpty);
    api.dispose();
  });
  test('[DiomanBreaker.onStateChange] 通知异常隔离，判定与 keyBuilder 异常原样落定', () async {
    final bug = StateError('breaker');
    for (final mode in [b3ValueNotice, b3ValueTrip, b3ValueKey]) {
      final logs = <String>[];
      final net = FakeNetwork()
        ..routes[b3Route] = [const FakeReply(status: 500)];
      final api = testClient(network: net, debug: logs.add, plugins: [
        DiomanBreaker(
            failureThreshold: 1,
            onStateChange: (k, f, t) => throw bug,
            shouldTrip: mode == b3ValueTrip ? (r) => throw bug : null,
            keyBuilder: mode == b3ValueKey ? (r) => throw bug : null)
      ]);
      final p = api.send<Object?>(b3ValueGet, b3Path);
      if (mode == b3ValueNotice) {
        expect((await p).status, 500);
        expect(logs.where((s) => s.contains('状态通知失败')), hasLength(1));
      } else {
        await expectLater(p, throwsA(same(bug)));
      }
      api.dispose();
    }
  });
}

/// 固定分桶覆盖。
String _key(DiomanRequest request) => b3ValueCustom;

/// 自定义计失败。
bool _trip(DiomanResponse<dynamic> result) => true;
