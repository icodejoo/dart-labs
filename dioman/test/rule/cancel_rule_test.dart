// ignore_for_file: avoid_relative_lib_imports
// 规则层：cancel
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../accept/lib/literals.dart';
import '../support/fixtures.dart';

/// 注册本文件的规则层用例。
void main() {
  const timeout = Duration(seconds: 3);

  group(tkCancelAll10, () {
    test('[DiomanCancel.cancelAll] 逻辑请求正常结束后 token 注销，cancelAll 为 0', () async {
      final adapter = RecordingAdapter((o, n) async => n == 1
          ? jsonBody({}, 401)
          : (n == 2 ? jsonBody({}, 500) : jsonBody(successEnvelope(), 200)));
      final dio = fakeDio(adapter);
      Dioman.install(dio,
          cancel: DiomanCancel(),
          auth: testAuth(TestTokens(tkT0)),
          retry: testRetry());

      await dio.get<dynamic>(tkX).timeout(timeout);
      expect(cancelAll(dio), 0);
    });
  });
}
