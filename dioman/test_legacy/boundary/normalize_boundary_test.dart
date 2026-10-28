// ignore_for_file: avoid_relative_lib_imports
// 边界层：normalize
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../test/accept/lib/literals.dart';
import '../../test/support/test_server.dart';

/// 注册本文件的边界层用例。
void main() {
  group('DiomanNormalize detection', () {
    test(
        '[DiomanException.code][DiomanException.data] a plain payload that merely carries a `code` field (no data/message) '
        'is NOT mistaken for an envelope and rejected', () async {
      final server = await TestServer.start(
          (req) => respondJson(req, {tkCode: 86, tkName: tkCN}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanNormalize());

      final res = await dio.get<Map<String, dynamic>>('/country');
      expect(res.data, {tkCode: 86, tkName: tkCN},
          reason: 'code-only map must pass through untouched, not be unwrapped '
              'or rejected as an DiomanException');
    });
  });
}
