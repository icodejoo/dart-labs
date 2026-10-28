// ignore_for_file: avoid_relative_lib_imports
// 组合层：normalize_retry
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../accept/lib/literals.dart';
import '../support/fixtures.dart';

/// 注册本文件的组合层用例。
void main() {
  const timeout = Duration(seconds: 3);

  group('恢复成功后的结果要经过后续处理（#8）', () {
    test(
        '[DiomanNormalize.onResponse × DiomanRetry.onRequest] retry 错误阶段重试成功：结果被 normalize 解包',
        () async {
      final adapter = RecordingAdapter((o, n) async =>
          n == 1 ? jsonBody({}, 500) : jsonBody(successEnvelope(), 200));
      final dio = fakeDio(adapter);
      Dioman.install(dio,
          retry: testRetry(), normalize: const DiomanNormalize());

      final r = await dio.get<dynamic>(tkX).timeout(timeout);
      expect(r.data, {tkV: 1});
    });
    test(
        '[DiomanNormalize.onResponse × DiomanRetry.shouldRetry] retry 业务失败恢复：结果被 normalize 解包',
        () async {
      final adapter = RecordingAdapter((o, n) async => n == 1
          ? jsonBody(failureEnvelope(), 200)
          : jsonBody(successEnvelope(), 200));
      final dio = fakeDio(adapter);
      Dioman.install(dio,
          retry: testRetry(shouldRetry: retryBusinessFailure),
          normalize: const DiomanNormalize());

      final r = await dio.get<dynamic>(tkX).timeout(timeout);
      expect(r.data, {tkV: 1});
    });
  });
}
