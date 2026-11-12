import 'package:test/test.dart';
import '../support/auth_mock_retry_share_scenarios.dart';


/// 验证对应主题的行为与边界。
void main() {
  test('[DiomanMock.routes × DiomanRetry.max] 模拟探测回落在每次外层重试重新执行',
      () => b4MockRetryRecovers(fallback: true));
  test('[DiomanMock.routes × DiomanRetry.max] 内联模拟传输失败由外层重试恢复成功',
      () => b4MockRetryRecovers());
  test('[DiomanMock.routes × DiomanRetry.max] 内联模拟业务失败由自定义重试判定恢复',
      () => b4MockRetryRecovers(inlineBusiness: true));
  test('[DiomanMock.routes × DiomanRetry.max] 共享下模拟探测回落仍逐次重试执行',
      () => b4MockRetryRecovers(fallback: true, withShare: true));
  test('[DiomanMock.routes × DiomanRetry.max] 共享下内联模拟传输失败仍由外层重试恢复',
      () => b4MockRetryRecovers(withShare: true));
  test('[DiomanMock.routes × DiomanRetry.max] 共享下内联模拟业务失败仍由自定义判定恢复',
      () => b4MockRetryRecovers(inlineBusiness: true, withShare: true));
}
