part of 'animated_counter.dart';

// ── controller 绑定 ───────────────────────────────────────────────────────────

/// 把 [AnimatedCounterController] 的命令回调与归属标记绑定到状态机。
extension _CounterControllerBinding<W extends _BaseAnimatedCounter> on _BaseCounterState<W> {
  /// 将命令回调及归属标记绑定到当前 State。
  void _bindController() {
    final c = widget.controller;
    if (c == null) return;
    c.$owner = this;
    c.$pauseCallback = () {
      if (_playback != _CounterPlayback.running) return;
      _playback = _CounterPlayback.paused;
      _pausedT = _currentT;
      _cancelActive();
      widget.onPause?.call();
    };
    c.$resumeCallback  = () {
      if (_playback != _CounterPlayback.paused) return;
      _playback = _CounterPlayback.running;
      final pending = _pendingStart;
      _pendingStart = null;
      if (pending != null) {
        pending();
      } else {
        _launchHandle(fromT: _pausedT);
      }
      _pausedT = 0;
      widget.onResume?.call();
    };
    c.$stopCallback    = () {
      _requestVersion++;
      _playback = _CounterPlayback.idle;
      _cancelActive(dropPending: true);
      _repeating = false;
      _onAnimStatusChange(AnimationStatus.dismissed);
    };
    c.$restartCallback = () {
      final version = ++_requestVersion;
      _cancelActive(dropPending: true);
      _repeating = false;
      if (version != _requestVersion || !mounted) return;
      _launchHandle(fromT: 0);
    };
    c.$repeatCallback  = ({bool reverse = false}) {
      _requestVersion++;
      _cancelActive(dropPending: true);
      _repeating = true;
      _repeatReverse = reverse;
      _launchHandle(fromT: 0);
      widget.onRepeat?.call();
    };
    c.$reverseCallback = () {
      final version = ++_requestVersion;
      _cancelActive(dropPending: true);
      _reversing = !_reversing;
      _swapEndpoints();
      _launchHandle(fromT: 1.0 - _currentT);
      if (!mounted || version != _requestVersion) return;
      _updateCurrentDigitValues();
      _onFrameUpdate();
      widget.onReverse?.call();
    };
    c.$statusGetter = () => _animationStatus;
  }

  /// 仅当控制器仍属于当前 State 时清除命令回调及归属标记。
  void _unbindController(AnimatedCounterController? c) {
    if (c == null || !identical(c.$owner, this)) return;
    c.$owner = null;
    c.$pauseCallback   = null;
    c.$resumeCallback  = null;
    c.$stopCallback    = null;
    c.$restartCallback = null;
    c.$repeatCallback  = null;
    c.$reverseCallback = null;
    c.$statusGetter    = null;
  }
}
