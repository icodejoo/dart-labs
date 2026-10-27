/// What the caller knows about the upcoming switch point.
///
/// 调用方对即将到来的切换点的已知信息。
class MovaWarmCue {
  /// Time left until the switch point, or null when it is not predictable
  /// (e.g. a user-initiated quality change happens "now").
  ///
  /// 距切换点剩余的时长；不可预测时为 null（例如用户发起的清晰度切换就是
  /// "现在"）。
  final Duration? remaining;

  /// Total length of the clip being played out, or null when unknown.
  ///
  /// 正在播出的片段总时长；未知时为 null。
  final Duration? total;

  /// Creates a cue.
  ///
  /// 创建一条切换线索。
  ///
  /// - [remaining]: time left until the switch / 距切换点剩余时长
  /// - [total]: total clip length / 片段总时长
  const MovaWarmCue({this.remaining, this.total});
}

/// Decides whether warming should start now for a given [MovaWarmCue].
///
/// 依据给定的 [MovaWarmCue] 判定此刻是否应开始预热。
abstract class MovaWarmTrigger {
  /// Returns whether to start warming now.
  ///
  /// 返回此刻是否应开始预热。
  ///
  /// - [cue]: what is known about the switch point / 关于切换点的已知信息
  ///
  /// Returns whether to warm now / 返回是否立即预热。
  bool shouldWarm(MovaWarmCue cue);
}

/// Warms up [lead] before a predictable switch point, and never at all for
/// clips shorter than [minDuration].
///
/// The ad case: an ad's length is known, so the two engines only overlap for
/// the last second or two instead of the whole break — same peak cost, far
/// smaller time-integral of that cost, and a far smaller chance of actually
/// hitting the SoC's concurrent hardware-decode session limit.
///
/// 在可预测的切换点前 [lead] 开始预热；片长短于 [minDuration] 则完全不预热。
///
/// 广告场景：广告时长基本已知，因此两个引擎只在最后一两秒重叠，而非整个广告
/// 全程——峰值开销不变，但开销的时间积分小得多，真撞上 SoC 硬解并发 session
/// 上限的概率也小得多。
class MovaLeadWarm implements MovaWarmTrigger {
  /// How long before the switch point to start warming.
  ///
  /// 距切换点多久开始预热。
  final Duration lead;

  /// Shortest clip worth warming for; shorter clips never warm.
  ///
  /// 值得预热的最短片长；更短的片段一律不预热。
  final Duration minDuration;

  /// Creates a lead-time trigger.
  ///
  /// 创建一个提前量触发策略。
  ///
  /// - [lead]: warm-up lead time / 预热提前量
  /// - [minDuration]: shortest clip worth warming for / 值得预热的最短片长
  const MovaLeadWarm({required this.lead, required this.minDuration});

  @override
  bool shouldWarm(MovaWarmCue cue) {
    final remaining = cue.remaining;
    if (remaining == null) return false;
    if (remaining <= Duration.zero) return false;
    final total = cue.total;
    if (total != null && total < minDuration) return false;
    return remaining <= lead;
  }
}

/// Warms up immediately, for switch points that are not predictable.
///
/// The quality-switch case: the user tapped a variant, "now" is the cue.
///
/// 立即预热，用于不可预测的切换点。
///
/// 清晰度切换场景：用户点了某一档，线索就是"现在"。
class MovaEagerWarm implements MovaWarmTrigger {
  /// Creates an eager trigger.
  ///
  /// 创建一个立即触发策略。
  const MovaEagerWarm();

  @override
  bool shouldWarm(MovaWarmCue cue) => true;
}
