/// 抽奖阶段。
enum LuckyPhase {
  /// 空闲。
  idle,

  /// 待机慢转。
  idleSpinning,

  /// 加速。
  accelerating,

  /// 匀速。
  cruising,

  /// 减速。
  decelerating,

  /// 已出结果。
  settled,
}

/// 抽奖阶段的命令和时钟判断。
extension LuckyPhaseX on LuckyPhase {
  /// 是否需要时钟推进。
  bool get isMoving =>
      this == LuckyPhase.idleSpinning ||
      this == LuckyPhase.accelerating ||
      this == LuckyPhase.cruising ||
      this == LuckyPhase.decelerating;

  /// 是否接受 play()。
  bool get canPlay =>
      this == LuckyPhase.idle ||
      this == LuckyPhase.settled ||
      this == LuckyPhase.idleSpinning;

  /// 是否接受开始回调，与 canPlay 一致。
  bool get acceptsStart => canPlay;
}
