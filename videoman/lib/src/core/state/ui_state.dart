/// Which transient heads-up overlay the controls layer should show.
///
/// 控制层当前应展示的临时提示浮层类型。
enum VmHud {
  /// No overlay shown.
  ///
  /// 无浮层。
  none,

  /// Volume adjustment overlay (left-side vertical drag).
  ///
  /// 音量调节浮层（左侧竖向拖动）。
  volume,

  /// Brightness adjustment overlay (right-side vertical drag).
  ///
  /// 亮度调节浮层（右侧竖向拖动）。
  brightness,

  /// Seek preview overlay (horizontal drag).
  ///
  /// 拖动进度预览浮层（横向拖动）。
  seek,

  /// Fill-mode change overlay (double tap).
  ///
  /// 填充模式切换浮层（双击）。
  fit,

  /// Quality switch overlay.
  ///
  /// 清晰度切换浮层。
  quality,

  /// Zoom overlay (pinch gesture).
  ///
  /// 缩放浮层（双指缩放手势）。
  zoom,
}

/// Immutable snapshot of transient UI/gesture interaction state.
///
/// Covers state that belongs to the controls layer's interaction model
/// rather than the playback engine itself — control-bar visibility, active
/// drag gesture, HUD overlay, and seek-preview position.
///
/// 临时性 UI/手势交互状态的不可变快照。
///
/// 涵盖属于控制层交互模型而非播放内核本身的状态——控制条可见性、当前拖动
/// 手势、HUD 浮层、拖动预览位置。
class VmUiState {
  /// Whether the control bar/overlay is currently visible.
  ///
  /// 控制条/浮层当前是否可见。
  final bool controlsVisible;

  /// Whether a drag gesture (seek/volume/brightness) is in progress.
  ///
  /// 是否有拖动手势（进度/音量/亮度）正在进行。
  final bool dragging;

  /// Which HUD overlay, if any, is currently shown.
  ///
  /// 当前展示的 HUD 浮层类型（若有）。
  final VmHud hud;

  /// Text content for the current HUD overlay, if any.
  ///
  /// 当前 HUD 浮层的文本内容（若有）。
  final String? hudText;

  /// Preview position while dragging the seek bar, before the seek commits.
  ///
  /// 拖动进度条时的预览位置，在拖动提交前生效。
  final Duration? previewAt;

  /// Creates a UI state snapshot; defaults to controls visible, idle,
  /// no HUD, and no preview.
  ///
  /// 创建一个 UI 状态快照；默认控制条可见、无手势、无 HUD、无预览。
  const VmUiState({
    this.controlsVisible = true,
    this.dragging = false,
    this.hud = VmHud.none,
    this.hudText,
    this.previewAt,
  });

  /// Returns a copy with the given fields replaced.
  ///
  /// [clearPreview] and [clearHudText] explicitly null out [previewAt] and
  /// [hudText] respectively — passing `null` for a nullable field is
  /// otherwise indistinguishable from "keep".
  ///
  /// 返回一个替换了指定字段的副本。
  ///
  /// [clearPreview]、[clearHudText] 用于显式清空 [previewAt]、[hudText]——
  /// 否则可空字段传 `null` 无法与"保持原值"区分。
  VmUiState copyWith({
    bool? controlsVisible,
    bool? dragging,
    VmHud? hud,
    String? hudText,
    Duration? previewAt,
    bool clearPreview = false,
    bool clearHudText = false,
  }) {
    return VmUiState(
      controlsVisible: controlsVisible ?? this.controlsVisible,
      dragging: dragging ?? this.dragging,
      hud: hud ?? this.hud,
      hudText: clearHudText ? null : (hudText ?? this.hudText),
      previewAt: clearPreview ? null : (previewAt ?? this.previewAt),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VmUiState &&
        other.controlsVisible == controlsVisible &&
        other.dragging == dragging &&
        other.hud == hud &&
        other.hudText == hudText &&
        other.previewAt == previewAt;
  }

  @override
  int get hashCode => Object.hash(controlsVisible, dragging, hud, hudText, previewAt);
}
