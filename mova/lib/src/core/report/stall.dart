/// One completed stall (rebuffer) record.
///
/// 一条已结束的卡顿（rebuffer）记录。
class MovaStall {
  /// How long the stall lasted.
  ///
  /// 卡顿持续时长。
  final Duration duration;

  /// When the stall ended (the falling edge).
  ///
  /// 卡顿结束的时刻（下降沿）。
  final DateTime at;

  /// Creates a stall record.
  ///
  /// 创建一条卡顿记录。
  const MovaStall({required this.duration, required this.at});
}

/// Turns a stream of "stalled right now" observations into completed stall
/// records. Mirrors `MovaAbrPolicy`: mova ships a default, hosts can inject.
///
/// 把一连串"此刻是否卡住"的观测，转换成一条条"已结束的卡顿"记录。
/// 与 `MovaAbrPolicy` 同一范式：mova 给默认实现，宿主可注入替换。
abstract class MovaStallPolicy {
  /// Feeds one observation; returns the finished stall when [stalled] just
  /// fell back to false, otherwise `null`.
  ///
  /// 输入一次观测；仅当 [stalled] 刚刚落回 false 时返回本次已结束的卡顿，
  /// 否则返回 `null`。
  MovaStall? onStall(bool stalled, DateTime at);

  /// Drops accumulated state (new source / quality switch).
  ///
  /// 丢弃累积状态（换源 / 换清晰度）。
  void reset();
}

/// Default edge-based policy: counts a stall from the rising edge to the
/// falling edge, swallowing anything shorter than [minStall] (mpv coalesces
/// property-change notifications, so sub-frame flaps are noise, not stalls).
///
/// 默认的边沿策略：从上升沿计到下降沿，吞掉短于 [minStall] 的抖动
/// （mpv 会合并属性变更通知，亚帧级翻转是噪声而非卡顿）。
class MovaEdgeStall implements MovaStallPolicy {
  /// Stalls shorter than this are swallowed as noise.
  ///
  /// 短于此值的卡顿按噪声吞掉。
  final Duration minStall;

  /// Creates an edge-based stall policy.
  ///
  /// 创建一个边沿式卡顿策略。
  MovaEdgeStall({this.minStall = const Duration(milliseconds: 200)});

  bool _stalled = false;
  DateTime? _risingAt;

  @override
  MovaStall? onStall(bool stalled, DateTime at) {
    if (stalled && !_stalled) {
      _stalled = true;
      _risingAt = at;
      return null;
    }
    if (!stalled && _stalled) {
      _stalled = false;
      final rising = _risingAt;
      _risingAt = null;
      if (rising == null) return null;
      final duration = at.difference(rising);
      if (duration < minStall) return null;
      return MovaStall(duration: duration, at: at);
    }
    return null;
  }

  @override
  void reset() {
    _stalled = false;
    _risingAt = null;
  }
}
