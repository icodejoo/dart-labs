/// Which observation landed the first frame of a playback attempt.
///
/// 哪一种观测让一次播放尝试的首帧落地。
enum MovaFirstFrameSignal {
  /// Native `MPV_EVENT_PLAYBACK_RESTART` — the precise signal.
  ///
  /// 原生 `MPV_EVENT_PLAYBACK_RESTART`——精确信号。
  restart,

  /// A `buffering` true→false falling edge (fallback).
  ///
  /// `buffering` 的 true→false 下降沿（兜底）。
  buffering,

  /// Two consecutive increasing positions above zero (fallback).
  ///
  /// 连续两个递增且大于 0 的位置样本（兜底）。
  progress,

  /// The first non-zero video size after a paused open (fallback).
  ///
  /// 暂停态打开后首个非零画面尺寸（兜底）。
  size,

  /// A fallback fired while the native signal was live, and no restart
  /// followed within the grace window.
  ///
  /// 原生信号在工作时兜底信号先到，且宽限期内始终没等到 RESTART。
  grace,
}

/// Decides when one playback attempt has actually started presenting media.
///
/// Pure logic: no `Timer`, no clock. The owner feeds observations and starts
/// the grace timer itself when [awaitingGrace] turns true. Every `onXxx`
/// returns the landing signal exactly once, or `null`.
///
/// 判定一次播放尝试何时真正开始呈现媒体。
///
/// 纯逻辑：无 `Timer`、无时钟。持有者喂观测，并在 [awaitingGrace] 变 true 时自己
/// 起宽限计时。每个 `onXxx` 只在落地那一次返回信号，否则返回 `null`。
///
/// Example / 示例:
/// ```dart
/// final gate = MovaFirstFrameGate()..arm(autoPlay: true);
/// gate.onBuffering(true, nativeLive: false);           // null
/// gate.onBuffering(false, nativeLive: false);          // MovaFirstFrameSignal.buffering
/// ```
class MovaFirstFrameGate {
  bool _armed = false;
  bool _landed = false;
  bool _awaitingGrace = false;
  bool _autoPlay = true;
  bool _resume = false;
  bool _sawBuffering = false;
  Duration? _prevPosition;

  /// Whether an attempt is armed (landed or not).
  ///
  /// 是否已武装一次尝试（无论是否已落地）。
  bool get armed => _armed;

  /// Whether the current attempt has landed.
  ///
  /// 当前尝试是否已落地。
  bool get landed => _landed;

  /// True once a fallback fired while the native signal was live and the
  /// attempt is still waiting for a restart — the owner should start a
  /// grace timer and call [onGraceExpired] when it fires.
  ///
  /// 原生信号在工作时兜底信号先到、当前尝试仍在等 RESTART 时为 true——持有者应
  /// 起一个宽限计时器，到点调用 [onGraceExpired]。
  bool get awaitingGrace => _awaitingGrace;

  /// Arms a fresh attempt; [autoPlay] false enables the size fallback.
  /// [resume] true arms a standby-resume attempt instead: only a native
  /// restart or a non-zero size lands it, immediately (no grace, regardless
  /// of [autoPlay]); buffering and position are ignored because playback kept
  /// moving during standby.
  ///
  /// 武装一次新尝试；[autoPlay] 为 false 时启用尺寸兜底。[resume] 为 true 时改为武装一次
  /// 待机恢复尝试：只有原生 RESTART 或非零尺寸能让它落地，且立即落地（不进宽限、不看
  /// [autoPlay]）；缓冲与位置一律忽略，因为待机期间播放一直在走。
  void arm({required bool autoPlay, bool resume = false}) {
    reset();
    _armed = true;
    _autoPlay = autoPlay;
    _resume = resume;
  }

  /// Feeds a native restart; always authoritative.
  ///
  /// 输入一次原生 RESTART；任何时候都权威。
  MovaFirstFrameSignal? onRestart() => _land(MovaFirstFrameSignal.restart);

  /// Feeds a buffering flag; lands only on a true→false edge.
  ///
  /// 输入一次缓冲标志；只在 true→false 下降沿落地。
  MovaFirstFrameSignal? onBuffering(bool buffering, {required bool nativeLive}) {
    if (!_open || _resume) return null;
    if (buffering) {
      _sawBuffering = true;
      return null;
    }
    if (!_sawBuffering) return null;
    _sawBuffering = false;
    return _fallback(MovaFirstFrameSignal.buffering, nativeLive);
  }

  /// Feeds a position; lands on the second consecutive increase above zero.
  ///
  /// 输入一次位置；在连续第二次递增且大于 0 时落地。
  MovaFirstFrameSignal? onProgress(Duration position, {required bool nativeLive}) {
    if (!_open || _resume) return null;
    if (position <= Duration.zero) {
      _prevPosition = null;
      return null;
    }
    final prev = _prevPosition;
    _prevPosition = position;
    if (prev == null || position <= prev) return null;
    return _fallback(MovaFirstFrameSignal.progress, nativeLive);
  }

  /// Feeds a video size; lands only for a paused open on the first non-zero size.
  ///
  /// 输入一次画面尺寸；只在暂停态打开且首个非零尺寸时落地。
  MovaFirstFrameSignal? onSize(int width, int height, {required bool nativeLive}) {
    if (!_open || width <= 0 || height <= 0) return null;
    if (_resume) return _land(MovaFirstFrameSignal.size);
    if (_autoPlay) return null;
    return _fallback(MovaFirstFrameSignal.size, nativeLive);
  }

  /// Lands the attempt via [MovaFirstFrameSignal.grace] if still waiting.
  ///
  /// 若仍在等待，则以 [MovaFirstFrameSignal.grace] 落地。
  MovaFirstFrameSignal? onGraceExpired() => _awaitingGrace ? _land(MovaFirstFrameSignal.grace) : null;

  /// Disarms everything.
  ///
  /// 解除一切武装。
  void reset() {
    _armed = false;
    _landed = false;
    _awaitingGrace = false;
    _autoPlay = true;
    _resume = false;
    _sawBuffering = false;
    _prevPosition = null;
  }

  /// Whether observations can still matter (armed and not yet landed).
  ///
  /// 观测是否仍有意义（已武装且未落地）。
  bool get _open => _armed && !_landed;

  /// Lands for a fallback signal, or defers to the grace window when the native
  /// signal is live.
  ///
  /// 兜底信号落地；原生信号在工作时改为进入宽限等待。
  MovaFirstFrameSignal? _fallback(MovaFirstFrameSignal signal, bool nativeLive) {
    if (nativeLive) {
      _awaitingGrace = true;
      return null;
    }
    return _land(signal);
  }

  /// Marks the attempt landed and returns [signal]; `null` when not open.
  ///
  /// 标记尝试已落地并返回 [signal]；未处于等待态时返回 `null`。
  MovaFirstFrameSignal? _land(MovaFirstFrameSignal signal) {
    if (!_open) return null;
    _landed = true;
    _awaitingGrace = false;
    return signal;
  }
}
