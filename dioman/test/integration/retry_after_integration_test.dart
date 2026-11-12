import 'dart:io';
import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/auth_test_helpers.dart';
import '../support/fake_clock.dart';
import '../support/helpers.dart';

/// 回环测试响应的成功载荷。
const _response = '{"code":0,"data":"done"}';

/// 验证对应主题的行为与边界。
void main() {
  test('[DiomanRetry.respectRetryAfter] 真实 429 503 秒数与日期通过 DiomanClock 等待',
      () async {
    for (final date in [false, true]) {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var sends = 0;
      server.listen((request) async {
        await request.drain<void>();
        sends++;
        if (sends == 1) {
          request.response.statusCode = date ? 503 : 429;
          request.response.headers.set(HttpHeaders.retryAfterHeader,
              date ? b3ValueThu01Jan1970000002Gmt : '2');
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(_response);
        await request.response.close();
      });
      final clock = FakeClock();
      final api = Dioman<Result>(
          dio: Dio(BaseOptions(
              baseUrl: 'http://${server.address.address}:${server.port}')),
          clock: clock,
          plugins: [const DiomanRetry(max: 1)]);
      final pending = api.send<Object?>(b3ValueGet, b3Path);
      while (clock.pendingTimers == 0) {
        await b3Turn();
      }
      expect(sends, 1);
      clock.elapse(b3Tick);
      await b3Turn();
      expect(sends, 1);
      clock.elapse(b3Tick);
      expect((await pending).ok, isTrue);
      expect(sends, 2);
      api.dispose();
      await server.close(force: true);
    }
  });
}
