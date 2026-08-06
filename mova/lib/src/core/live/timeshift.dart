import '../options/live_config.dart';
import '../state/state.dart';

/// Resolves the seekable DVR/time-shift window for [s] under [cfg].
///
/// Precedence: an injected [MovaLiveConfig.windowResolver] wins, then an
/// explicit [MovaLiveConfig.dvrWindow], then the kernel-reported
/// [MovaState.duration] (a live HLS stream's "duration" is its sliding-window
/// length). A negative result is clamped to zero so callers never see a
/// nonsensical window.
///
/// 在配置 [cfg] 下解析状态 [s] 的可拖动 DVR/时移窗口。
///
/// 优先级：注入的 [MovaLiveConfig.windowResolver] 最高，其次是显式的
/// [MovaLiveConfig.dvrWindow]，最后回落到内核报告的 [MovaState.duration]
/// （直播 HLS 流的"时长"即其滑动窗口长度）。结果为负时被 clamp 到零，
/// 使调用方绝不会拿到荒谬的窗口值。
///
/// - [s]: the current player state / 当前播放器状态
/// - [cfg]: the live configuration in effect / 生效的直播配置
///
/// Returns the window length, never negative / 返回窗口长度，绝不为负。
Duration resolveWindow(MovaState s, MovaLiveConfig cfg) {
  final resolver = cfg.windowResolver;
  final raw = resolver != null ? resolver(s) : (cfg.dvrWindow ?? s.duration);
  return raw.isNegative ? Duration.zero : raw;
}

/// How far [position] is behind the live edge of a [window], or `null` when it
/// is close enough to the edge to count as live.
///
/// Returns `null` (i.e. "at the edge") when the window is unknown/zero, when
/// the gap is within [edgeThreshold], or when [position] sits at or past the
/// window end — a playhead ahead of the window is a clock-skew artefact, not a
/// negative time-shift.
///
/// 返回 [position] 落后 [window] 直播边缘的时长；足够接近边缘时返回 `null`。
///
/// 以下三种情况都返回 `null`（即"在边缘"）：窗口未知/为零；差距在
/// [edgeThreshold] 以内；[position] 位于窗口末端或之后——播放头跑到窗口前面
/// 是时钟偏差造成的假象，不是负的时移量。
///
/// - [position]: current playhead within the window / 窗口内的当前播放位置
/// - [window]: seekable window length / 可拖动窗口长度
/// - [edgeThreshold]: gap still counted as live / 仍算作直播的差距阈值
///
/// Returns the lag, or `null` when at the edge / 返回落后时长；在边缘时返回 `null`。
Duration? behindOf(Duration position, Duration window, Duration edgeThreshold) {
  if (window <= Duration.zero) return null;
  final behind = window - position;
  if (behind <= edgeThreshold) return null;
  return behind;
}

/// Whether [position] counts as sitting at the live edge of [window].
///
/// Exactly the inverse of [behindOf] returning a value; kept as its own
/// function so UI code reads as intent rather than as a null check.
///
/// 判断 [position] 是否算作处于 [window] 的直播边缘。
///
/// 与 [behindOf] 返回非空恰好互为反面；单独成函数是为了让 UI 代码读起来是
/// 意图表达，而不是一次 null 判断。
///
/// - [position]: current playhead within the window / 窗口内的当前播放位置
/// - [window]: seekable window length / 可拖动窗口长度
/// - [edgeThreshold]: gap still counted as live / 仍算作直播的差距阈值
///
/// Returns whether playback is at the live edge / 返回是否处于直播边缘。
bool atLiveEdge(Duration position, Duration window, Duration edgeThreshold) =>
    behindOf(position, window, edgeThreshold) == null;
