/// Video surface fill mode.
///
/// 画面填充模式。
enum VmFit {
  /// Fit entirely inside the box, letterboxed (default).
  ///
  /// 完整放入画框，可能留黑边（默认）。
  contain,

  /// Fill the box, cropping overflow.
  ///
  /// 铺满画框，裁掉溢出部分。
  cover,

  /// Stretch to fill, ignoring aspect ratio.
  ///
  /// 拉伸铺满，忽略宽高比。
  fill;

  /// The next mode in the contain → cover → fill cycle.
  ///
  /// contain → cover → fill 循环中的下一个模式。
  VmFit get next => switch (this) {
        VmFit.contain => VmFit.cover,
        VmFit.cover => VmFit.fill,
        VmFit.fill => VmFit.contain,
      };

  /// Short display label key for the mode (resolved by the UI layer).
  ///
  /// 模式的简短显示标签键（由 UI 层解析为具体文案）。
  String get labelKey => switch (this) {
        VmFit.contain => 'contain',
        VmFit.cover => 'cover',
        VmFit.fill => 'fill',
      };
}
