import 'package:dioman/src/response.dart' show DiomanResponseInternal;
import '../support/response_contract.dart';
import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/auth_test_helpers.dart';
import '../support/fake_clock.dart';
import '../support/helpers.dart';

const _result = 'result';
const _maxHeader = '60';
const _path = '/b8';
const _get = 'GET';

/// 验证对应主题的行为与边界。
void main() {
  for (final header in ['61', 'Thu, 01 Jan 1970 00:01:01 GMT', _maxHeader]) {
    test('[DiomanRetry.retryAfterMax] B8 服务端等待超限不重试 $header', () async {
      final clock = FakeClock();
      var sends = 0;
      final api = testClient(statusOf: businessStatus, clock: clock, plugins: [
        DiomanRetry<Result>(
            max: 1,
            jitter: (_) => throw StateError('jitter'),
            delayMax: Duration.zero),
        TestPlugin(_result, stage: DiomanStage.source,
            handler: (ctx, next) async {
          sends++;
          final result = ctx.factory.normalize(ctx.request,
              raw: Response<dynamic>(
                  requestOptions: ctx.request.toRequestOptions(),
                  statusCode: 503,
                  headers: Headers.fromMap({
                    'retry-after': [header]
                  })));
          DiomanResponseInternal.setRetryAfter(result, header);
          return result;
        })
      ]);
      final pending = api.send<dynamic>(_get, _path);
      await b3Turn();
      expect(sends, 1);
      clock.elapse(const Duration(seconds: 60));
      expect((await pending).status, 503);
      expect(sends, header == _maxHeader ? 2 : 1);
      expect(clock.pendingTimers, 0);
      api.dispose();
    });
  }
}
