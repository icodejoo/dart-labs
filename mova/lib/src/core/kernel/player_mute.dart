/// Optional player-local warm-up mute, independent of system volume and standby.
/// Unsupported implementations may return false; callers continue without mute.
///
/// 可选的播放器预热静音，独立于系统音量和待机。不支持时返回 false，调用方不静音。
abstract class MovaPlayerMute {
  /// Sets or releases only the warm-up mute owned by this capability. Idempotent;
  /// preserves the original mute and any standby mute. Never throws.
  ///
  /// 设置或释放本能力持有的预热静音。幂等；保留原始静音和待机静音，绝不抛错。
  ///
  /// - [on]: acquire when true, release when false / true 获取，false 释放
  ///
  /// Returns whether the operation succeeded / 返回操作是否成功。
  ///
  /// Example / 示例：`if (kernel is MovaPlayerMute) await kernel.setWarmMute(true);`
  Future<bool> setWarmMute(bool on);
}
