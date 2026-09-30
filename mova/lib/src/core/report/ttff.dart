/// Measures "open() called → first frame actually playing" per
/// `doc/plans/2026-09-29-telemetry-enhancement.md` §D1.
///
/// Armed on `open(autoPlay: true)`; lands on the first falling edge of the
/// kernel's `buffering` flag, which media_kit derives from mpv's `core-idle`
/// ("only false if there's actually video playing"). Pure logic — no
/// `Timer`, no internal `DateTime.now()` call; every timestamp is passed in
/// by the caller so tests are deterministic.
///
/// 按 §D1 测量"open() 调用 → 画面真正开始播"。
///
/// 在 `open(autoPlay: true)` 时武装；落在内核 `buffering` 标志的首个下降沿上——
/// 该标志由 media_kit 从 mpv 的 `core-idle` 推导（"只有真的在播画面时才为
/// false"）。纯逻辑——无 `Timer`、内部不调用 `DateTime.now()`；一切时间戳均由
/// 调用方传入，使测试可确定性复现。
class MovaTtffTracker {
  bool _armed = false;
  bool _landed = false;
  bool _sawBuffering = false;
  Duration? _lastProgress;
  DateTime? _armedAt;

  /// Whether the first frame has already landed for the current arming.
  ///
  /// 当前这次武装是否已经落地首帧。
  bool get landed => _landed;

  /// Whether this tracker is currently armed and waiting for the first frame.
  ///
  /// 该 tracker 是否正处于已武装、等待首帧的状态。
  bool get isArmed => _armed && !_landed;

  /// Whether the current session was ever armed (i.e. opened with
  /// `autoPlay: true`) — used to decide whether a teardown before landing is
  /// a real `startupFail` or simply a session that never intended to measure
  /// TTFF at all.
  ///
  /// 当前会话是否曾经被武装过（即以 `autoPlay: true` 打开）——用于判断落地前的
  /// 一次 teardown 究竟是真实的 `startupFail`，还是本就无意测量 TTFF 的会话。
  bool get wasArmed => _armed;

  /// The timestamp [arm] was called with, or `null` when never armed.
  ///
  /// [arm] 被调用时传入的时间戳；从未武装过时为 `null`。
  DateTime? get armedAt => _armedAt;

  /// Arms measurement at [at]; a no-op measurement window when [autoPlay] is
  /// false, since `core-idle` never becomes false without autoplay and the
  /// resulting number would be meaningless.
  ///
  /// 在 [at] 时刻武装测量；[autoPlay] 为假时不进入武装（`core-idle` 在不自动
  /// 播放时永远不会转 false，测出的数字没有意义）。
  void arm(DateTime at, {required bool autoPlay}) {
    reset();
    if (!autoPlay) return;
    _armed = true;
    _armedAt = at;
  }

  /// Feeds a `buffering` observation; returns the elapsed time since arming
  /// exactly when this is the first frame landing (a `true`→`false` falling
  /// edge while armed and not yet landed), otherwise `null`.
  ///
  /// 输入一次 `buffering` 观测；恰在此次是首帧落地时（武装中且尚未落地的
  /// `true`→`false` 下降沿）返回距武装以来的耗时，否则返回 `null`。
  Duration? onBuffering(bool buffering, DateTime at) {
    if (!isArmed) return null;
    if (buffering) {
      _sawBuffering = true;
      return null;
    }
    // 只认 true→false 的下降沿：open 之后 buffering 流会立刻先发一个初始 false，
    // 不是首帧（真机实测：失败源/限速源也在 40–160ms 就"落地"）。
    if (!_sawBuffering) return null;
    return _land(at);
  }

  /// Feeds a native `MPV_EVENT_PLAYBACK_RESTART` observation (2026-09-29
  /// update to §D1) — the same landing semantics as [onBuffering]'s falling
  /// edge, but driven directly by libmpv's own event instead of inferred from
  /// the `buffering` flag. Returns the elapsed time since arming exactly when
  /// this lands the first frame, otherwise `null`.
  ///
  /// 输入一次原生 `MPV_EVENT_PLAYBACK_RESTART` 观测（§D1 的 2026-09-29 更新）——
  /// 落地语义与 [onBuffering] 的下降沿相同，但直接来自 libmpv 自己的事件，而非
  /// 从 `buffering` 标志推断。恰在此次落地首帧时返回距武装以来的耗时，否则
  /// 返回 `null`。
  Duration? onNativeRestart(DateTime at) => isArmed ? _land(at) : null;

  /// Feeds a position sample — the fallback landing when neither the native
  /// restart nor a `buffering` edge is available. Lands only on two consecutive
  /// increasing samples > 0: a lone sample is untrustworthy, since the kernel
  /// replays the previous media's stale position right after `open`.
  ///
  /// 输入一次位置样本——原生 RESTART 与 `buffering` 边沿都不可用时的兜底落地。
  /// 需连续两个递增且 > 0 的样本才落地：单个样本不可信，open 之后内核会先回放
  /// 上一条素材的残留位置（真机实测）。
  ///
  /// [position] 是当前播放位置；[at] 是事件时间。返回距武装的耗时；未落地返回 null。
  /// 示例：`tracker.onProgress(const Duration(milliseconds: 40), now)`
  Duration? onProgress(Duration position, DateTime at) {
    if (!isArmed) return null;
    final prev = _lastProgress;
    _lastProgress = position;
    if (prev == null || position <= Duration.zero || position <= prev) return null;
    return _land(at);
  }

  /// Marks the first frame as landed and returns the elapsed time since arming.
  ///
  /// 标记首帧落地，返回距武装以来的耗时。
  Duration? _land(DateTime at) {
    _landed = true;
    final armedAt = _armedAt;
    return armedAt == null ? null : at.difference(armedAt);
  }

  /// Resets to the unarmed state so a new [arm] can start fresh.
  ///
  /// 重置为未武装状态，使新的 [arm] 可以重新开始。
  void reset() {
    _armed = false;
    _landed = false;
    _sawBuffering = false;
    _lastProgress = null;
    _armedAt = null;
  }
}
