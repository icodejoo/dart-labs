import '../model/ad.dart';

/// Why an ad break failed to play.
///
/// 一个广告位播放失败的原因。
enum MovaAdFailKind {
  /// `open()` on the ad source threw.
  ///
  /// 对广告源的 `open()` 抛出了异常。
  openThrew,

  /// The player reported a [MovaErrorEvent] while the ad was loading or
  /// playing.
  ///
  /// 广告加载或播放期间播放器报告了 [MovaErrorEvent]。
  playerError,

  /// The ad was opened but never produced a first frame within
  /// [MovaAdConfig.loadTimeout].
  ///
  /// 广告已打开，但在 [MovaAdConfig.loadTimeout] 内始终没有产出首帧。
  loadTimeout,

  /// Warming the ad up in a shadow engine timed out or was given up on, and
  /// [MovaAdConfig.notReadyAction] chose to drop the break.
  ///
  /// 在影子引擎里预热广告超时或被放弃，且 [MovaAdConfig.notReadyAction]
  /// 选择了丢弃该广告位。
  warmFailed,
}

/// One ad failure, fed to a [MovaAdFailPolicy].
///
/// A plain value object so the recovery rule is unit-testable with no player,
/// no engine and no Flutter binding.
///
/// 一次广告失败，喂给 [MovaAdFailPolicy]。
///
/// 纯值对象，使兜底规则无需播放器、引擎或 Flutter 绑定即可被测试。
class MovaAdFail {
  /// The break that failed.
  ///
  /// 失败的广告位。
  final MovaAdBreak adBreak;

  /// What went wrong.
  ///
  /// 出了什么问题。
  final MovaAdFailKind kind;

  /// How many times this break has already been attempted, starting at 1 for
  /// the first failure.
  ///
  /// 该广告位已经尝试过的次数，首次失败时为 1。
  final int attempt;

  /// The underlying error object, when there was one.
  ///
  /// 底层错误对象（若有）。
  final Object? error;

  /// Creates a failure record.
  ///
  /// 创建一条失败记录。
  ///
  /// - [adBreak]: the break that failed / 失败的广告位
  /// - [kind]: failure category / 失败类别
  /// - [attempt]: 1-based attempt counter / 从 1 起算的尝试次数
  /// - [error]: underlying error / 底层错误
  const MovaAdFail({
    required this.adBreak,
    required this.kind,
    required this.attempt,
    this.error,
  });
}

/// What the controller should do about a failed ad break.
///
/// 控制器该拿一条失败的广告位怎么办。
enum MovaAdFailAction {
  /// Re-open the same break and try again.
  ///
  /// 重新打开同一条广告位再试一次。
  retry,

  /// Give up on this break, mark it played, and carry on with the pod (or the
  /// content if it was the last one).
  ///
  /// 放弃这一条，标记为已播，继续 pod 的下一条（若已是最后一条则回正片）。
  skipBreak,

  /// Give up on the whole pod: mark every remaining break of the same kind as
  /// played and go straight to the content.
  ///
  /// 放弃整个 pod：把同类型的所有剩余广告位都标记为已播，直接进正片。
  abandonPod,
}

/// Decides how to recover from an ad that would not play.
///
/// The counterpart of [MovaWarmPolicy] on the failure side: a pure, injectable
/// rule so hosts with a real ad stack (fill-rate targets, make-good
/// obligations, per-campaign retry budgets) can replace it wholesale instead
/// of living with mova's opinion.
///
/// 判定一条播不出来的广告该如何兜底。
///
/// 失败侧与 [MovaWarmPolicy] 对应的那一半：纯粹、可注入的规则，使有真实广告
/// 体系的宿主（填充率指标、补播义务、每个 campaign 各自的重试预算）能整体
/// 替换掉它，而不必忍受 mova 的一家之言。
abstract class MovaAdFailPolicy {
  /// Returns the action to take for [failure].
  ///
  /// 返回针对 [failure] 应采取的动作。
  ///
  /// - [failure]: the failure being recovered from / 待兜底的失败
  ///
  /// Returns the recovery action / 返回兜底动作。
  MovaAdFailAction onFailure(MovaAdFail failure);
}

/// Retries up to [maxRetries] times, then skips the break and carries on.
///
/// The default, with [maxRetries] zero. Retrying a broken ad URL costs the
/// viewer a second stall for something they did not ask to watch, so the
/// out-of-the-box answer is "the viewer's time wins": drop that one creative,
/// keep the rest of the pod. Hosts who own make-good obligations raise
/// [maxRetries] deliberately.
///
/// 最多重试 [maxRetries] 次，之后跳过该广告位继续。
///
/// 默认策略，[maxRetries] 为 0。对一个坏掉的广告地址重试，代价是让观众为一个
/// 他本来就没想看的东西再卡一次，因此开箱默认是"观众的时间优先"：丢掉这一条
/// 素材，保留 pod 的其余部分。有补播义务的宿主可以自行调高 [maxRetries]。
class MovaAdRetrySkip implements MovaAdFailPolicy {
  /// How many retries one break is worth before it is dropped.
  ///
  /// 一条广告位在被丢弃前值得重试几次。
  final int maxRetries;

  /// Creates a retry-then-skip policy.
  ///
  /// 创建一个"先重试、再跳过"的策略。
  ///
  /// - [maxRetries]: retry budget per break, default 0 / 每条广告位的重试预算，默认 0
  ///
  /// Example / 示例:
  /// ```dart
  /// const MovaAdConfig(failPolicy: MovaAdRetrySkip(maxRetries: 2));
  /// ```
  const MovaAdRetrySkip({this.maxRetries = 0});

  @override
  MovaAdFailAction onFailure(MovaAdFail failure) =>
      failure.attempt <= maxRetries ? MovaAdFailAction.retry : MovaAdFailAction.skipBreak;
}

/// Abandons the entire pod on the first failure and goes straight to content.
///
/// For hosts who treat a broken creative as a signal that the whole ad
/// response is suspect — one failure and the viewer gets their content back,
/// rather than being walked through the rest of a pod that may be equally
/// broken.
///
/// 首次失败即放弃整个 pod，直接进正片。
///
/// 适合把"一条素材坏了"视为"整份广告响应都可疑"的宿主——失败一次就把画面还给
/// 观众，而不是带着他把 pod 里可能同样坏掉的其余几条挨个走一遍。
class MovaAdAbandonPod implements MovaAdFailPolicy {
  /// Creates an abandon-the-pod policy.
  ///
  /// 创建一个"放弃整个 pod"的策略。
  ///
  /// Example / 示例:
  /// ```dart
  /// const MovaAdConfig(failPolicy: MovaAdAbandonPod());
  /// ```
  const MovaAdAbandonPod();

  @override
  MovaAdFailAction onFailure(MovaAdFail failure) => MovaAdFailAction.abandonPod;
}
