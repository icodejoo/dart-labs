// ignore_for_file: avoid_relative_lib_imports
// 组合层：mock_normalize
import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../accept/lib/literals.dart';
import '../support/test_server.dart';

/// 注册本文件的组合层用例。
void main() {
  group(tkDiomanMock, () {
    test(
        '[DiomanMock.enabled × DiomanNormalize.onResponse] a mock hit still runs onResponse of normalize and share, so the '
        'envelope is unwrapped and a concurrent follower does not hang',
        () async {
      final server = await TestServer.start(
          (req) => respondJson(req, {'should': 'not be called'}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final mock = DiomanMock(enabled: true)
        ..add(
            'GET:/mocked',
            (o) async => ResponseBody.fromString(
                  jsonEncode({
                    tkCode: 0,
                    tkData: {tkX2: 1},
                    tkMessage: tkOk
                  }),
                  200,
                  headers: {
                    Headers.contentTypeHeader: [tkApplicationJson],
                  },
                ));
      dio.interceptors.addAll([
        const DiomanKey(),
        const DiomanNormalize(),
        DiomanShare(),
        mock,
      ]);

      final leader = dio.get<Map<String, dynamic>>(tkMocked);
      final follower = dio.get<Map<String, dynamic>>(tkMocked);

      final results = await Future.wait([leader, follower])
          .timeout(const Duration(seconds: 5));

      expect(results[0].data, {tkX2: 1},
          reason:
              'normalize must unwrap the mocked envelope, same as a real response');
      expect(results[1].data, {tkX2: 1},
          reason:
              'the follower must not hang — share must settle on a mock hit');
    });
  });
}
