/// Named regions of the player overlay that components can be assigned to.
///
/// 播放器叠加层上可分配给组件的命名区域。
enum VmSlot {
  /// Invisible gesture-capturing region (tap/drag zones).
  ///
  /// 不可见的手势捕获区域（点击/拖拽区）。
  gesture,

  /// Heads-up display transient feedback (volume/brightness/seek toasts).
  ///
  /// 抬头显示的瞬时反馈（音量/亮度/进度提示）。
  hud,

  /// Top control bar area.
  ///
  /// 顶部控制条区域。
  top,

  /// Center of the player (play/pause, loading, error states).
  ///
  /// 播放器中心区域（播放/暂停、加载、错误状态）。
  center,

  /// Area directly above the bottom control bar.
  ///
  /// 底部控制条正上方的区域。
  bottomAbove,

  /// Bottom control bar area.
  ///
  /// 底部控制条区域。
  bottom,

  /// Full-bleed overlay above everything else (ads, custom banners).
  ///
  /// 覆盖在最上层的全屏叠加层（广告、自定义横幅）。
  overlay,
}
