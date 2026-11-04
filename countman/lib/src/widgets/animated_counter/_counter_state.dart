part of 'animated_counter.dart';

// ── shared state base ─────────────────────────────────────────────────────────

/// 动画生命周期；只有暂停态允许恢复。
enum _CounterPlayback { idle, running, paused, completed }

/// 把内部播放状态映射为对外的 [CountmanRunState]。
CountmanRunState _runStateOf(_CounterPlayback playback) => switch (playback) {
      _CounterPlayback.idle => CountmanRunState.idle,
      _CounterPlayback.running => CountmanRunState.running,
      _CounterPlayback.paused => CountmanRunState.paused,
      _CounterPlayback.completed => CountmanRunState.completed,
    };

/// 两条渲染路径共用的可中断动画状态机。
abstract class _BaseCounterState<W extends _BaseAnimatedCounter> extends State<W>
    with _CounterScope<W>, _CounterMeasure<W>, _CounterTint<W> {
  // ── ticker ────────────────────────────────────────────────────────────────
  /// 主滚动任务句柄；完成、取消或尚未启动时可能已结束或为空。
  CounterHandle? _handle;

  /// 落位回弹任务句柄，与主滚动并发运行，独立于 [_handle]。
  CounterHandle? _bounceHandle;

  // Per-column post-animation bounce nudge, each a fraction of digit height
  // (empty / 0 = none). Per-column so it can be phase-shifted by the same
  // stagger delay as the roll — each place bounces as it lands. Positive
  // magnitude; the render applies the motion-direction sign.
  //
  // 逐列的动画后回弹轻推，各为数位高度的比例（空 / 0 = 无）。逐列是为了能按与滚动
  // 相同的 stagger 延迟做相位偏移——每一位在落定时各自回弹。为正幅值；渲染按运动
  // 方向取符号。
  List<double> _bounceOffsets = const <double>[];
  /// 当前转换版本；用户回调重入后旧转换必须退出。
  int _requestVersion = 0;
  /// 显式播放状态的存储；读写请用 [_playback]。
  _CounterPlayback _playbackValue = _CounterPlayback.idle;

  /// 显式播放状态，避免完成后 resume 重播旧任务。
  _CounterPlayback get _playback => _playbackValue;

  /// 写入播放状态，并同步到绑定的控制器的 runState（相同状态不重复通知）。
  set _playback(_CounterPlayback value) {
    _playbackValue = value;
    widget.controller?.setRunState(_runStateOf(value));
  }

  /// 对外状态；暂停时保留最近一次播放方向。
  AnimationStatus _animationStatus = AnimationStatus.dismissed;
  /// reverse 命令的方向，与数值增减方向独立。
  bool _reversing = false;
  /// 当前转换的数值起点，供 fast 路径计算可中断位置。
  num _fromValue = 0;
  /// 当前屏幕值；从实际个位进度还原原始数值，保留紧凑格式的数量级。
  num get _displayedValue {
    final progress = _engine.displayProgress(_currentT);
    if (progress == null) return _fromValue;
    return _fromValue + (_lastValue - _fromValue) * progress;
  }
  /// 当前过渡的线性进度 0–1。
  double _currentT = 0.0;

  /// 暂停时记下的进度，resume 时从这里继续。
  double _pausedT  = 0.0;

  /// 是否处于 repeat 循环中；每轮结束后自动重启。
  bool _repeating  = false;

  // repeat 时每轮结束后是否交换端点往返播放。
  bool _repeatReverse = false;
  // 尚未真正开始的启动动作（startDelay 或批量队列中）；pause 时保留，resume 时执行。
  VoidCallback? _pendingStart;

  // ── digit state ───────────────────────────────────────────────────────────
  /// startDelay 的等待定时器；到期后启动主滚动。
  Timer? _startDelayTimer;

  /// 当前过渡的目标值（已钳制）。
  num   _lastValue    = 0;

  /// 当前显示所依据的数值：静止时为屏幕值，动画开始后为目标值。
  @override
  num   _currentValue = 0;


  /// 数位滚动引擎：持有各列端点与当前位置，进度到位置的换算都在其中。
  /// 快速模式（widget._timeFast）下 currentDigits[i] 携带 0–1 进度。
  final _engine = DigitRollEngine();
  /// 当前过渡是否为递减（reverse 命令会翻转它）；决定滚动方向与递减专用时长/曲线。
  bool _isAnimatingDecrease = false;

  // Total numeric distance |new − old| of the current transition. Drives
  // autoEase (big value jumps ease automatically) independent of the per-digit
  // wrapped trajectory.
  //
  // 本次过渡的数值总跨度 |新 − 旧|。驱动 autoEase（大数值跳变自动缓动），
  // 与逐位环绕轨迹无关。
  double _valueRange = 0.0;

  // ── subclass hooks ────────────────────────────────────────────────────────

  /// Called each animation frame after [_updateCurrentDigitValues].
  /// Painter path: update painter + markNeedsPaint.
  /// Widget path:  increment rebuild notifier.
  @override
  void _onFrameUpdate();

  /// 动画完成且数位已到达真实端点时通知两条渲染路径。
  void _onAnimationComplete();

  // ── helpers ───────────────────────────────────────────────────────────────

  /// 当前应显示的目标值：控制器优先，其次组件的 value。
  num get _effectiveValue =>
      widget.controller != null ? widget.controller!.value : (widget.value ?? 0);

  // ── lifecycle ─────────────────────────────────────────────────────────────

  /// 初始化两套数位端点，静态 fast 直接处于完成进度。
  @override
  void initState() {
    super.initState();
    _resolveOnce();
    // animate-once 已播过：不播入场，挂载即显示终值。
    final skipEntrance = _oncePart && _onceSkip;
    final entranceStart = skipEntrance ? _effectiveValue : widget.initialValue;
    _currentValue = entranceStart.isFinite
        ? entranceStart.clamp(
            widget.minValue ?? double.negativeInfinity, widget.maxValue ?? double.infinity)
        : 0;
    _fromValue = _currentValue;
    _lastValue    = _currentValue;
    _engine.settle(_getDigitsList(_currentValue), fast: widget._timeFast);
    _currentT = 1.0;
    _bindController();
    widget.controller?.addListener(_handleControllerUpdate);
    if (!skipEntrance && widget.initialValue != _effectiveValue) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _triggerTransitionWithDelay(widget.initialValue, _effectiveValue);
      });
    }
  }

  /// 配置变化时用屏幕位置衔接，同时识别有效上下限变化。
  @override
  void didUpdateWidget(W oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_handleControllerUpdate);
      _unbindController(oldWidget.controller);
      widget.controller?.addListener(_handleControllerUpdate);
      _bindController();
    }
    final oldVal = oldWidget.controller != null ? oldWidget.controller!.value : oldWidget.value;
    final newVal = widget.controller != null ? widget.controller!.value : widget.value;
    final current = _displayedValue;
    final formatChanged = oldWidget._resolvedFormat != widget._resolvedFormat ||
        oldWidget.minValue != widget.minValue || oldWidget.maxValue != widget.maxValue;
    final timelineChanged = oldWidget._resolvedTimeline != widget._resolvedTimeline;
    if (formatChanged || oldWidget._timeFast != widget._timeFast) {
      // 格式或 fast 改变时重新拆位，避免延迟期间沿用旧端点或进度表示。
      _refreshFormatDigits();
    } else if (timelineChanged) {
      // 新时间轴可能带启动延迟，先取消旧调度以免继续按旧进度更新。
      _cancelActive(dropPending: true);
    }
    if (oldVal != newVal || formatChanged || timelineChanged) {
      _triggerTransitionWithDelay(current, newVal ?? 0,
          preserveDigits: !formatChanged && oldWidget._timeFast == widget._timeFast);
    }
  }

  /// 立即按新格式重建当前值数位，保证启动延迟期间两条路径也可安全绘制。
  void _refreshFormatDigits() {
    _cancelActive(dropPending: true);
    _engine.settle(_getDigitsList(_currentValue), fast: widget._timeFast);
  }

  /// 控制器零时长命令即使目标相同也必须执行。
  void _handleControllerUpdate() {
    final newValue = widget.controller?.value ?? 0;
    if (newValue != _lastValue || widget.controller!.overrideDuration == Duration.zero) {
      if (widget.controller!.overrideDuration == Duration.zero) widget.onReset?.call();
      _triggerTransitionWithDelay(_displayedValue, newValue);
    }
  }

  // ── transition triggering ─────────────────────────────────────────────────

  /// 先准备端点，再延迟启动；restart 在等待期间也能使用新目标。
  /// [preserveDigits] 为 false 表示格式已变，应按新格式重新拆位。
  void _triggerTransitionWithDelay(num oldValue, num newValue, {bool preserveDigits = true}) {
    final startDigits = preserveDigits && !_engine.digitsAreFast && !widget._timeFast
        ? List<double>.of(_engine.currentDigits) : null;
    _requestVersion++;
    _startAnimationTransition(oldValue, newValue, startDigits: startDigits);
  }

  /// 取消本组件所有进行中或待启动的调度（延迟定时器、批量队列、主动画、回弹）。
  /// [dropPending] 为 true 时同时丢弃待启动动作，否则保留给 resume。
  void _cancelActive({bool dropPending = false}) {
    _startDelayTimer?.cancel();
    _startDelayTimer = null;
    StartScheduler.instance.cancel(this);
    _handle?.cancel();
    _bounceHandle?.cancel();
    _bounceHandle = null;
    if (_bounceOffsets.isNotEmpty) {
      _bounceOffsets = const <double>[];
      if (mounted) _onFrameUpdate();
    }
    if (dropPending) _pendingStart = null;
  }

  /// 交换动画起止端点（普通与 fast 两套数位一并交换）并翻转方向。
  void _swapEndpoints() {
    final from = _fromValue;
    _fromValue = _lastValue;
    _lastValue = from;
    _currentValue = _lastValue;
    _engine.swapEndpoints();
    _isAnimatingDecrease = !_isAnimatingDecrease;
  }

  /// 原子准备新转换，回调重入时由版本号阻止旧请求覆盖端点。
  /// [startDigits] 保留中断时各列的分数进度，避免先舍入再拆位产生小幅回跳。
  void _startAnimationTransition(num oldValue, num newValue, {List<double>? startDigits}) {
    final version = _requestVersion;
    // 新转换先取消旧主动画、回弹与排队启动，避免旧任务覆盖新端点。
    _cancelActive(dropPending: true);
    _repeating = false;
    if (!oldValue.isFinite) oldValue = 0;
    if (!newValue.isFinite) newValue = 0;
    oldValue = oldValue.clamp(widget.minValue ?? double.negativeInfinity, widget.maxValue ?? double.infinity);
    newValue = newValue.clamp(widget.minValue ?? double.negativeInfinity, widget.maxValue ?? double.infinity);
    _isAnimatingDecrease = newValue < oldValue;
    _reversing = false;
    _fromValue = oldValue;
    _currentT = 0;
    _playback = _CounterPlayback.running;

    // 引擎只增不减列数，使值变小时（如 1000 → 7）SizedBox 与对齐保持稳定。
    _engine.begin(
      from: startDigits ?? _getDigitsList(oldValue),
      to: _getDigitsList(newValue),
      fast: widget._timeFast,
      unchanged: oldValue == newValue,
    );

    // Total numeric span — drives autoEase (big jumps ease automatically).
    //
    // 数值总跨度——驱动 autoEase（大跳变自动缓动）。
    _valueRange = (newValue - oldValue).abs().toDouble();

    // ── Normal (non-fast) mode: cumulative per-place cascade ──────────────────
    // Keep the cumulative trajectory: the units column carries the WHOLE number
    // and each higher place is value / 10^place. Lower places therefore spin
    // faster than higher ones — the mechanical-odometer cascade — so a target
    // like 99 rolls 00→01→…→99, NOT every column stepping in lockstep
    // 00→11→…→99. Direction (increase → up, decrease → down) and the
    // end-of-roll ghost are handled entirely in the render layer
    // (CounterPainter.resolveColumnPhase / DigitColumn): it reads the target
    // digit and snaps each place onto it. No all-nines ε-adjust is needed, so
    // animate straight to the real target.
    //
    // 普通（非 fast）模式：累计逐位级联。保留累计轨迹：个位列携带整个数字，每个更高位
    // 为 值 / 10^位。低位因此比高位滚得快——机械里程表式级联——故如 99 这样的目标会
    // 滚 00→01→…→99，而非每列锁步 00→11→…→99。方向（递增→向上，递减→向下）与
    // 滚动末尾的幻影完全在渲染层处理（CounterPainter.resolveColumnPhase / DigitColumn）：
    // 读取目标数位并把每一位精确吸附到目标。无需 all-nines 的 ε 修正，直接动画到真实目标。
    final isIncrease  = newValue > oldValue;
    final isDecrease  = newValue < oldValue;
    final targetColor = isIncrease ? widget.increasingColor
                      : isDecrease ? widget.decreasingColor : null;
    if (targetColor != null) _startTint(targetColor);
    _lastValue    = newValue;
    _currentValue = newValue;

    if (mounted) setState(() {});

    final totalDuration = _effectiveDuration;
    if (totalDuration == Duration.zero) {
      widget.onAnimationStart?.call();
      if (!mounted || version != _requestVersion) return;
      _currentT = 1.0;
      _updateCurrentDigitValues();
      _playback = _CounterPlayback.completed;
      _onAnimationComplete();
      _onAnimStatusChange(AnimationStatus.completed);
    } else {
      void launch() {
        _pendingStart = null;
        if (mounted && version == _requestVersion) _launchHandle(fromT: 0);
      }
      _pendingStart = launch;
      final delay = widget._timeStartDelay;
      if (delay != null && delay > Duration.zero) {
        _startDelayTimer = Timer(Duration(microseconds:
            (delay.inMicroseconds / widget._timeSpeedMultiplier).round()), launch);
      } else {
        StartScheduler.instance.enqueue(launch, tag: this);
      }
    }
  }

  /// 从指定进度恢复当前端点，并发出实际播放方向事件。
  void _launchHandle({double fromT = 0}) {
    _playback = _CounterPlayback.running;
    final version = _requestVersion;
    _bounceHandle?.cancel();
    _bounceHandle = null;
    _handle?.cancel();
    _currentT = fromT;
    final totalDuration = _effectiveDuration;
    final remaining = Duration(microseconds:
        ((1.0 - fromT) * totalDuration.inMicroseconds).round());
    if (remaining <= Duration.zero) {
      _currentT = 1;
      _updateCurrentDigitValues();
      _playback = _CounterPlayback.completed;
      _onAnimationComplete();
      _onAnimStatusChange(_reversing ? AnimationStatus.dismissed : AnimationStatus.completed);
      return;
    }

    if (fromT == 0) {
      widget.onAnimationStart?.call();
      if (!mounted || version != _requestVersion) return;
    }
    _onAnimStatusChange(_reversing ? AnimationStatus.reverse : AnimationStatus.forward);
    if (!mounted || version != _requestVersion) return;
    _handle = _counterPlugin.add(CounterOptions(
      from: fromT,
      to:   1.0,
      duration: remaining,
      curve: Curves.linear,
      onUpdate: (t) {
        _currentT = t;
        _updateCurrentDigitValues();
        _onFrameUpdate();
      },
      onComplete: (_) {
        if (!mounted || version != _requestVersion) return;
        _currentT = 1.0;
        _playback = _CounterPlayback.completed;
        _onAnimationComplete();
        _onAnimStatusChange(_reversing ? AnimationStatus.dismissed : AnimationStatus.completed);
        if (!mounted || version != _requestVersion) return;
        if (_repeating) {
          if (_repeatReverse) _swapEndpoints();
          _launchHandle(fromT: 0);
        }
      },
    ));

    // Bounce runs CONCURRENTLY with the roll (started here, not in onComplete),
    // so each column bounces the instant IT finishes rolling rather than after
    // the whole staggered roll completes. Only on a fresh start (fromT == 0).
    //
    // 回弹与滚动并发（在此启动，而非 onComplete），使每列在自己滚动结束的瞬间就回弹，
    // 而非等整个错峰滚动完成。仅在全新开始（fromT == 0）时启动。
    if (fromT == 0.0 && widget._timeBounceOvershoot > 0.0) _startBounceWave();
  }

  /// 状态先落地再通知；回到反向起点发 dismissed，暂停不改变方向。
  void _onAnimStatusChange(AnimationStatus status) {
    final version = _requestVersion;
    _animationStatus = status;
    widget.controller?.$notifyStatusListeners(status);
    if (!mounted || version != _requestVersion) return;
    if (status == AnimationStatus.completed ||
        (status == AnimationStatus.dismissed && _playback == _CounterPlayback.completed)) {
      widget.onAnimationEnd?.call();
    }
  }

  // ── concurrent bounce wave ─────────────────────────────────────────────────

  /// 启动逐列回弹，与滚动并发，跨 `滚动 + 回弹` 时间轴，使每列在自己滚动结束的瞬间
  /// 回弹（而非等整个错峰滚动完成）。每次回弹是对已定位数位的纯位置轻推——值仍钉在
  /// 目标（进度 0），故不显示相邻数位，目标数位为 0 时同样有效。时间轴计算见
  /// [DigitBounce]；[_bounceOffsets]（每列 0 → maxFrac → 0）由 painter / DigitColumn
  /// 当作数位高度的比例消费。
  void _startBounceWave() {
    if (!mounted || widget._timeBounceOvershoot <= 0.0) return;

    // _effectiveStaggerDelay 已按倍速缩放，此处不再重复缩放。
    final Duration? stagger = _effectiveStaggerDelay;
    final bounce = DigitBounce(
      overshoot: widget._timeBounceOvershoot,
      staggerUs: stagger == null ? 0.0 : stagger.inMicroseconds.toDouble(),
      baseDurationUs: _baseDurationUs,
      direction: widget._timeStaggerDirection,
      digitCount: _engine.maxDigits,
    );
    final double totalUs = bounce.totalUs;
    if (totalUs <= 0) return;

    _bounceOffsets = List<double>.filled(_engine.maxDigits, 0.0);

    _bounceHandle?.cancel();
    _bounceHandle = _counterPlugin.add(CounterOptions(
      from: 0.0,
      to: 1.0,
      duration: Duration(microseconds: totalUs.round()),
      curve: Curves.linear,
      allowNegative: false,
      onUpdate: (t) {
        if (!mounted) return;
        bounce.fill(_bounceOffsets, t);
        _onFrameUpdate();
      },
      onComplete: (_) {
        if (!mounted) return;
        _bounceOffsets = const <double>[];
        _onFrameUpdate();
        _bounceHandle = null;
      },
    ));
  }

  // ── digit computation ─────────────────────────────────────────────────────

  /// 按当前进度把各列位置写入引擎；换算细节见 [DigitRollEngine.compute]。
  void _updateCurrentDigitValues() {
    final Duration? stagger = _effectiveStaggerDelay;
    _engine.compute(
      t: _currentT,
      curve: _effectiveCurve,
      baseDurationUs: _baseDurationUs,
      totalDurationUs: _effectiveDuration.inMicroseconds.toDouble(),
      // 已按倍速缩放。
      staggerUs: (stagger != null && stagger > Duration.zero)
          ? stagger.inMicroseconds.toDouble()
          : 0.0,
      direction: widget._timeStaggerDirection,
      valueRange: _valueRange,
      autoEaseThreshold: widget._timeAutoEaseThreshold,
      fast: widget._timeFast,
      curveForDigit: widget._timeCurveForDigit,
      interpolation: widget._timeInterpolation,
    );
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_handleControllerUpdate);
    _unbindController(widget.controller);
    _startDelayTimer?.cancel();
    _pendingStart = null;
    StartScheduler.instance.cancel(this);
    _bounceHandle?.cancel();
    _handle?.cancel();
    super.dispose();
  }
}
