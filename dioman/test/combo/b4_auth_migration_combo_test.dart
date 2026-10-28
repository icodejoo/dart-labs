import 'package:dioman/pipeline.dart';
import 'package:test/test.dart';
import '../support/pipeline/b4_migration_scenarios.dart';

/// 鉴权与重试跨来源阶段的行为组合回归。
void main() {
  test(
      '[DiomanAuth.onRefresh × DiomanCache.option] 刷新后缓存只保存最终成功并供后续调用命中',
      () => b4RefreshAndRetry(
          auth: true, refresh: true, cache: true, assertCached: true));
  test('[DiomanAuth.onRefresh × DiomanCache.option] 清除凭据后缓存命中也必须通过鉴权',
      () => b4CacheRequiresCredentials());
  test('[DiomanAuth.onRefresh × DiomanShare.option] 传输失败后刷新期间首发取消不影响跟随者',
      () => b4CancellationSettles(chained: true));
  test('[DiomanAuth.onRefresh × DiomanShare.option] 业务失败后刷新期间首发取消不影响跟随者',
      () => b4CancellationSettles(chained: true, businessFailure: true));
  test('[DiomanAuth.onRefresh × DiomanShare.option] 刷新后传输失败仍重试并携带新凭据',
      () => b4RefreshAndRetry(auth: true, refresh: true, extraFailure: true));
  test('[DiomanAuth.onRefresh × DiomanShare.option] 就绪回调异常使所有共享调用保留原错误落定',
      () => b4CallbackBugSettles(throwIn: B4BugSite.ready));
  test('[DiomanAuth.onRefresh × DiomanShare.option] 到期回调异常使所有共享调用保留原错误落定',
      () => b4CallbackBugSettles(throwIn: B4BugSite.expiresAt));
  test('[DiomanAuth.onRefresh × DiomanShare.option] 保护判定异常使所有共享调用保留原错误落定',
      () => b4CallbackBugSettles(throwIn: B4BugSite.isProtected));
  test('[DiomanAuth.onRefresh × DiomanShare.option] 主动刷新时钟异常使所有共享调用保留原错误落定',
      () => b4CallbackBugSettles(throwIn: B4BugSite.clock));
  test('[DiomanAuth.onRefresh × DiomanShare.option] 并发鉴权失败只刷新一次并共享重放成功',
      () => b4RefreshAndRetry(auth: true, refresh: true));
  test(
      '[DiomanAuth.onRefresh × DiomanShare.option] 单调用刷新重放后共享活动表与逻辑状态归零',
      () =>
          b4RefreshAndRetry(auth: true, refresh: true, singleSubscriber: true));
  test(
      '[DiomanAuth.onRefresh × DiomanShare.option] 失败回调异常使竞速调用保留原错误落定',
      () => b4CallbackBugSettles(
          throwIn: B4BugSite.onFailure, policy: DiomanSharePolicy.race));
  test('[DiomanAuth.onRefresh × DiomanShare.option] 公开请求没有凭据仍可共享一次传输',
      () => b4PublicRequestsShare());
  test('[DiomanAuth.onRefresh × DiomanShare.option] 内联模拟在共享之前为每个逻辑调用执行',
      () => b4InlineRunsPerCaller());
  test('[DiomanAuth.onRefresh × DiomanShare.option] 内部重试与鉴权组合保持逻辑状态完整',
      () => b4RefreshAndRetry(auth: true, internalRetry: true));
  test(
      '[DiomanAuth.onRefresh × DiomanShare.option] 重装共享插件后刷新重放仍正确结算',
      () => b4RefreshAndRetry(
          auth: true,
          refresh: true,
          internalRetry: true,
          reinstallShare: true));
  test('[DiomanAuth.onRefresh × DiomanShare.option] 刷新期间全局取消使所有共享调用结束并清理',
      () => b4CancellationSettles(cancelAll: true));
  test('[DiomanAuth.onRefresh × DiomanShare.option] 最新成功覆盖旧鉴权失败且不提前刷新',
      () => b4LatestSuccessSkipsRefresh());
}
