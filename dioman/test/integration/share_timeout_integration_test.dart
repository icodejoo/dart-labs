import '../support/response_contract.dart';
import 'dart:io';
import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/helpers.dart';

const _get = 'GET';
const _path = '/decode';

/// 验证对应主题的行为与边界。
void main() {
  for (final policy in [DiomanSharePolicy.end, DiomanSharePolicy.race]) {
    test('[DiomanShare.policy] B8 真实阶段超时不会污染其他订阅者 $policy', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var hits = 0;
      server.listen((request) async {
        final hit = ++hits;
        await Future<void>.delayed(Duration(
            milliseconds: hit == 1
                ? (policy == DiomanSharePolicy.race ? 50 : 700)
                : 900));
        request.response.statusCode = 500;
        request.response.write('{}');
        await request.response.close();
      });
      final api = Dioman<Result>(
          dio: Dio(BaseOptions(
              baseUrl: 'http://${server.address.address}:${server.port}')),
          plugins: [DiomanShare<Result>(policy: policy)]);
      try {
        final first = api.send<dynamic>(_get, _path,
            call: DiomanCall(
                connectTimeout: const Duration(seconds: 2),
                receiveTimeout: const Duration(seconds: 2),
                options: {DiomanShare.option: true}));
        final latest = api.send<dynamic>(_get, _path,
            call: DiomanCall(
                connectTimeout: const Duration(milliseconds: 100),
                receiveTimeout: const Duration(milliseconds: 100),
                options: {DiomanShare.option: true}));
        expect(outcomeOf((await latest)), diomanTestTimeout);
        final r = await first;
        expect([outcomeOf(r), r.status], [diomanTestHttp, 500]);
        expect(api.pending, 0);
      } finally {
        api.dispose();
        api.dio.close(force: true);
        await server.close(force: true);
      }
    });
  }
}
