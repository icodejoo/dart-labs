import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/auth_mock_retry_share_scenarios.dart';


/// 验证对应主题的行为与边界。
void main() {
  test('[DiomanRetry.max × DiomanShare.option] 业务失败外层重试后缓存只保存成功响应',
      () => b4RefreshAndRetry(cache: true, assertCached: true));
  test('[DiomanRetry.max × DiomanShare.option] 共享重试成功后再次调用命中缓存且不重复发送',
      () => b4RefreshAndRetry(cache: true, assertCached: true));
  test('[DiomanAuth.onRefresh × DiomanShare.option] 刷新前取消首发后跟随者仍完成刷新',
      () => b4CancellationSettles(cancelBeforeReply: true));
  test(
      '[DiomanRetry.max × DiomanShare.option] 失败响应前取消首发后跟随者仍外层重试成功',
      () => b4CancellationSettles(
          cancelBeforeReply: true, retryWithoutRefresh: true));
  test('[DiomanRetry.max × DiomanShare.option] 鉴权与缓存共享组合在外层重试后正确结算',
      () => b4RefreshAndRetry(auth: true, cache: true));
  test('[DiomanRetry.max × DiomanShare.option] 外层重试中最新成功覆盖较早成功并统一结果',
      () => b4RetryArbitration(policy: DiomanSharePolicy.end));
  test(
      '[DiomanSharePolicy.race]'
      '[DiomanRetry.max × DiomanShare.option] 外层重试中竞速等待在途成功且不被旧失败提前结算',
      () => b4RetryArbitration(policy: DiomanSharePolicy.race));
  test('[DiomanRetry.max × DiomanShare.option] 竞速重试通知异常被隔离且各调用均正确落定',
      () => b4RetryNoticesSettle(throwNotice: true));
  test(
      '[DiomanRetry.max × DiomanShare.option] 最新策略重试判定异常保留原错误并清理',
      () => b4CallbackBugSettles(
          throwIn: B4BugSite.shouldRetry, policy: DiomanSharePolicy.end));
  test(
      '[DiomanRetry.max × DiomanShare.option] 竞速策略重试判定异常保留原错误并清理',
      () => b4CallbackBugSettles(
          throwIn: B4BugSite.shouldRetry, policy: DiomanSharePolicy.race));
  test('[DiomanRetry.max × DiomanShare.option] 新调用加入外层重试当前尝试且不增加传输',
      () => b4CallerJoinsCurrentRetry());
  test('[DiomanRetry.max × DiomanShare.option] 内部重试策略的外层通知按逻辑调用触发',
      () => b4RetryNoticesSettle(throwNotice: false));
  test('[DiomanRetry.max × DiomanShare.option] 内部重试耗尽后外层重试仍重新进入共享表',
      () => b4RefreshAndRetry(internalRetry: true));
  test('[DiomanRetry.max × DiomanShare.option] 内部重试策略允许后到调用共享当前重放结果',
      () => b4CallerJoinsCurrentRetry());
  test('[DiomanRetry.max × DiomanShare.option] 首发共享重试判定异常保留原错误并清理',
      () => b4CallbackBugSettles(throwIn: B4BugSite.shouldRetry));
}
