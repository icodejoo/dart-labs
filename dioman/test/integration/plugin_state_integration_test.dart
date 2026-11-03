import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/auth_test_helpers.dart';
import '../support/helpers.dart';


/// 验证对应主题的行为与边界。
void main() {
  test(
      '[DiomanAuth.enabled][DiomanAuth.stage][DiomanBreaker.enabled][DiomanBreaker.name][DiomanBreaker.pluginName][DiomanBreaker.stage][DiomanBreakerApi.isOpen][DiomanRetry.enabled][DiomanRetry.name][DiomanRetry.pluginName][DiomanRetry.stage]'
      '[DiomanBreaker.setup]'
      '[DiomanRetry.setup]'
      '[DiomanPlugin.stage] B3 固定阶段、名称和每客户端独立状态', () async {
    final retry = const DiomanRetry();
    final breaker = const DiomanBreaker();
    final auth = b3Auth(TestTokens());
    expect(retry.stage, DiomanStage.attempt);
    expect(breaker.stage, DiomanStage.attempt);
    expect(auth.stage, DiomanStage.credential);
    expect([retry.name, breaker.name, auth.name],
        ['dioman:retry', 'dioman:breaker', 'dioman:auth']);
    final a = testClient(plugins: [breaker]);
    final b = testClient(plugins: [breaker]);
    final m = a.plugin<DiomanBreakerApi>()!;
    final request = DiomanRequest(RequestOptions(path: b3Path));
    expect(m.isOpen(request), isFalse);
    expect(identical(m, b.plugin<DiomanBreakerApi>()), isFalse);
    a.dispose();
    b.dispose();
  });
}
