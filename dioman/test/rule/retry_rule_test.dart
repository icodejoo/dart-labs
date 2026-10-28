import 'package:dioman/pipeline.dart';
import 'package:test/test.dart';
import '../support/pipeline/b3_helpers.dart';
import '../support/pipeline/fake_clock.dart';
import '../support/pipeline/fake_network.dart';
import '../support/pipeline/helpers.dart';

/// 验证重试判定优先级和请求级合并。
void main() {
  test('[DiomanRetry.statusCodes] HTTP 与 business 逻辑状态全表和最后结果', () async {
    for (final business in [false, true]) {
      for (final status in [200, 408, 429, 500, 501, 502, 503, 504, 505]) {
        final net = FakeNetwork()
          ..routes[b3Route] = [
            FakeReply(status: business ? 200 : status, body: {
              b3ValueCode: business && status != 200 ? status : 0,
              b3ValueData: null
            })
          ];
        final clock = FakeClock();
        final api = testClient(
            network: net, clock: clock, plugins: [const DiomanRetry(max: 2)]);
        final r = await b3Finish(api.send<Object?>(b3ValueGet, b3Path), clock);
        expect(net.sends.length,
            DiomanRetry.defaultStatusCodes.contains(status) ? 3 : 1);
        expect(r.status, status);
        api.dispose();
      }
    }
  });
  test('[DiomanRetry.shouldRetry] 成功也交判定，自定义布尔优先与方法硬否决', () async {
    for (final method in [b3ValueGet, b3ValuePost]) {
      for (final decision in [true, false, null]) {
        var calls = 0;
        final net = FakeNetwork();
        final clock = FakeClock();
        final api = testClient(network: net, clock: clock, plugins: [
          DiomanRetry(
              max: 1,
              shouldRetry: (r, attempt) {
                calls++;
                expect(r.ok, isTrue);
                expect(attempt, 1);
                return decision;
              })
        ]);
        await b3Finish(api.send<Object?>(method, b3Path), clock);
        expect(calls, method == b3ValueGet ? 1 : 0);
        expect(
            net.sends.length, method == b3ValueGet && decision == true ? 2 : 1);
        api.dispose();
      }
    }
  });
  test('[DiomanRetry.shouldRetry] 类别硬否决先于回调，network timeout 默认重试', () async {
    for (final kind
        in DiomanKind.values.where((k) => k != DiomanKind.internal)) {
      var inner = 0;
      var decisions = 0;
      final clock = FakeClock();
      final api = testClient(clock: clock, plugins: [
        DiomanRetry(
            max: 1,
            shouldRetry: (r, a) {
              decisions++;
              return null;
            }),
        TestPlugin('source', stage: DiomanStage.source,
            handler: (ctx, next) async {
          inner++;
          return ctx.fail(DiomanFailure(kind: kind));
        })
      ]);
      await b3Finish(api.send<Object?>(b3ValueGet, b3Path), clock);
      final retry = [DiomanKind.network, DiomanKind.timeout].contains(kind);
      expect(inner, retry ? 2 : 1);
      expect(
          decisions,
          [
            DiomanKind.cancel,
            DiomanKind.auth,
            DiomanKind.parse,
            DiomanKind.breaker,
            DiomanKind.offline
          ].contains(kind)
              ? 0
              : 1);
      api.dispose();
    }
  });
  test('[DiomanRetry.option] 四种写法、整数简写、字段覆盖、非法类型和安装开关', () async {
    for (final option in [
      null,
      true,
      false,
      2,
      const DiomanRetryOptions(
          max: 2,
          methods: [b3ValuePost],
          statusCodes: [501],
          shouldRetry: null,
          delay: _zero,
          jitter: false,
          delayMax: b3Tick,
          respectRetryAfter: false,
          afterStatusCodes: [501],
          retryAfterMax: b3Tick,
          onRetry: _notice),
      const DiomanRetryOptions(enabled: false),
      b3ValueInvalid
    ]) {
      final net = FakeNetwork()
        ..routes['POST:$b3Path'] = [const FakeReply(status: 501)];
      final clock = FakeClock();
      final api = testClient(network: net, clock: clock, plugins: [
        const DiomanRetry(max: 1, methods: [b3ValuePost5], statusCodes: [501])
      ]);
      final pending = api.send<Object?>(b3ValuePost5, b3Path,
          call: DiomanCall(options: {DiomanRetry.option: option}));
      if (option == b3ValueInvalid) {
        await expectLater(pending, throwsArgumentError);
      } else {
        await b3Finish(pending, clock);
        expect(
            net.sends.length,
            option == false ||
                    option is DiomanRetryOptions && option.enabled == false
                ? 1
                : option == 2 || option is DiomanRetryOptions
                    ? 3
                    : 2);
      }
      api.dispose();
    }
    final api = testClient(plugins: [const DiomanRetry(enabled: false)]);
    expect(api.inspect(), isEmpty);
    api.dispose();
  });
  test('[DiomanContext.markReplayable] max 零与负数仍声明克隆且不重试', () async {
    for (final max in [0, -1]) {
      var entered = 0;
      final api = testClient(plugins: [
        DiomanRetry(max: max),
        TestPlugin('probe', handler: (ctx, next) async {
          entered++;
          expect(ctx.replayable, isTrue);
          return next();
        })
      ]);
      expect((await api.send<Object?>(b3ValueGet, b3Path)).ok, isTrue);
      expect(entered, 1);
      api.dispose();
    }
  });
}

/// 请求级零退避。
Duration _zero(int attempt, int max, DiomanResponse<dynamic> r) =>
    Duration.zero;

/// 请求级无操作通知。
void _notice(int attempt) {}
