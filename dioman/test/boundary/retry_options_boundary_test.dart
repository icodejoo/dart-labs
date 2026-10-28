import 'package:dioman/pipeline.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/pipeline/b3_helpers.dart';
import '../support/pipeline/fake_clock.dart';
import '../support/pipeline/helpers.dart';

/// 退避头名称。
const _retryHeader = 'retry-after';

/// 服务器退避秒数。
const _serverSeconds = '2';

/// 普通退避窗口。
const _normalDelay = Duration(seconds: 3);

/// 验证覆盖选项的实际等待时间，不只检验发送次数。
void main() {
  test(
      '[DiomanRetryOptions.delay] afterStatusCodes respectRetryAfter delay jitter 与双上限逐字段生效',
      () async {
    final cases = <(DiomanRetryOptions, Duration)>[
      (const DiomanRetryOptions(), _normalDelay),
      (
        const DiomanRetryOptions(afterStatusCodes: [500]),
        const Duration(seconds: 2)
      ),
      (
        const DiomanRetryOptions(
            afterStatusCodes: [500], respectRetryAfter: false),
        _normalDelay
      ),
      (
        const DiomanRetryOptions(
            afterStatusCodes: [500],
            retryAfterMax: b3Tick,
            delayMax: Duration.zero),
        b3Tick
      ),
      (
        DiomanRetryOptions(delay: (a, m, r) {
          expect((a, m), (1, 1));
          return b3Tick;
        }),
        b3Tick
      ),
      (const DiomanRetryOptions(delayMax: b3Tick), b3Tick),
      (
        DiomanRetryOptions(jitter: (Duration raw) {
          expect(raw, _normalDelay);
          return b3Tick;
        }),
        b3Tick
      ),
    ];
    for (final entry in cases) {
      final clock = FakeClock();
      var sends = 0;
      var notifications = 0;
      final api = testClient(clock: clock, plugins: [
        DiomanRetry(
            max: 1,
            statusCodes: [500],
            onRetry: (n) {
              expect(n, 1);
              notifications++;
            }),
        TestPlugin(b3ValueResult, stage: DiomanStage.source,
            handler: (ctx, next) async {
          sends++;
          return DiomanResponse<dynamic>(
              ok: false,
              kind: DiomanKind.biz,
              status: 500,
              httpStatus: 200,
              data: null,
              request: ctx.request,
              raw: Response<dynamic>(
                  requestOptions: ctx.request.toRequestOptions(),
                  headers: Headers.fromMap({
                    _retryHeader: [_serverSeconds]
                  })));
        })
      ]);
      final pending = api.send<Object?>(b3ValueGet, b3Path,
          call: DiomanCall(options: {DiomanRetry.option: entry.$1}));
      await b3Turn();
      expect(sends, 1);
      clock.elapse(entry.$2 - const Duration(milliseconds: 1));
      await b3Turn();
      expect(sends, 1);
      expect(notifications, 0);
      clock.elapse(const Duration(milliseconds: 1));
      await pending;
      expect(sends, 2);
      expect(notifications, 1);
      api.dispose();
    }
  });
  test('[DiomanRetryOptions.shouldRetry] 请求判定覆盖插件判定，状态表与方法按请求替换', () async {
    for (final permit in [false, true]) {
      final clock = FakeClock();
      var calls = 0;
      var sends = 0;
      final api = testClient(clock: clock, plugins: [
        DiomanRetry(
            max: 5,
            methods: [b3ValueGet],
            shouldRetry: (r, a) => fail(b3ValueShould)),
        TestPlugin(b3ValueResult, stage: DiomanStage.source,
            handler: (ctx, next) async {
          sends++;
          return ctx
              .fail(const DiomanFailure(kind: DiomanKind.http, status: 400));
        })
      ]);
      final result = await b3Finish(
          api.send<Object?>(b3ValuePost5, b3Path,
              call: DiomanCall(options: {
                DiomanRetry.option: DiomanRetryOptions(
                    max: 1,
                    methods: [b3ValuePost5],
                    statusCodes: [400],
                    shouldRetry: (r, a) {
                      calls++;
                      return permit;
                    })
              })),
          clock);
      expect(result.status, 400);
      expect(calls, 1);
      expect(sends, permit ? 2 : 1);
      api.dispose();
    }
  });
}
