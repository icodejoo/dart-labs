/// Heuristic buffering monitor for adaptive downshifting.
///
/// Counts buffering *rising edges* (playback stalls). When stalls reach
/// [threshold], [add] returns true once as a "downshift now" signal and the
/// counter resets. In the engine's native "auto" mode this monitor is
/// typically disabled and libmpv handles ABR itself; it exists to downshift
/// when the user has *pinned* a quality that the network can't sustain.
///
/// 用于自适应降档的启发式缓冲监测。
///
/// 统计缓冲*上升沿*（播放卡顿）。当卡顿次数达到 [threshold]，[add] 会返回一次
/// true 作为"立即降档"信号并重置计数。内核原生"自动"模式下通常禁用本监测、由
/// libmpv 自行做 ABR；它的价值在于当用户*锁定*了网络扛不住的清晰度时触发降档。
class VmBufferingAbr {
  /// Number of stalls that triggers a downshift suggestion.
  ///
  /// 触发降档建议所需的卡顿次数。
  final int threshold;

  bool _last = false;
  int _stalls = 0;

  /// Creates a monitor that downshifts after [threshold] stalls (default 3).
  ///
  /// 创建一个在 [threshold] 次卡顿后建议降档的监测器（默认 3）。
  VmBufferingAbr({this.threshold = 3});

  /// Number of stalls counted since the last downshift signal.
  ///
  /// 距上次降档信号以来累计的卡顿次数。
  int get stalls => _stalls;

  /// Feeds the latest buffering flag; returns true exactly when a downshift
  /// should happen (threshold reached), resetting the counter.
  ///
  /// 输入最新的缓冲标志；恰在应降档时（达到阈值）返回 true 并重置计数。
  ///
  /// - [buffering]: current buffering state / 当前是否在缓冲
  /// - returns whether to downshift now / 返回是否应立即降档
  bool add(bool buffering) {
    final risingEdge = buffering && !_last;
    _last = buffering;
    if (!risingEdge) return false;
    _stalls++;
    if (_stalls >= threshold) {
      _stalls = 0;
      return true;
    }
    return false;
  }

  /// Resets the monitor (e.g. after a manual quality change).
  ///
  /// 重置监测器（如手动切换清晰度后）。
  void reset() {
    _last = false;
    _stalls = 0;
  }
}
