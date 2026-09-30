import 'stats_probe.dart' show MovaEndFileReason;

/// Why a playback session ended. Parallel to ExoPlayer's
/// ENDED/STOPPED/FAILED/ABANDONED terminal states.
///
/// 一次播放会话的结束原因。与 ExoPlayer 的
/// ENDED/STOPPED/FAILED/ABANDONED 终止态一一对应。
enum MovaSessionEnd {
  /// Playback reached the end of the media (`MovaDone`).
  ///
  /// 播放到达媒体末尾（`MovaDone`）。
  ended,

  /// Torn down after the first frame — a new `open()` or `dispose()`.
  ///
  /// 首帧之后被拆掉——新的 `open()` 或 `dispose()`。
  stopped,

  /// A fatal error ended it.
  ///
  /// 被一次致命错误终结。
  failed,

  /// Torn down before the first frame ever arrived, with no fatal error —
  /// the user gave up waiting (Mux "exits before video start").
  ///
  /// 首帧还没出来就被拆掉，且没有致命错误——用户等不及走了
  /// （Mux 的 "exits before video start"）。
  abandoned,
}

/// Classifies how a session ended, per
/// `doc/plans/2026-09-29-telemetry-enhancement.md` §D3. Pure: every input is
/// explicit so the whole four-way split is unit-testable without a kernel.
///
/// 按 §D3 判定会话结束原因。纯函数：所有输入都显式传入，四个分支无需内核即可
/// 单测。
///
/// - [fatalSeen]: a fatal error was recorded / 本会话记录过致命错误
/// - [completed]: playback reached the end / 播放已到达末尾
/// - [firstFrame]: whether the first frame ever landed / 首帧是否曾经落地
///
/// Returns the terminal reason / 返回终止原因。
MovaSessionEnd resolveSessionEnd({
  required bool fatalSeen,
  required bool completed,
  required bool firstFrame,
}) => fatalSeen
    ? MovaSessionEnd.failed
    : completed
        ? MovaSessionEnd.ended
        : firstFrame
            ? MovaSessionEnd.stopped
            : MovaSessionEnd.abandoned;

/// Same four-way split as [resolveSessionEnd], but corroborated by the native
/// `MPV_EVENT_END_FILE` reason when one arrived before teardown (2026-09-29
/// update to §D3). `MovaDone`/[completed] stays authoritative for `ended` —
/// media_kit's forced `--keep-open=yes` means mpv never reports a native
/// `eof` reason, so [completed] is still the only signal for that branch.
/// [nativeReason] `null` (no native event arrived, or the kernel doesn't
/// support `observeEvent`) falls back to exactly [resolveSessionEnd]'s
/// behavior — this function is a strict enhancement, not a replacement.
///
/// 与 [resolveSessionEnd] 同样的四分，但当 teardown 前收到过原生
/// `MPV_EVENT_END_FILE` 原因时用它佐证（§D3 的 2026-09-29 更新）。`ended`
/// 分支仍以 `MovaDone`/[completed] 为准——media_kit 强制的 `--keep-open=yes`
/// 意味着 mpv 永远不会报告原生 `eof` 原因，因此该分支的唯一信号仍是
/// [completed]。[nativeReason] 为 `null`（teardown 前没有原生事件到达，或内核
/// 不支持 `observeEvent`）时行为与 [resolveSessionEnd] 完全一致——本函数是严格
/// 意义上的增强，而非替换。
MovaSessionEnd resolveSessionEndNative({
  required MovaEndFileReason? nativeReason,
  required bool fatalSeen,
  required bool completed,
  required bool firstFrame,
}) {
  // Same priority order as resolveSessionEnd (failed > ended > stopped >
  // abandoned) — the native reason only ever widens what counts as
  // "fatal", it never reorders the branches, so passing nativeReason: null
  // reduces to resolveSessionEnd exactly, including "fatal wins over
  // completed".
  //
  // 与 resolveSessionEnd 相同的优先级顺序（failed > ended > stopped >
  // abandoned）——原生原因只是拓宽了"什么算致命"，从不重排分支，因此传
  // nativeReason: null 会精确退化为 resolveSessionEnd，包括"fatal 优先于
  // completed"这一条。
  final effectiveFatal = fatalSeen || nativeReason == MovaEndFileReason.error;
  return resolveSessionEnd(fatalSeen: effectiveFatal, completed: completed, firstFrame: firstFrame);
}

