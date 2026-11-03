import 'package:dioman/src/response.dart' show DiomanResponseInternal;
import '../support/response_contract.dart';
import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/auth_test_helpers.dart';
import '../support/fake_clock.dart';
import '../support/helpers.dart';

/// 验证退避、服务器时间与取消窗口。
void main() {
  test(
      '[DiomanRetry.respectRetryAfter]'
      '[DiomanRetry.respectRetryAfter] 秒数、空白、HTTP 日期、无效值和独立封顶', () async {
    for (final header in <String?>[
      null,
      b3ValueEmpty,
      b3Value,
      b3Value2,
      b3Value224,
      'NaN',
      'Infinity',
      b3ValueBad,
      b3ValueThu01Jan1970000002Gmt,
      'Thu, 01 Xxx 1970 00:00:02 GMT',
      b3ValueWed31Dec1969235959Gmt
    ]) {
      final clock = FakeClock();
      var inner = 0;
      var delays = 0;
      final api = testClient(clock: clock, plugins: [
        DiomanRetry(
            max: 1,
            delay: (a, m, r) {
              delays++;
              return b3Tick;
            },
            delayMax: Duration.zero,
            jitter: (_) => const Duration(seconds: 9),
            retryAfterMax: b3Tick),
        TestPlugin(b3ValueResult, stage: DiomanStage.source,
            handler: (ctx, next) async {
          inner++;
          final raw = Response<dynamic>(
              requestOptions: ctx.request.toRequestOptions(),
              statusCode: 200,
              headers: Headers.fromMap({
                if (header != null) 'retry-after': [header]
              }));
          final result = DiomanResponse<dynamic>(
              ok: false,
              status: 429,
              data: null,
              request: ctx.request,
              raw: null);
          DiomanResponseInternal.setRetryAfter(
              result, raw.headers.value('retry-after'));
          return result;
        })
      ]);
      final p = api.send<Object?>(b3ValueGet, b3Path);
      await b3Turn();
      final valid = header != null &&
          [
            b3ValueEmpty,
            b3Value,
            b3Value2,
            b3Value224,
            b3ValueThu01Jan1970000002Gmt,
            b3ValueWed31Dec1969235959Gmt
          ].contains(header);
      expect(delays, valid ? 0 : 1);
      clock.elapse(Duration.zero);
      await b3Turn();
      final positive =
          header == b3Value2 || header == b3ValueThu01Jan1970000002Gmt;
      expect(inner, positive ? 1 : 2);
      clock.elapse(b3Tick);
      await p;
      expect(inner, positive ? 1 : 2);
      expect(clock.pendingTimers, 0);
      api.dispose();
    }
  });
  test(
      '[DiomanRetry.delayMax][DiomanRetry.jitter]'
      '[DiomanRetry.delay] 抖动正负、随机、负退避与上限，关闭服务器头', () async {
    for (final jitter in <Object?>[
      null,
      false,
      true,
      (Duration d) => const Duration(seconds: 9),
      (Duration d) => const Duration(seconds: -1)
    ]) {
      for (final negative in [false, true]) {
        final clock = FakeClock();
        var inner = 0;
        final api = testClient(clock: clock, plugins: [
          DiomanRetry(
              max: 1,
              respectRetryAfter: false,
              delay: (a, m, r) =>
                  negative ? const Duration(seconds: -1) : b3Tick,
              jitter: jitter,
              delayMax: b3Tick),
          TestPlugin(b3ValueResult, stage: DiomanStage.source,
              handler: (ctx, next) async {
            inner++;
            return scriptedResult(ctx, diomanTestTimeout);
          })
        ]);
        await b3Finish(api.send<Object?>(b3ValueGet, b3Path), clock);
        expect(inner, 2);
        api.dispose();
      }
    }
  });
  test('[DiomanContext.wait] 退避取消含订阅前取消，禁止再次进入内层', () async {
    for (final before in [false, true]) {
      final token = CancelToken();
      final clock = FakeClock();
      var inner = 0;
      final api = testClient(clock: clock, plugins: [
        DiomanRetry(
            max: 2,
            delay: (a, m, r) {
              if (before) token.cancel();
              return b3Tick;
            }),
        TestPlugin(b3ValueResult, stage: DiomanStage.source,
            handler: (ctx, next) async {
          inner++;
          return scriptedResult(ctx, diomanTestNetwork);
        })
      ]);
      final p = api.send<Object?>(b3ValueGet, b3Path,
          call: DiomanCall(cancelToken: token));
      await b3Turn();
      if (!before) token.cancel();
      expect(outcomeOf((await p)), diomanTestCancel);
      expect(inner, 1);
      expect(clock.pendingTimers, 0);
      api.dispose();
    }
  });
  test(
      '[Dioman.clock][Dioman.new(debug)][Dioman.new(plugins)]'
      '[DiomanRetry.onRetry] 通知抛错隔离并记日志，通知取消不重发', () async {
    for (final cancel in [false, true]) {
      final token = CancelToken();
      final clock = FakeClock();
      final logs = <String>[];
      var inner = 0;
      late Dioman<Result> api;
      api = testClient(clock: clock, debug: logs.add, plugins: [
        DiomanRetry(
            max: 1,
            onRetry: (a) {
              expect(a, 1);
              if (cancel) {
                api.cancelAll();
              } else {
                throw StateError(b3ValueNotice);
              }
            }),
        TestPlugin(b3ValueResult, stage: DiomanStage.source,
            handler: (ctx, next) async {
          inner++;
          return scriptedResult(ctx, diomanTestNetwork);
        })
      ]);
      final r = await b3Finish(
          api.send<Object?>(b3ValueGet, b3Path,
              call: DiomanCall(cancelToken: token)),
          clock);
      expect(inner, cancel ? 1 : 2);
      expect(outcomeOf(r), cancel ? diomanTestCancel : diomanTestNetwork);
      if (!cancel) {
        expect(logs.where((s) => s.contains('重试通知失败')), hasLength(1));
      }
      api.dispose();
    }
  });
  test(
      '[DiomanRetry.defaultDelay]'
      '[DiomanRetry.shouldRetry] shouldRetry delay jitter 程序错误原样落定，internal 不重试',
      () async {
    final bug = StateError('decision');
    for (final mode in [
      b3ValueShould,
      b3ValueDelay,
      b3ValueJitter,
      b3ValueInternal
    ]) {
      final api = testClient(plugins: [
        DiomanRetry(
            max: 2,
            shouldRetry: mode == b3ValueShould ? (r, a) => throw bug : null,
            delay: mode == b3ValueDelay
                ? (a, m, r) => throw bug
                : DiomanRetry.defaultDelay,
            jitter: mode == b3ValueJitter ? (Duration d) => throw bug : null),
        TestPlugin(b3ValueResult, stage: DiomanStage.source,
            handler: (ctx, next) async {
          if (mode == b3ValueInternal) throw bug;
          return scriptedResult(ctx, diomanTestTimeout);
        })
      ]);
      await expectLater(
          api.send<Object?>(b3ValueGet, b3Path), throwsA(same(bug)));
      expect(api.pending, 0);
      api.dispose();
    }
  });
  test(
      '[DiomanCall.cancelToken][DiomanFailureKind.cancel][DiomanFailureKind.network][DiomanStage.source]'
      '[DiomanContext.cancelled] next 返回后取消优先，internal 保留原错', () async {
    final token = CancelToken();
    var inner = 0;
    final api = testClient(plugins: [
      const DiomanRetry(max: 2),
      TestPlugin(b3ValueResult, stage: DiomanStage.source,
          handler: (ctx, next) async {
        inner++;
        token.cancel();
        return scriptedResult(ctx, diomanTestNetwork);
      })
    ]);
    expect(
        outcomeOf((await api.send<Object?>(b3ValueGet, b3Path,
            call: DiomanCall(cancelToken: token)))),
        diomanTestCancel);
    expect(inner, 1);
    api.dispose();
  });
}
