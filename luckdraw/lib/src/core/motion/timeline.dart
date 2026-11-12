import '../foundation/constants.dart';
import '../foundation/duration_ms.dart';

/// 把原始时间戳转为可暂停、单帧推进有上限的有效毫秒时间。
///
/// 例如 `timeline.advance(const Duration(milliseconds: 16))`；首帧只设基准。
final class LuckyTimeline {
  /// 创建时间轴；[maxFrameDelta] 控制每次 advance 的最大推进量。
  LuckyTimeline({this.maxFrameDelta = kLuckyDefaultMaxFrameDelta});

  /// 每帧最大推进量。
  Duration maxFrameDelta;

  /// 已累计的有效毫秒数。
  double get nowMs => _now;

  /// 最近一次推进的毫秒数。
  double get lastDeltaMs => _delta;

  /// 用户或生命周期任一暂停时为 true。
  bool get isPaused => _userPaused || _lifecyclePaused;

  /// 有效时间累计值。
  double _now = 0;

  /// 最近一次增量。
  double _delta = 0;

  /// 最近一次原始时间。
  double _lastRaw = 0;

  /// 下次推进是否仅建立基准。
  bool _needsRebase = true;

  /// 用户暂停标记。
  bool _userPaused = false;

  /// 生命周期暂停标记。
  bool _lifecyclePaused = false;

  /// 让下一次 advance 只建立时间基准，保留累计有效时间。
  void rebase() => _needsRebase = true;

  /// 推进到 [raw]，负增量视为零，暂停期间不推进有效时间。
  void advance(Duration raw) {
    final rawMs = luckyMs(raw);
    var d = 0.0;
    if (_needsRebase) {
      _needsRebase = false;
    } else {
      d = rawMs - _lastRaw;
      final max = luckyMs(maxFrameDelta);
      if (d < 0) d = 0;
      if (d > max) d = max;
      if (isPaused) d = 0;
    }
    _lastRaw = rawMs;
    _now += d;
    _delta = d;
  }

  /// 标记用户暂停。
  void pauseUser() => _userPaused = true;

  /// 恢复用户暂停，并让恢复后的首帧只建立基准。
  void resumeUser() {
    _userPaused = false;
    rebase();
  }

  /// 标记生命周期暂停。
  void pauseLifecycle() => _lifecyclePaused = true;

  /// 恢复生命周期暂停，并让恢复后的首帧只建立基准。
  void resumeLifecycle() {
    _lifecyclePaused = false;
    rebase();
  }
}
