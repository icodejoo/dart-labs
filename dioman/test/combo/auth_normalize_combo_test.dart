// ignore_for_file: avoid_relative_lib_imports
// 组合层：auth_normalize
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../accept/lib/literals.dart';
import '../support/fixtures.dart';

/// 注册本文件的组合层用例。
void main() {
  const timeout = Duration(seconds: 3);

  group('恢复成功后的结果要经过后续处理（#8）', () {
    test(
        '[DiomanAuth.onRequest × DiomanNormalize.onResponse] auth 刷新重放成功：结果被 normalize 解包',
        () async {
      final adapter = RecordingAdapter((o, n) async =>
          n == 1 ? jsonBody({}, 401) : jsonBody(successEnvelope(), 200));
      final dio = fakeDio(adapter);
      final tm = TestTokens(tkT0);
      Dioman.install(dio,
          auth: testAuth(tm), normalize: const DiomanNormalize());

      final r = await dio.get<dynamic>(tkX).timeout(timeout);
      expect(r.data, {tkV: 1});
      expect(tm.accessToken, tkT1);
    });
    test(
        '[DiomanAuth.onRequest × DiomanNormalize.onResponse] auth 重放成功但落到业务失败：normalize 照常把它转成错误',
        () async {
      final adapter = RecordingAdapter((o, n) async =>
          n == 1 ? jsonBody({}, 401) : jsonBody(failureEnvelope(), 200));
      final dio = fakeDio(adapter);
      Dioman.install(dio,
          auth: testAuth(TestTokens(tkT0)), normalize: const DiomanNormalize());

      await expectLater(
        dio.get<dynamic>(tkX).timeout(timeout),
        throwsA(isA<DioException>()
            .having((e) => e.error, tkError, isA<DiomanException>())),
      );
    });
  });
}
