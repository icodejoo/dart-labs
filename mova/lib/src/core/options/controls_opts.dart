/// Control-bar behaviour options.
///
/// 控制条行为配置。
class MovaCtrlsOpts {
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

  /// Duration of the show/hide fade animation for the control bars.
  ///
  /// 控制条显示/隐藏渐变动画的时长。
  final Duration fadeDuration;

  /// 是否启用当前播放器聚焦时的快捷键；默认 false。
  ///
  /// 空格播放/暂停，左右键快退/快进 10 秒，上下键调音量，F 切换全屏，Esc 退出全屏。
  /// 文本输入、锁定、PiP 和 mini 状态不处理播放器快捷键。
  /// 示例：`MovaCtrlsOpts(shortcuts: true)`。
  final bool shortcuts;

  /// Creates controls options; auto-hide on with a 3-second delay, and
  /// visible on start, by default.
  ///
  /// 创建控制条配置；默认开启自动隐藏（3 秒延迟），且开始播放时可见。
  const MovaCtrlsOpts({
    this.autoHide = true,
    this.shortcuts = false,
    this.autoHideDelay = const Duration(seconds: 3),
    this.showOnStart = true,
    this.fadeDuration = const Duration(milliseconds: 200),
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovaCtrlsOpts &&
          runtimeType == other.runtimeType &&
          autoHide == other.autoHide &&
          shortcuts == other.shortcuts &&
          autoHideDelay == other.autoHideDelay &&
          showOnStart == other.showOnStart &&
          fadeDuration == other.fadeDuration;

  @override
  int get hashCode => Object.hash(
    autoHide,
    autoHideDelay,
    showOnStart,
    fadeDuration,
    shortcuts,
  );
}
