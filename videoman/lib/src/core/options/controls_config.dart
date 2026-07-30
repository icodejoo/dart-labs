/// Control-bar behaviour configuration.
///
/// 控制条行为配置。
class VmControlsConfig {
  /// Whether the control bar auto-hides after [autoHideDelay] of inactivity.
  ///
  /// 控制条是否在 [autoHideDelay] 无操作后自动隐藏。
  final bool autoHide;

  /// Inactivity duration before the control bar auto-hides.
  ///
  /// 控制条自动隐藏前的无操作时长。
  final Duration autoHideDelay;

  /// Whether the control bar is visible immediately when playback starts.
  ///
  /// 播放开始时控制条是否立即可见。
  final bool showOnStart;

  /// Creates a controls config; auto-hide on with a 3-second delay, and
  /// visible on start, by default.
  ///
  /// 创建控制条配置；默认开启自动隐藏（3 秒延迟），且开始播放时可见。
  const VmControlsConfig({
    this.autoHide = true,
    this.autoHideDelay = const Duration(seconds: 3),
    this.showOnStart = true,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VmControlsConfig &&
          runtimeType == other.runtimeType &&
          autoHide == other.autoHide &&
          autoHideDelay == other.autoHideDelay &&
          showOnStart == other.showOnStart;

  @override
  int get hashCode => Object.hash(autoHide, autoHideDelay, showOnStart);
}
