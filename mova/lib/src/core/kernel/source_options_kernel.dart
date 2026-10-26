/// Optional kernel capability: libmpv options that apply to one source only.
/// A kernel that lacks it simply ignores `MovaSource.mpvOptions`.
///
/// 可选的内核能力：只对某一个源生效的 libmpv 选项。不具备此能力的内核会直接忽略
/// `MovaSource.mpvOptions`。
abstract class MovaSourceOptionsKernel {
  /// Stages [options] for the very next `open()`: that open applies them just
  /// before loading, and every later open first restores what the previous one
  /// changed — so options never leak into another source. The engine calls this
  /// right before each `open()` (an empty map when the source has none).
  ///
  /// 为紧随其后的那一次 `open()` 暂存 [options]：该次 open 在加载前下发它们，之后每次 open
  /// 都会先还原上一次改动过的属性——因此选项不会泄漏到别的源。引擎在每次 `open()` 前调用
  /// （源没有选项时传空 Map）。
  ///
  /// - [options]: mpv option/property name to value / mpv 选项/属性名 → 值
  void stageSourceOptions(Map<String, String> options);
}
