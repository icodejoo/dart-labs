/// Read-only duration information for an animated SVG document.
///
/// 动画 SVG 文档的只读时长信息。
final class XvgAnimationInfo {
  /// Creates duration information from a settling time and optional loop period.
  ///
  /// 根据稳定时刻、循环标志和可选循环周期创建时长信息。
  const XvgAnimationInfo({
    required this.settleTime,
    required this.loops,
    this.loopPeriod,
  });

  /// Latest finite active end or infinite animation begin, excluding disabled
  /// timelines; zero when there are no later times.
  ///
  /// 有限活动结束和无限动画开始的最晚时刻；忽略失效时间线，无更晚时刻时为零。
  final Duration settleTime;

  /// Whether the document has an indefinite loop.
  ///
  /// 文档是否含无限循环。
  final bool loops;

  /// Steady-state period, or null if absent, undefined, or longer than 60 seconds.
  /// Alternating directions contribute twice their iteration duration.
  ///
  /// 稳态周期；无循环、无法确定或超过 60 秒时为 null；交替方向按双倍单轮时长计。
  final Duration? loopPeriod;

  /// Settling time for finite documents, settling time plus one known period
  /// for looping documents, or null when the loop period is unknown.
  ///
  /// 有限文档返回稳定时刻；已知循环周期时返回稳定时刻加一个周期，否则返回 null。
  Duration? get naturalDuration => !loops
      ? settleTime
      : loopPeriod == null
      ? null
      : settleTime + loopPeriod!;

  /// Whether all duration information matches [other].
  ///
  /// 所有时长信息是否与 [other] 相等。
  @override
  bool operator ==(Object other) =>
      other is XvgAnimationInfo &&
      other.settleTime == settleTime &&
      other.loops == loops &&
      other.loopPeriod == loopPeriod;

  /// Hash of all duration information.
  ///
  /// 所有时长信息的哈希值。
  @override
  int get hashCode => Object.hash(settleTime, loops, loopPeriod);

  /// A description containing the settling time, loop flag, and period.
  ///
  /// 包含稳定时刻、循环标志和周期的描述。
  @override
  String toString() =>
      'XvgAnimationInfo(settleTime: $settleTime, loops: $loops, '
      'loopPeriod: $loopPeriod)';
}
