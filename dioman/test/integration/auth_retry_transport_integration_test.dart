import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/auth_test_helpers.dart';
import '../support/fake_clock.dart';
import '../support/helpers.dart';

/// 真实回环服务收到的标量载荷。
const _payload = 'transport payload';
/// 回环测试响应的成功载荷。
const _response = '{"code":0,"data":"done"}';
/// multipart 测试的字段名。
const _field = 'upload';

/// 验证对应主题的行为与边界。
void main() {
  test('[DiomanNext] JSON FormData Stream 重发复用宿主 adapter，不关闭宿主', () async {
    for (final auth in [false, true]) {
      for (final bodyKind in [b3ValueData, _field, b3ValueResult]) {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final bodies = <String>[];
        final headers = <String?>[];
        server.listen((request) async {
          bodies.add(await utf8.decoder.bind(request).join());
          headers.add(request.headers.value(HttpHeaders.authorizationHeader));
          request.response.statusCode = bodies.length == 1
              ? auth
                  ? 401
                  : 500
              : 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(_response);
          await request.response.close();
        });
        final clock = FakeClock();
        final logs = <String>[];
        final dio = Dio(BaseOptions(
            baseUrl: 'http://${server.address.address}:${server.port}'));
        final api =
            Dioman<Result>(dio: dio, clock: clock, debug: logs.add, plugins: [
          if (auth)
            b3Auth(TestTokens())
          else
            const DiomanRetry(max: 1, methods: [b3ValuePost5]),
        ]);
        Object data;
        if (bodyKind == _field) {
          data = FormData.fromMap(
              {_field: MultipartFile.fromString(_payload, filename: _field)});
        } else if (bodyKind == b3ValueResult) {
          data = Stream<List<int>>.multi((sink) {
            sink.add(utf8.encode(_payload));
            sink.close();
          });
        } else {
          data = {_field: _payload};
        }
        final pending = api.send<Object?>(b3ValuePost5, b3Path, data: data);
        if (!auth && bodyKind != b3ValueResult) {
          while (clock.pendingTimers == 0) {
            await b3Turn();
          }
          clock.elapse(const Duration(seconds: 3));
        }
        expect((await pending).ok, bodyKind != b3ValueResult);
        expect(bodies, hasLength(bodyKind == b3ValueResult ? 1 : 2));
        expect(bodies.every((s) => s.contains(_payload)), isTrue);
        if (auth) {
          expect(headers, [
            'Bearer $b3Old',
            if (bodyKind != b3ValueResult) 'Bearer $b3Fresh'
          ]);
        }
        expect(logs.any((s) => s.contains('无法克隆')), bodyKind == b3ValueResult);
        expect((await dio.get<dynamic>(b3Path)).statusCode, 200);
        api.dispose();
        await server.close(force: true);
      }
    }
  });
}
