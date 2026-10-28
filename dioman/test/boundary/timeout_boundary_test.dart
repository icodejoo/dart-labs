// ignore_for_file: avoid_relative_lib_imports
// 边界层：timeout
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../accept/lib/literals.dart';
import '../support/test_server.dart';

/// 注册本文件的边界层用例。
void main() {
  group(tkDiomanTimeout, () {
    test(
        '[DiomanTimeout.onRequest][DiomanTimeout.timeouts] a tier absent from the map is a no-op for that request',
        () async {
      final server = await TestServer.start((req) async {
        await respondJson(req, {tkOk: true}, 200);
      });
      addTearDown(server.close);

      final captured = <String, Duration?>{};
      final dio = Dio(BaseOptions(
        baseUrl: server.baseUrl,
        connectTimeout: const Duration(seconds: 4),
        receiveTimeout: const Duration(seconds: 5),
      ));
      dio.interceptors.add(DiomanTimeout(
        probe: () => NetworkQuality.good, // not in the map below
        timeouts: const {
          NetworkQuality.poor: DiomanTimeouts(connect: Duration(seconds: 7)),
        },
      ));
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        captured[tkConnect] = o.connectTimeout;
        captured[tkReceive] = o.receiveTimeout;
        h.next(o);
      }));

      await dio.get<dynamic>(tkX);
      expect(captured[tkConnect], const Duration(seconds: 4));
      expect(captured[tkReceive], const Duration(seconds: 5));
    });
  });
}
