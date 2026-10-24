import 'dart:async';

import 'fail.dart';

/// Arms start-up and stall deadlines for one engine. Owns its timers; the
/// engine feeds it playback observations and receives timeouts.
///
/// Internal (not exported from the barrel).
///
/// 为一个引擎武装起播与卡顿期限。自持计时器；引擎喂播放观测、接收超时回调。
///
/// 内部类（不从 barrel 导出）。
class MovaPlayWatchdog {
  /// Creates a watchdog.
  ///
  /// 创建看门狗。
  ///
  /// - [startTimeout]: start deadline / 起播期限
  /// - [stallTimeout]: stall deadline, `null` = never report stalls / 卡顿期限，`null` 表示不报告卡顿
  /// - [onTimeout]: called once per expired deadline with the kind and the wait / 每个期限到期时回调一次，带类型与等待时长
  MovaPlayWatchdog({
    required this.startTimeout,
    this.stallTimeout,
    required void Function(MovaPlayFailKind kind, Duration waited) onTimeout,
  }) : _onTimeout = onTimeout; // ignore: prefer_initializing_formals

  /// Start deadline.
  ///
  /// 起播期限。
  final Duration startTimeout;

  /// Stall deadline; `null` disables stall reporting.
  ///
  /// 卡顿期限；`null` 关闭卡顿上报。
  final Duration? stallTimeout;

  final void Function(MovaPlayFailKind kind, Duration waited) _onTimeout;

  /// The running start or stall deadline, if any.
  ///
  /// 正在计的起播或卡顿期限（若有）。
  Timer? _timer;

  /// Whether an attempt is currently being watched.
  ///
  /// 当前是否正在监视一次尝试。
  bool _armed = false;

  /// Whether the watched attempt has shown its first frame.
  ///
  /// 被监视的尝试是否已出首帧。
  bool _landed = false;

  /// Latest playing intent.
  ///
  /// 最近的播放意图。
  bool _playing = false;

  /// Latest buffering flag.
  ///
  /// 最近的缓冲标志。
  bool _buffering = false;

  /// New attempt; the start deadline runs only while [playing] intent is true.
  ///
  /// 新的一次尝试；起播期限只在播放意图为真时计时。
  ///
  /// - [playing]: whether playback is intended right now / 当前是否有播放意图
  void armStart({required bool playing}) {
    _cancel();
    _armed = true;
    _landed = false;
    _buffering = false;
    _playing = playing;
    _refresh();
  }

  /// Playing intent changed: pauses/resumes (restarts) the running deadline.
  ///
  /// 播放意图变化：暂停/恢复（从头重计）正在计的期限。
  ///
  /// - [playing]: the new intent / 新的意图
  void onPlaying(bool playing) {
    if (_playing == playing) return;
    _playing = playing;
    if (_armed) _refresh();
  }

  /// The attempt showed its first frame: stop the start deadline, watch stalls.
  ///
  /// 本次尝试出了首帧：停掉起播期限，转入卡顿监视。
  void onLanded() {
    if (!_armed || _landed) return;
    _landed = true;
    _refresh();
  }

  /// Buffering flag while running: true starts the stall deadline, false clears it.
  ///
  /// 运行中的缓冲标志：true 起卡顿期限，false 清除。
  ///
  /// - [buffering]: the latest flag / 最新标志
  void onBuffering(bool buffering) {
    if (_buffering == buffering) return;
    _buffering = buffering;
    if (_armed && _landed) _refresh();
  }

  /// Stops all deadlines until the next [armStart].
  ///
  /// 停掉所有期限，直到下一次 [armStart]。
  void disarm() {
    _cancel();
    _armed = false;
  }

  /// Releases the timer; the watchdog must not be used afterwards.
  ///
  /// 释放计时器；之后不可再使用。
  void dispose() => disarm();

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// Restarts the one deadline that applies to the current state, or none.
  ///
  /// 重启当前状态下适用的那个期限，没有适用的就不起。
  void _refresh() {
    _cancel();
    if (!_armed || !_playing) return;
    if (!_landed) {
      _timer = Timer(startTimeout, () => _fire(MovaPlayFailKind.startTimeout, startTimeout));
      return;
    }
    final stall = stallTimeout;
    if (stall != null && _buffering) {
      _timer = Timer(stall, () => _fire(MovaPlayFailKind.stallTimeout, stall));
    }
  }

  void _fire(MovaPlayFailKind kind, Duration waited) {
    _timer = null;
    _onTimeout(kind, waited);
  }
}
