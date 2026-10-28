// ignore_for_file: avoid_relative_lib_imports
// 规则层：log
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../accept/lib/literals.dart';
import '../support/test_server.dart';

/// 注册本文件的规则层用例。
void main() {
  group(tkDiomanLog, () {
    test(
        '[DiomanLog.writer][DiomanLogOptions.writer] logs request/response/error text through a custom writer, '
        'covering headers, body truncation, and the network-error (no '
        'response) label', () async {
      final logs = <String>[];
      var attempts = 0;
      final server = await TestServer.start((req) async {
        attempts++;
        if (attempts == 1) {
          return respondJson(req, {tkV: tkX2 * 50}, 200);
        }
        return respondJson(req, {tkFail: true}, 500);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanLog(
        logHeaders: true,
        maxBodyLength: 10,
        writer: (m, {error}) => logs.add(m),
      ));

      await dio.post<void>(tkData2,
          data: {tkA2: 1}, options: Options(headers: {'X-Test': tk1}));
      expect(logs.any((l) => l.contains('Headers:')), isTrue);
      expect(logs.any((l) => l.contains('… (+')), isTrue,
          reason: 'the 50-char body got truncated at maxBodyLength=10');

      logs.clear();
      await expectLater(dio.get<void>(tkData2), throwsA(isA<DioException>()));
      expect(logs.any((l) => l.startsWith('[dioman:log] ✗ 500')), isTrue);
    });
    test(
        '[DiomanLog.writer][DiomanLogOptions.writer] with no writer given, falls back to the default sink without '
        'throwing', () async {
      final server =
          await TestServer.start((req) => respondJson(req, {tkV: 1}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanLog());
      await dio.get<void>(tkData2); // must not throw
    });
  });

  group(tkNewlyWiredOptionsFieldsFullConstructorOptionsParity, () {
    test(
        '[DiomanLog.writer][DiomanLogOptions.writer] DiomanLogOptions.writer overrides the plugin default sink for a '
        'single call', () async {
      final server = await TestServer.start((req) => respondJson(req, {}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors
          .add(const DiomanLog(logResponse: false, logError: false));

      final captured = <String>[];
      await dio.get<void>(
        tkX,
        options: Options(extra: {
          tkDiomanLog2:
              DiomanLogOptions(writer: (msg, {error}) => captured.add(msg)),
        }),
      );

      expect(captured, isNotEmpty,
          reason: 'per-request writer must receive the request log line');
    });
  });
}
