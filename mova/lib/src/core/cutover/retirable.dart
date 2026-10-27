/// Engines that can be told they are being retired by a hand-off: their view
/// state (fullscreen / orientation) has been migrated to a successor, so
/// disposing must not reset the shared platform orientation / system bars.
/// A capability next to `MovaApi` (like `MovaKeepAlive`); check with `is`.
///
/// 能被告知"正被换指退役"的引擎：其视图状态（全屏/方向）已迁给接班引擎，
/// 因此 dispose 时不能复位共享的平台方向/系统栏。与 `MovaApi` 并列的能力接口
/// （同 `MovaKeepAlive`）；用 `is` 判断。
abstract class MovaHandoffRetirable {
  /// Marks this engine as retired by a hand-off. Call before `dispose()`;
  /// a retired engine's `dispose()` skips the orientation / system-bar reset.
  /// Idempotent. An engine disposed without this call still resets as usual.
  ///
  /// 标记本引擎已被换指退役。须在 `dispose()` 之前调用；已退役引擎的
  /// `dispose()` 跳过方向/系统栏复位。幂等。未调用就 dispose 的引擎照常复位。
  ///
  /// Example / 示例:
  /// ```dart
  /// if (old is MovaHandoffRetirable) (old as MovaHandoffRetirable).markRetired();
  /// await old.dispose();
  /// ```
  void markRetired();
}
