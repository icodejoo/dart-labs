// ignore_for_file: avoid_relative_lib_imports
// 规则层：normalize
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../accept/lib/literals.dart';
import '../support/test_server.dart';

/// 注册本文件的规则层用例。
void main() {
  group(tkDiomanNormalize, () {
    test(
        '[DiomanNormalize.shouldNormalize][DiomanNormalizeOptions.shouldNormalize] a custom shouldNormalize overrides the default envelope-detection '
        'heuristic', () async {
      final server = await TestServer.start((req) => respondJson(
          req,
          {
            tkCode: 0,
            tkData: {tkV: 1},
            tkMessage: tkEmpty
          },
          200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanNormalize(shouldNormalize: (o, r) => false));

      final r = await dio.get<Map<String, dynamic>>(tkData2);
      expect(
          r.data,
          {
            tkCode: 0,
            tkData: {tkV: 1},
            tkMessage: tkEmpty
          },
          reason: 'shouldNormalize forced false — envelope left untouched '
              'even though it looks like one');
    });
  });

  group('DiomanNormalize detection', () {
    test(
        '[DiomanException.code][DiomanException.message] a real error envelope (code + message) is still rejected as an '
        "DiomanException", () async {
      final server = await TestServer.start(
          (req) => respondJson(req, {tkCode: 1, tkMessage: tkBoom}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanNormalize());

      await expectLater(
        dio.get<void>(tkX),
        throwsA(isA<DioException>().having(
          (e) => e.error,
          tkError,
          isA<DiomanException>(),
        )),
      );
    });
    test(
        '[DiomanException.code][DiomanException.data] a real success envelope (code + data) is still unwrapped',
        () async {
      final server = await TestServer.start((req) => respondJson(
          req,
          {
            tkCode: 0,
            tkData: {tkX2: 1},
            tkMessage: tkOk
          },
          200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanNormalize());

      final res = await dio.get<Map<String, dynamic>>(tkX);
      expect(res.data, {tkX2: 1});
    });
  });

  group(tkNewlyWiredOptionsFieldsFullConstructorOptionsParity, () {
    test(
        '[DiomanNormalize.codeKey][DiomanNormalize.dataKey] DiomanNormalizeOptions.dataKey/codeKey/messageKey override the '
        "plugin's envelope keys for a single call", () async {
      final server = await TestServer.start((req) => respondJson(
          req,
          {
            tkStatus: 0,
            tkPayload: {tkOk: true},
            tkMsg: tkFine
          },
          200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors
          .add(const DiomanNormalize()); // default keys: code/data/message

      final res = await dio.get<Map<String, dynamic>>(
        tkX,
        options: Options(extra: {
          tkDiomanNormalize2: const DiomanNormalizeOptions(
            codeKey: tkStatus,
            dataKey: tkPayload,
            messageKey: tkMsg,
          ),
        }),
      );

      expect(res.data, {tkOk: true},
          reason: 'per-request envelope keys must be used instead of the '
              'plugin defaults, which would not recognise this envelope at all');
    });
  });
}