/// Accumulates one session's watch-time/stall/position tallies.
///
/// [watchedMs] only accrues while actually playing and not stalled — the
/// numerator half of the rebuffer-rate formula.
///
/// 累计一次会话的观看时长/卡顿/位置数据。
///
/// [watchedMs] 只在真正播放且未卡顿期间累加——卡顿率公式的分子部分。
class MovaSessionTally {
  int _watchedMs = 0;
  int _stallCount = 0;
  int _stallMs = 0;
  int _maxPositionMs = 0;
  int _durationMs = 0;

  bool _playing = false;
  bool _stalled = false;
  DateTime? _lastTick;

  /// Total watched time in milliseconds (playing and not stalled).
  ///
  /// 累计观看时长（毫秒；播放且未卡顿）。
  int get watchedMs => _watchedMs;

  /// Total number of finished stalls.
  ///
  /// 已结束的卡顿总次数。
  int get stallCount => _stallCount;

  /// Total stalled time in milliseconds.
  ///
  /// 累计卡顿时长（毫秒）。
  int get stallMs => _stallMs;

  /// Furthest playback position reached, in milliseconds.
  ///
  /// 到达过的最远播放位置（毫秒）。
  int get maxPositionMs => _maxPositionMs;

  /// The media's duration in milliseconds, or 0 when unknown (live/unset).
  ///
  /// 媒体时长（毫秒），未知（直播/未设置）时为 0。
  int get durationMs => _durationMs;

  /// Records the playing/paused flag; call before advancing the clock via
  /// [tick] so the interval just elapsed is attributed correctly.
  ///
  /// 记录播放/暂停标志；应在通过 [tick] 推进时钟前调用，以便刚经过的时间段被
  /// 正确归因。
  void setPlaying(bool playing) => _playing = playing;

  /// Records the real stalled flag (from `MovaStatsProbe.stalling` or the
  /// degraded `buffering` signal).
  ///
  /// 记录真实的卡顿标志（来自 `MovaStatsProbe.stalling` 或降级的
  /// `buffering` 信号）。
  void setStalled(bool stalled) => _stalled = stalled;

  /// Advances the internal clock to [at], attributing the elapsed interval
  /// since the previous tick to watched/stalled time per the flags set via
  /// [setPlaying]/[setStalled].
  ///
  /// 把内部时钟推进到 [at]，按 [setPlaying]/[setStalled] 设置的标志，把距上次
  /// tick 以来经过的时间归因到观看/卡顿时长。
  void tick(DateTime at) {
    final last = _lastTick;
    _lastTick = at;
    if (last == null) return;
    final elapsedMs = at.difference(last).inMilliseconds;
    if (elapsedMs <= 0) return;
    if (_stalled) {
      _stallMs += elapsedMs;
    } else if (_playing) {
      _watchedMs += elapsedMs;
    }
  }

  /// Counts one finished stall (from `MovaStallPolicy.onStall`). Only bumps the
  /// count: the stalled time itself is already accumulated by [tick] while
  /// [setStalled] is on, so adding the duration again would double-count it.
  ///
  /// 记一次已结束的卡顿（来自 `MovaStallPolicy.onStall`）。只加次数：卡顿时长
  /// 已在 [setStalled] 开启期间由 [tick] 累计，再加一次 duration 会重复计时
  /// （真机实测 stallMs 曾是真实值的 2 倍）。
  void addStall() => _stallCount++;

  /// Records the latest known playback position.
  ///
  /// 记录最近已知的播放位置。
  void recordPosition(Duration position) {
    final ms = position.inMilliseconds;
    if (ms > _maxPositionMs) _maxPositionMs = ms;
  }

  /// Records the media's duration, once known.
  ///
  /// 记录媒体时长（已知时）。
  void setDuration(Duration duration) {
    _durationMs = duration.inMilliseconds;
  }

  /// The rebuffer rate: `stallMs / (watchedMs + stallMs)`, 0 when the
  /// denominator is 0 — mirrors 腾讯云"平均卡顿率" / Mux Rebuffer Percentage.
  ///
  /// 卡顿率：`stallMs / (watchedMs + stallMs)`，分母为 0 时返回 0——与腾讯云
  /// "平均卡顿率"、Mux Rebuffer Percentage 同式。
  double get rebufferRate {
    final denom = _watchedMs + _stallMs;
    if (denom <= 0) return 0;
    return _stallMs / denom;
  }

  /// Completion percentage: `maxPositionMs / durationMs * 100`, or `null`
  /// when the duration is unknown (live, or never reported).
  ///
  /// 完成度百分比：`maxPositionMs / durationMs * 100`；时长未知（直播或从未
  /// 上报）时为 `null`。
  double? get completionPercent {
    if (_durationMs <= 0) return null;
    return _maxPositionMs / _durationMs * 100;
  }
}
