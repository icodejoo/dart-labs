import '../recovery/fail.dart';

/// Start-up/stall timeouts and how to recover from them. Off by default: with
/// [enabled] false no timer is created, no stream is subscribed and `open()`
/// failures still throw to the caller exactly as before.
///
/// 起播/卡顿超时以及如何从中恢复。默认关闭：[enabled] 为 false 时不创建任何计时器、
/// 不订阅任何流，`open()` 的失败也照旧抛给调用方。
///
/// Example / 示例:
/// ```dart
/// createMovaEngine(options: const MovaOpts(
///   recovery: MovaRecoveryConfig(enabled: true, startTimeout: Duration(seconds: 8)),
/// ));
/// ```
class MovaRecoveryConfig {
  /// Master switch.
  ///
  /// 总开关。
  final bool enabled;

  /// Longest wait from an attempt being armed (while playback is intended) to
  /// its first frame.
  ///
  /// 一次尝试（在播放意图为真时）从武装到首帧的最长等待。
  final Duration startTimeout;

  /// Longest continuous buffering after the first frame while playing; `null`
  /// disables the stall watchdog.
  ///
  /// 出首帧后、播放中连续缓冲的最长时长；`null` 关闭卡顿看门狗。
  final Duration? stallTimeout;

  /// Whether a live source reaching its end counts as a failure (default true).
  ///
  /// 直播源走到结尾是否算失败（默认 true）。
  final bool liveEndIsFailure;

  /// Injectable recovery rule; `null` selects the default: VOD uses
  /// [MovaRetryThenFailover] (one retry per address), live uses
  /// [MovaLiveReconnect] unless [liveReconnect] is turned off.
  ///
  /// 可注入的恢复规则；`null` 选用默认规则：点播用 [MovaRetryThenFailover]（每个地址重试
  /// 一次），直播用 [MovaLiveReconnect]（除非关掉 [liveReconnect]）。
  final MovaRecoveryPolicy? policy;

  /// Whether the default policy keeps reconnecting live sources with
  /// exponential backoff (default true), so a publisher that restarts is picked
  /// up again. Set false to give live the same one-retry rule as VOD. Ignored
  /// when [policy] is set; VOD is never affected.
  ///
  /// 默认策略是否对直播源持续指数退避重连（默认 true），使推流端重启后能自动接上。设为 false
  /// 则直播与点播一样只重试一次。设置了 [policy] 时忽略；点播不受影响。
  final bool liveReconnect;

  /// Creates the config; the defaults are the recommended ones, only
  /// [enabled] needs flipping.
  ///
  /// 创建配置；默认值即推荐值，一般只需打开 [enabled]。
  const MovaRecoveryConfig({
    this.enabled = false,
    this.startTimeout = const Duration(seconds: 10),
    this.stallTimeout = const Duration(seconds: 10),
    this.liveEndIsFailure = true,
    this.policy,
    this.liveReconnect = true,
  });

  /// The policy actually in effect.
  ///
  /// 实际生效的策略。
  MovaRecoveryPolicy get effectivePolicy =>
      policy ?? (liveReconnect ? const MovaDefaultRecovery() : const MovaRetryThenFailover());

  /// Debug-checks the timeouts are positive; called by the engine on
  /// construction (a `Duration` comparison cannot live in a `const` initializer).
  ///
  /// debug 下检查超时为正；由引擎构造时调用（`Duration` 比较不能写在 `const` 构造器
  /// 的初始化列表里）。
  void assertValid() {
    assert(startTimeout > Duration.zero, 'MovaRecoveryConfig.startTimeout must be positive');
    assert(
      stallTimeout == null || stallTimeout! > Duration.zero,
      'MovaRecoveryConfig.stallTimeout must be positive or null',
    );
  }

  /// Returns a copy with the given fields replaced.
  ///
  /// 返回替换了指定字段的拷贝。
  ///
  /// - [enabled]: replacement master switch / 替换用的总开关
  /// - [startTimeout]: replacement start deadline / 替换用的起播期限
  /// - [stallTimeout]: replacement stall deadline / 替换用的卡顿期限
  /// - [clearStallTimeout]: set the stall deadline to `null` (off) / 把卡顿期限置为 `null`（关闭）
  /// - [liveEndIsFailure]: replacement live-end rule / 替换用的直播结尾规则
  /// - [policy]: replacement policy / 替换用的策略
  /// - [clearPolicy]: reset the policy to the default / 把策略重置为默认
  /// - [liveReconnect]: replacement live-reconnect switch / 替换用的直播重连开关
  ///
  /// Returns the new config / 返回新配置。
  MovaRecoveryConfig copyWith({
    bool? enabled,
    Duration? startTimeout,
    Duration? stallTimeout,
    bool clearStallTimeout = false,
    bool? liveEndIsFailure,
    MovaRecoveryPolicy? policy,
    bool clearPolicy = false,
    bool? liveReconnect,
  }) {
    return MovaRecoveryConfig(
      enabled: enabled ?? this.enabled,
      startTimeout: startTimeout ?? this.startTimeout,
      stallTimeout: clearStallTimeout ? null : (stallTimeout ?? this.stallTimeout),
      liveEndIsFailure: liveEndIsFailure ?? this.liveEndIsFailure,
      policy: clearPolicy ? null : (policy ?? this.policy),
      liveReconnect: liveReconnect ?? this.liveReconnect,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovaRecoveryConfig &&
          enabled == other.enabled &&
          startTimeout == other.startTimeout &&
          stallTimeout == other.stallTimeout &&
          liveEndIsFailure == other.liveEndIsFailure &&
          policy == other.policy &&
          liveReconnect == other.liveReconnect;

  @override
  int get hashCode => Object.hash(enabled, startTimeout, stallTimeout, liveEndIsFailure, policy, liveReconnect);
}
