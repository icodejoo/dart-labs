part of 'animated_counter.dart';

// ── shared widget base ────────────────────────────────────────────────────────

abstract class _BaseAnimatedCounter extends StatefulWidget {
  /// Aggregate visual style. Overrides the deprecated loose visual params
  /// field-by-field (see the resolving getters below).
  ///
  /// 聚合视觉样式。逐字段覆盖弃用的松散视觉参数（见下方解析 getter）。
  final AnimatedCounterStyle? style;

  final num? value;
  final AnimatedCounterController? controller;
  final Duration duration;
  final Duration negativeSignDuration;
  final Curve curve;
  final TextStyle? _textStyle;
  final String? prefix;
  final String? infix;
  final String? suffix;
  final TextStyle? _prefixStyle;
  final TextStyle? _infixStyle;
  final TextStyle? _suffixStyle;
  final TextOverflow? prefixOverflow;
  final TextOverflow? infixOverflow;
  final TextOverflow? suffixOverflow;
  final int fractionDigits;
  final int wholeDigits;
  final bool hideLeadingZeroes;
  final double _numberAlignment;
  final String? thousandSeparator;
  final List<int> groupingPattern;
  final String decimalSeparator;
  final TextStyle? _separatorStyle;
  final MainAxisAlignment _mainAxisAlignment;
  final CrossAxisAlignment _crossAxisAlignment;
  final EdgeInsets _padding;
  final bool _useTabularFigures;
  final bool showPositiveSign;
  final Duration? positiveSignDuration;
  final String? semanticsLabel;
  final VoidCallback? onAnimationEnd;
  final VoidCallback? onAnimationStart;
  final AxisDirection flipDirection;
  final num? minValue;
  final num? maxValue;
  final Color? _increasingColor;
  final Color? _decreasingColor;
  final Duration _colorFadeDuration;
  final Widget? prefixWidget;
  final Widget? infixWidget;
  final Widget? suffixWidget;
  final Widget? thousandSeparatorWidget;
  final Widget? decimalSeparatorWidget;
  final Widget? negativeSignWidget;
  final Widget? positiveSignWidget;
  final Duration? staggerDelay;
  final StaggerDirection staggerDirection;
  final bool compactNotation;
  final bool triggerHaptics;
  final int? compactFractionDigits;
  final num initialValue;
  final NumeralSystem numeralSystem;
  final String Function(int digit)? numeralMapper;
  final CounterTransition transition;
  final Duration? reverseDuration;
  final Curve? reverseCurve;
  final Duration? startDelay;
  final double speedMultiplier;
  final Map<num, String>? compactAbbreviations;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onReset;
  final VoidCallback? onRepeat;
  final VoidCallback? onReverse;
  final bool repaintBoundary;
  final double autoEaseThreshold;
  final Curve? Function(int digitIndex)? curveForDigit;
  final Color? Function(num value)? colorResolver;
  final double Function(double from, double to, double t)? interpolation;
  final double bounceOvershoot;
  final double bounceElasticity;

  /// Fast mode: every digit column does a SINGLE step from its old digit to
  /// its new digit (one slot of movement), regardless of numeric distance —
  /// e.g. 1000 → 9999 slides each column once (1→9, 0→9, …) instead of the
  /// full cascading odometer roll. Applies to every [transition].
  ///
  /// 快速模式：每个数字列都从旧位到新位单步位移（一个身位），无关数值距离——
  /// 如 1000 → 9999 每列只滑一次（1→9、0→9…），而非完整级联滚动。对所有
  /// [transition] 生效。
  final bool fast;

  // ── resolved visual getters: [style] wins, else the deprecated raw param ──
  // 已解析视觉 getter：[style] 优先，否则用弃用的原始参数。
  TextStyle? get textStyle => style?.textStyle ?? _textStyle;
  TextStyle? get prefixStyle => style?.prefixStyle ?? _prefixStyle;
  TextStyle? get infixStyle => style?.infixStyle ?? _infixStyle;
  TextStyle? get suffixStyle => style?.suffixStyle ?? _suffixStyle;
  TextStyle? get separatorStyle => style?.separatorStyle ?? _separatorStyle;

  /// Horizontal alignment of visible digits within the stable full-width slot.
  /// -1.0 = left, 0.0 = center (default), 1.0 = right.
  double get numberAlignment => style?.numberAlignment ?? _numberAlignment;
  MainAxisAlignment get mainAxisAlignment => style?.mainAxisAlignment ?? _mainAxisAlignment;
  CrossAxisAlignment get crossAxisAlignment => style?.crossAxisAlignment ?? _crossAxisAlignment;
  EdgeInsets get padding => style?.padding ?? _padding;
  bool get useTabularFigures => style?.useTabularFigures ?? _useTabularFigures;
  Color? get increasingColor => style?.increasingColor ?? _increasingColor;
  Color? get decreasingColor => style?.decreasingColor ?? _decreasingColor;
  Duration get colorFadeDuration => style?.colorFadeDuration ?? _colorFadeDuration;

  /// Container decoration drawn around the whole counter (style-only).
  ///
  /// 绘制在整个计数器外围的容器装饰（仅样式）。
  Decoration? get decoration => style?.decoration;

  const _BaseAnimatedCounter({
    super.key,
    this.style,
    this.value,
    this.controller,
    this.duration = const Duration(milliseconds: 300),
    this.negativeSignDuration = const Duration(milliseconds: 150),
    this.curve = Curves.linear,
    @Deprecated('Use style: AnimatedCounterStyle(textStyle: ...)') TextStyle? textStyle,
    this.prefix,
    this.infix,
    this.suffix,
    this.fractionDigits = 0,
    this.wholeDigits = 1,
    this.hideLeadingZeroes = true,
    @Deprecated('Use style: AnimatedCounterStyle(numberAlignment: ...)') double numberAlignment = 0.0,
    this.thousandSeparator,
    this.groupingPattern = const [3],
    this.decimalSeparator = '.',
    @Deprecated('Use style: AnimatedCounterStyle(separatorStyle: ...)') TextStyle? separatorStyle,
    @Deprecated('Use style: AnimatedCounterStyle(mainAxisAlignment: ...)') MainAxisAlignment mainAxisAlignment = MainAxisAlignment.center,
    @Deprecated('Use style: AnimatedCounterStyle(crossAxisAlignment: ...)') CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.center,
    @Deprecated('Use style: AnimatedCounterStyle(padding: ...)') EdgeInsets padding = EdgeInsets.zero,
    @Deprecated('Use style: AnimatedCounterStyle(useTabularFigures: ...)') bool useTabularFigures = true,
    @Deprecated('Use style: AnimatedCounterStyle(prefixStyle: ...)') TextStyle? prefixStyle,
    @Deprecated('Use style: AnimatedCounterStyle(infixStyle: ...)') TextStyle? infixStyle,
    @Deprecated('Use style: AnimatedCounterStyle(suffixStyle: ...)') TextStyle? suffixStyle,
    this.prefixOverflow,
    this.infixOverflow,
    this.suffixOverflow,
    this.showPositiveSign = false,
    this.positiveSignDuration,
    this.semanticsLabel,
    this.onAnimationEnd,
    this.onAnimationStart,
    this.flipDirection = AxisDirection.up,
    this.minValue,
    this.maxValue,
    @Deprecated('Use style: AnimatedCounterStyle(increasingColor: ...)') Color? increasingColor,
    @Deprecated('Use style: AnimatedCounterStyle(decreasingColor: ...)') Color? decreasingColor,
    @Deprecated('Use style: AnimatedCounterStyle(colorFadeDuration: ...)') Duration colorFadeDuration = const Duration(milliseconds: 800),
    this.prefixWidget,
    this.infixWidget,
    this.suffixWidget,
    this.thousandSeparatorWidget,
    this.decimalSeparatorWidget,
    this.negativeSignWidget,
    this.positiveSignWidget,
    this.staggerDelay,
    this.staggerDirection = StaggerDirection.rightToLeft,
    this.compactNotation = false,
    this.triggerHaptics = false,
    this.compactFractionDigits,
    this.initialValue = 0,
    this.numeralSystem = NumeralSystem.latin,
    this.numeralMapper,
    this.transition = CounterTransition.slide,
    this.reverseDuration,
    this.reverseCurve,
    this.startDelay,
    this.speedMultiplier = 1.0,
    this.compactAbbreviations,
    this.onPause,
    this.onResume,
    this.onReset,
    this.onRepeat,
    this.onReverse,
    this.repaintBoundary = true,
    this.autoEaseThreshold = 100000,
    this.curveForDigit,
    this.colorResolver,
    this.interpolation,
    this.bounceOvershoot = 0.0,
    this.bounceElasticity = 4.0,
    this.fast = false,
  })  : _textStyle = textStyle,
        _prefixStyle = prefixStyle,
        _infixStyle = infixStyle,
        _suffixStyle = suffixStyle,
        _separatorStyle = separatorStyle,
        _numberAlignment = numberAlignment,
        _mainAxisAlignment = mainAxisAlignment,
        _crossAxisAlignment = crossAxisAlignment,
        _padding = padding,
        _useTabularFigures = useTabularFigures,
        _increasingColor = increasingColor,
        _decreasingColor = decreasingColor,
        _colorFadeDuration = colorFadeDuration,
        assert(value != null || controller != null,
            'Either value or controller must be provided'),
        assert(fractionDigits >= 0),
        assert(wholeDigits >= 0),
        assert(speedMultiplier > 0),
        assert(bounceOvershoot >= 0.0),
        assert(bounceElasticity >= 1.0);
}

// ── shared state base ─────────────────────────────────────────────────────────

abstract class _BaseCounterState<W extends _BaseAnimatedCounter> extends State<W> {
  // ── ticker ────────────────────────────────────────────────────────────────
  CounterHandle? _handle;
  CounterHandle? _bounceHandle; // separate post-animation bounce
  // Per-column post-animation bounce nudge, each a fraction of digit height
  // (empty / 0 = none). Per-column so it can be phase-shifted by the same
  // stagger delay as the roll — each place bounces as it lands. Positive
  // magnitude; the render applies the motion-direction sign.
  //
  // 逐列的动画后回弹轻推，各为数位高度的比例（空 / 0 = 无）。逐列是为了能按与滚动
  // 相同的 stagger 延迟做相位偏移——每一位在落定时各自回弹。为正幅值；渲染按运动
  // 方向取符号。
  List<double> _bounceOffsets = const <double>[];
  double _currentT = 0.0;
  double _pausedT  = 0.0;
  bool _repeating  = false;

  bool _usingAdjustedTarget    = false;
  List<double> _realTargetDigitValues = [];

  // ── digit state ───────────────────────────────────────────────────────────
  Timer? _startDelayTimer;
  Color? _directionColor;
  int   _colorAnimKey = 0;
  num   _lastValue    = 0;
  num   _currentValue = 0;

  List<double> _oldDigitValues     = [];
  List<double> _targetDigitValues  = [];
  List<double> _currentDigitValues = [];
  // Fast mode (widget.fast): per-column old/new digit (0–9), computed once per
  // transition. In fast mode _currentDigitValues[i] carries the 0–1 progress.
  //
  // 快速模式（widget.fast）：每列旧/新位（0–9），每次过渡算一次。此模式下
  // _currentDigitValues[i] 携带 0–1 进度。
  List<int> _fastFromDigits = [];
  List<int> _fastToDigits   = [];
  int  _maxDigits          = 0;
  bool _isAnimatingDecrease = false;
  // Total numeric distance |new − old| of the current transition. Drives
  // autoEase (big value jumps ease automatically) independent of the per-digit
  // wrapped trajectory.
  //
  // 本次过渡的数值总跨度 |新 − 旧|。驱动 autoEase（大数值跳变自动缓动），
  // 与逐位环绕轨迹无关。
  double _valueRange = 0.0;

  Size?       _prototypeSize;
  TextStyle?  _lastStyle;
  TextScaler? _lastTextScaler;
  // Signature of the 0–9 glyphs last measured. Recompute the prototype cell
  // when it changes (e.g. numeralMapper / numeralSystem swapped) so the cell
  // keeps fitting the actual glyphs.
  //
  // 上次测量的 0–9 字形签名。当其变化时（例如切换 numeralMapper /
  // numeralSystem）重新计算原型单元格，使单元格始终适配真实字形。
  String?     _lastGlyphSig;

  // ── subclass hooks ────────────────────────────────────────────────────────

  /// Called each animation frame after [_updateCurrentDigitValues].
  /// Painter path: update painter + markNeedsPaint.
  /// Widget path:  increment rebuild notifier.
  void _onFrameUpdate();

  /// Called when animation completes, after all-nines snapping.
  void _onAnimationComplete();

  // ── helpers ───────────────────────────────────────────────────────────────

  num get _effectiveValue =>
      widget.controller != null ? widget.controller!.value : (widget.value ?? 0);

  Duration get _effectiveDuration {
    final base = (widget.controller != null && widget.controller!.overrideDuration != null)
        ? widget.controller!.overrideDuration!
        : ((_isAnimatingDecrease && widget.reverseDuration != null)
            ? widget.reverseDuration!
            : widget.duration);
    Duration d = base;
    final stagger = _effectiveStaggerDelay;
    if (stagger != null && stagger > Duration.zero) {
      d += stagger * (_maxDigits - 1);
    }
    return widget.speedMultiplier == 1.0
        ? d
        : Duration(microseconds: (d.inMicroseconds / widget.speedMultiplier).round());
  }

  Curve get _effectiveCurve {
    if (_isAnimatingDecrease && widget.reverseCurve != null) return widget.reverseCurve!;
    return widget.curve;
  }

  AxisDirection get _effectiveFlipDirection {
    if (!_isAnimatingDecrease) return widget.flipDirection;
    return switch (widget.flipDirection) {
      AxisDirection.up    => AxisDirection.down,
      AxisDirection.down  => AxisDirection.up,
      AxisDirection.left  => AxisDirection.right,
      AxisDirection.right => AxisDirection.left,
    };
  }

  Duration? get _effectiveStaggerDelay {
    if (widget.staggerDelay == null) return null;
    return widget.speedMultiplier == 1.0
        ? widget.staggerDelay
        : Duration(microseconds: (widget.staggerDelay!.inMicroseconds / widget.speedMultiplier).round());
  }

  Duration get _effectiveNegativeSignDuration => widget.speedMultiplier == 1.0
      ? widget.negativeSignDuration
      : Duration(microseconds: (widget.negativeSignDuration.inMicroseconds / widget.speedMultiplier).round());

  Duration get _effectivePositiveSignDuration {
    final base = widget.positiveSignDuration ?? widget.negativeSignDuration;
    return widget.speedMultiplier == 1.0
        ? base
        : Duration(microseconds: (base.inMicroseconds / widget.speedMultiplier).round());
  }

  // ── lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _currentValue = widget.initialValue;
    _lastValue    = _currentValue;
    final initialDigits = _getDigitsList(_currentValue);
    _maxDigits          = initialDigits.length;
    _oldDigitValues     = List<double>.from(initialDigits);
    _targetDigitValues  = List<double>.from(initialDigits);
    _currentDigitValues = List<double>.from(initialDigits);
    _bindController();
    widget.controller?.addListener(_handleControllerUpdate);
    if (widget.initialValue != _effectiveValue) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _triggerTransitionWithDelay(widget.initialValue, _effectiveValue);
      });
    }
  }

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
    if (oldVal != newVal) _triggerTransitionWithDelay(oldVal ?? 0, newVal ?? 0);
  }

  void _handleControllerUpdate() {
    final newValue = widget.controller?.value ?? 0;
    if (newValue != _lastValue) {
      if (widget.controller!.overrideDuration == Duration.zero) widget.onReset?.call();
      _triggerTransitionWithDelay(_lastValue, newValue);
    }
  }

  // ── controller binding ────────────────────────────────────────────────────

  void _bindController() {
    final c = widget.controller;
    if (c == null) return;
    c.$pauseCallback = () {
      _pausedT = _currentT;
      _handle?.cancel();
      widget.onPause?.call();
    };
    c.$resumeCallback  = () { _launchHandle(fromT: _pausedT); widget.onResume?.call(); };
    c.$stopCallback    = () { _handle?.cancel(); };
    c.$restartCallback = () { _launchHandle(fromT: 0); widget.onAnimationStart?.call(); };
    c.$repeatCallback  = ({bool reverse = false}) {
      _repeating = true;
      _launchHandle(fromT: 0);
      widget.onRepeat?.call();
    };
    c.$reverseCallback = () {
      final tmp = List<double>.from(_oldDigitValues);
      _oldDigitValues      = List<double>.from(_targetDigitValues);
      _targetDigitValues   = tmp;
      _isAnimatingDecrease = !_isAnimatingDecrease;
      _launchHandle(fromT: 1.0 - _currentT);
      widget.onReverse?.call();
    };
    c.$statusGetter = () {
      if (_currentT >= 1.0) return AnimationStatus.completed;
      if (_currentT <= 0.0) return AnimationStatus.dismissed;
      return AnimationStatus.forward;
    };
  }

  void _unbindController(AnimatedCounterController? c) {
    if (c == null) return;
    c.$pauseCallback   = null;
    c.$resumeCallback  = null;
    c.$stopCallback    = null;
    c.$restartCallback = null;
    c.$repeatCallback  = null;
    c.$reverseCallback = null;
    c.$statusGetter    = null;
  }

  // ── transition triggering ─────────────────────────────────────────────────

  void _triggerTransitionWithDelay(num oldValue, num newValue) {
    _startDelayTimer?.cancel();
    if (widget.startDelay != null && widget.startDelay! > Duration.zero) {
      final delay = Duration(microseconds:
          (widget.startDelay!.inMicroseconds / widget.speedMultiplier).round());
      _startDelayTimer = Timer(delay, () {
        if (mounted) _startAnimationTransition(oldValue, newValue);
      });
    } else {
      _startAnimationTransition(oldValue, newValue);
    }
  }

  void _startAnimationTransition(num oldValue, num newValue) {
    if (!oldValue.isFinite) oldValue = 0;
    if (!newValue.isFinite) newValue = 0;
    _isAnimatingDecrease = newValue < oldValue;
    widget.onAnimationStart?.call();

    final oldDigits = _getDigitsList(oldValue);
    var animTarget  = newValue;

    final effFD = _effectiveFractionDigits();
    // The all-nines ε-adjust only matters in fast mode (normal mode overwrites
    // _usingAdjustedTarget = false below and lands exactly via ghost-prevention).
    // Skip the pow/round/scan entirely for the common non-fast path.
    //
    // all-nines 的 ε 修正只在 fast 模式有意义（普通模式下方会把 _usingAdjustedTarget
    // 置 false，并靠防幻影精确落位）。常见的非 fast 路径直接跳过 pow/round/扫描。
    _usingAdjustedTarget = false;
    if (widget.fast) {
      final scaledNew = (newValue.abs() * math.pow(10, effFD)).round();
      _usingAdjustedTarget = newValue > 0 && scaledNew > 0 && isAllNinesTarget(scaledNew);
      if (_usingAdjustedTarget) {
        animTarget = newValue - 1.0 / math.pow(10, effFD);
      }
    }

    final targetDigits = _getDigitsList(animTarget);
    _realTargetDigitValues = List<double>.from(_getDigitsList(newValue));
    // Never shrink _maxDigits — keeps SizedBox stable and numberAlignment
    // consistent when animating to a smaller value (e.g. 1000 → 7).
    _maxDigits = math.max(_maxDigits,
        math.max(oldDigits.length,
            math.max(targetDigits.length, _realTargetDigitValues.length)));

    _oldDigitValues    = [...List<double>.filled(_maxDigits - oldDigits.length, 0.0),    ...oldDigits];
    _targetDigitValues = [...List<double>.filled(_maxDigits - targetDigits.length, 0.0), ...targetDigits];
    _currentDigitValues = List<double>.from(_oldDigitValues);

    // Per-column single digits (0–9), old & new. Derived from the cumulative
    // magnitude arrays via %10, then reused by both fast and normal modes.
    // Uses the REAL new value's digits (not the all-nines-adjusted animTarget).
    //
    // 每列的单个数字（0–9），旧与新。由累计幅值数组经 %10 得到，fast 与普通模式共用。
    // 使用真实新值的数位（而非 all-nines 修正后的 animTarget）。
    final realTarget = [
      ...List<double>.filled(
          (_maxDigits - _realTargetDigitValues.length).clamp(0, _maxDigits), 0.0),
      ..._realTargetDigitValues,
    ];
    _fastFromDigits = [for (final v in _oldDigitValues) v.toInt().abs() % 10];
    _fastToDigits   = [for (final v in realTarget) v.toInt().abs() % 10];

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
    // Non-fast mode needs no extra fixup here: `animTarget == newValue`, so the
    // `_targetDigitValues`/`_currentDigitValues` computed above already hold the
    // real-target and old-value arrays, and `_usingAdjustedTarget` stayed false.
    //
    // 非 fast 模式此处无需额外修正：`animTarget == newValue`，故上方算出的
    // `_targetDigitValues`/`_currentDigitValues` 已是真实目标与旧值数组，
    // `_usingAdjustedTarget` 也一直为 false。

    final isIncrease  = newValue > oldValue;
    final isDecrease  = newValue < oldValue;
    final targetColor = isIncrease ? widget.increasingColor
                      : isDecrease ? widget.decreasingColor : null;
    if (targetColor != null) { _directionColor = targetColor; _colorAnimKey++; }
    _lastValue    = newValue;
    _currentValue = newValue;

    if (mounted) setState(() {});

    final totalDuration = _effectiveDuration;
    if (totalDuration == Duration.zero) {
      _currentT = 1.0;
      _updateCurrentDigitValues();
      _onFrameUpdate();
      _onAnimStatusChange(AnimationStatus.completed);
    } else {
      StartScheduler.instance.enqueue(
        () { if (mounted) _launchHandle(fromT: 0); },
        tag: this,
      );
    }
  }

  void _launchHandle({double fromT = 0}) {
    _bounceHandle?.cancel();
    _bounceHandle = null;
    _handle?.cancel();
    _currentT = fromT;
    final totalDuration = _effectiveDuration;
    if (totalDuration == Duration.zero) return;
    final remaining = Duration(microseconds:
        ((1.0 - fromT) * totalDuration.inMicroseconds).round());
    if (remaining <= Duration.zero) return;

    _handle = counter(CounterOptions(
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
        _currentT = 1.0;
        // Snap to real target when using all-nines adjusted value — applies to both paths.
        if (_usingAdjustedTarget && _realTargetDigitValues.isNotEmpty) {
          final n = math.max(_realTargetDigitValues.length, _maxDigits);
          _currentDigitValues = [
            ...List<double>.filled(n - _realTargetDigitValues.length, 0.0),
            ..._realTargetDigitValues,
          ];
        }
        _onAnimationComplete();
        _usingAdjustedTarget = false;
        _onAnimStatusChange(AnimationStatus.completed);
        if (_repeating) { _repeating = false; _launchHandle(fromT: 0); }
      },
    ));

    // Bounce runs CONCURRENTLY with the roll (started here, not in onComplete),
    // so each column bounces the instant IT finishes rolling rather than after
    // the whole staggered roll completes. Only on a fresh start (fromT == 0).
    //
    // 回弹与滚动并发（在此启动，而非 onComplete），使每列在自己滚动结束的瞬间就回弹，
    // 而非等整个错峰滚动完成。仅在全新开始（fromT == 0）时启动。
    if (fromT == 0.0 && widget.bounceOvershoot > 0.0) _startBounceWave();
  }

  void _onAnimStatusChange(AnimationStatus status) {
    widget.controller?.$notifyStatusListeners(status);
    if (status == AnimationStatus.completed) widget.onAnimationEnd?.call();
  }

  // ── concurrent bounce wave ─────────────────────────────────────────────────

  /// Starts the per-column bounce, running CONCURRENTLY with the roll over
  /// `roll + bounce` so each column bounces the instant IT finishes rolling
  /// (not after the whole staggered roll). Each bounce is a pure POSITIONAL
  /// nudge of the already-settled digit — the value stays pinned on target
  /// (progress 0), so NO adjacent digit is revealed (only the target value
  /// shows) and it works even when the target digit is 0. tanh caps the nudge
  /// within one digit height; [_bounceOffsets] (0 → maxFrac → 0 per column) is
  /// consumed by the painter / DigitColumn as a fraction of digit height.
  ///
  /// 启动逐列回弹，与滚动并发，跨 `滚动 + 回弹` 时间轴，使每列在自己滚动结束的瞬间
  /// 回弹（而非等整个错峰滚动完成）。每次回弹是对已定位数位的纯位置轻推——值仍钉在
  /// 目标（进度 0），故不显示相邻数位（只显示目标值），且目标数位为 0 时同样有效。
  /// tanh 把轻推限制在一个数位高度内；[_bounceOffsets]（每列 0 → maxFrac → 0）由
  /// painter / DigitColumn 当作数位高度的比例消费。
  void _startBounceWave() {
    if (!mounted || widget.bounceOvershoot <= 0.0) return;

    final double ex2     = math.exp(2.0 * widget.bounceOvershoot);
    final double maxFrac = (ex2 - 1) / (ex2 + 1);

    const double bounceUs = 350000.0;

    // Per-column roll-end (µs from launch), mirroring _updateCurrentDigitValues:
    // column i finishes rolling at delayUs(i) + baseDurationUs. The bounce for
    // that column then plays over the next [bounceUs].
    //
    // 逐列滚动结束时刻（自启动的 µs），与 _updateCurrentDigitValues 对齐：第 i 列在
    // delayUs(i) + baseDurationUs 结束滚动，其回弹随后在 [bounceUs] 内播放。
    Duration baseDuration = (widget.controller != null && widget.controller!.overrideDuration != null)
        ? widget.controller!.overrideDuration!
        : ((_isAnimatingDecrease && widget.reverseDuration != null)
            ? widget.reverseDuration! : widget.duration);
    if (baseDuration == Duration.zero) baseDuration = const Duration(microseconds: 1);
    final double baseDurationUs = baseDuration.inMicroseconds.toDouble() / widget.speedMultiplier;

    final Duration? stagger = _effectiveStaggerDelay;
    final double staggerUs =
        (stagger == null) ? 0.0 : stagger.inMicroseconds.toDouble() / widget.speedMultiplier;

    double rollEndUs(int i) => _staggerDelayUs(i, staggerUs) + baseDurationUs;

    // Timeline covers the last column's roll-end plus one bounce.
    //
    // 时间轴覆盖最后一列的滚动结束再加一次回弹。
    double lastRollEndUs = 0.0;
    for (int i = 0; i < _maxDigits; i++) {
      final e = rollEndUs(i);
      if (e > lastRollEndUs) lastRollEndUs = e;
    }
    final double totalUs = lastRollEndUs + bounceUs;
    if (totalUs <= 0) return;

    _bounceOffsets = List<double>.filled(_maxDigits, 0.0);

    _bounceHandle?.cancel();
    _bounceHandle = counter(CounterOptions(
      from: 0.0,
      to: 1.0,
      duration: Duration(microseconds: totalUs.round()),
      curve: Curves.linear,
      allowNegative: false,
      onUpdate: (t) {
        if (!mounted) return;
        final double elapsedUs = t * totalUs;
        for (int i = 0; i < _maxDigits; i++) {
          final double localUs = elapsedUs - rollEndUs(i);
          _bounceOffsets[i] = (localUs > 0.0 && localUs < bounceUs)
              ? maxFrac * math.sin(math.pi * localUs / bounceUs)
              : 0.0;
        }
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

  /// Per-column stagger delay (µs from launch) for column [i] given the
  /// [staggerUs] stride. Shared by the roll ([_updateCurrentDigitValues]) and
  /// the bounce wave ([_startBounceWave]) so both stay phase-aligned.
  ///
  /// 给定 [staggerUs] 步长时，第 [i] 列的错峰延迟（自启动的 µs）。由滚动
  /// （[_updateCurrentDigitValues]）与回弹波（[_startBounceWave]）共用，使两者相位对齐。
  double _staggerDelayUs(int i, double staggerUs) => switch (widget.staggerDirection) {
        StaggerDirection.leftToRight => staggerUs * i,
        StaggerDirection.rightToLeft => staggerUs * (_maxDigits - 1 - i),
      };

  // ── digit computation ─────────────────────────────────────────────────────

  void _updateCurrentDigitValues() {
    final double t      = _currentT;
    final Curve  curve  = _effectiveCurve;
    final Duration? stagger = _effectiveStaggerDelay;

    Duration baseDuration = (widget.controller != null && widget.controller!.overrideDuration != null)
        ? widget.controller!.overrideDuration!
        : ((_isAnimatingDecrease && widget.reverseDuration != null)
            ? widget.reverseDuration! : widget.duration);
    if (baseDuration == Duration.zero) baseDuration = const Duration(microseconds: 1);

    final double baseDurationUs  = baseDuration.inMicroseconds.toDouble() / widget.speedMultiplier;
    final double totalDurationUs = _effectiveDuration.inMicroseconds.toDouble();

    // autoEase off the total numeric span, not the per-digit wrapped delta
    // (which is now ≤ 10 and would never cross the threshold).
    //
    // autoEase 依据数值总跨度，而非逐位环绕增量（后者现已 ≤ 10，永远够不到阈值）。
    final bool autoEase = curve == Curves.linear && _valueRange > widget.autoEaseThreshold;
    final Curve effectiveComputeCurve = autoEase ? Curves.easeInOut : curve;

    // Reuse the buffer across frames; reallocate only when the digit count
    // changes (once per transition). Saves one list allocation per frame.
    //
    // 帧间复用缓冲；仅当位数变化时重分配（每次过渡一次）。省去每帧一次列表分配。
    if (_currentDigitValues.length != _maxDigits) {
      _currentDigitValues = List<double>.filled(_maxDigits, 0.0);
    }

    // Stagger stride + elapsed hoisted out of the per-digit loop (were
    // recomputed per digit per frame).
    //
    // stagger 步长与 elapsed 提到逐位循环外（原来每位每帧都算）。
    final double staggerUs = (stagger != null && stagger > Duration.zero)
        ? stagger.inMicroseconds.toDouble() / widget.speedMultiplier
        : 0.0;
    final double elapsedUs = t * totalDurationUs;

    for (int i = 0; i < _maxDigits; i++) {
      double tDigit = t;
      if (staggerUs > 0.0) {
        final double delayUs = _staggerDelayUs(i, staggerUs);
        tDigit = ((elapsedUs - delayUs) / baseDurationUs).clamp(0.0, 1.0);
      }
      final Curve  digitCurve = widget.curveForDigit?.call(i) ?? effectiveComputeCurve;
      final double progress   = digitCurve.transform(tDigit);

      // Fast mode: the column just carries its 0–1 progress; the from→new-digit
      // single step is rendered by the painter / DigitColumn (no cascade here).
      //
      // 快速模式：列只携带 0–1 进度；from→新位 的单步由 painter / DigitColumn 渲染
      // （此处不做级联）。
      if (widget.fast) {
        _currentDigitValues[i] = progress;
        continue;
      }

      final double from       = _oldDigitValues[i];
      final double to         = _targetDigitValues[i];
      double value = widget.interpolation != null
          ? widget.interpolation!(from, to, progress)
          : from + (to - from) * progress;

      // Bounce is applied separately as a per-column positional nudge in
      // _startBounceWave() (concurrent with the roll), not baked into the value.
      //
      // 回弹在 _startBounceWave() 中作为逐列位置轻推单独施加（与滚动并发），不写入数值。
      _currentDigitValues[i] = value;
    }
  }

  List<double> _getDigitsList(num targetValue) {
    if (targetValue is double && !targetValue.isFinite) targetValue = 0;
    final num clamped = targetValue.clamp(
      widget.minValue ?? double.negativeInfinity,
      widget.maxValue ?? double.infinity,
    );
    num displayValue = clamped;

    final Map<num, String> abbreviations = widget.compactAbbreviations ?? {
      1e3: 'K', 1e6: 'M', 1e9: 'B', 1e12: 'T',
    };
    if (widget.compactNotation) {
      final absVal = clamped.abs();
      final sorted = abbreviations.keys.toList()..sort((a, b) => b.compareTo(a));
      for (final threshold in sorted) {
        if (absVal >= threshold) { displayValue = clamped / threshold; break; }
      }
    }

    final int effFD = widget.compactNotation
        ? (widget.compactFractionDigits ?? (widget.fractionDigits == 0 ? 1 : widget.fractionDigits))
        : widget.fractionDigits;

    final int val = (displayValue * math.pow(10, effFD)).round();
    List<double> digits = val == 0 ? [0.0] : [];
    int v = val.abs();
    while (v > 0) { digits.add(v.toDouble()); v = v ~/ 10; }
    while (digits.length < widget.wholeDigits + effFD) { digits.add(0.0); }
    return digits.reversed.toList(growable: false);
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_handleControllerUpdate);
    _unbindController(widget.controller);
    _startDelayTimer?.cancel();
    StartScheduler.instance.cancel(this);
    _bounceHandle?.cancel();
    _handle?.cancel();
    super.dispose();
  }

  // ── shared build helpers ──────────────────────────────────────────────────

  TextStyle _resolveStyle(BuildContext context) {
    final baseStyle = DefaultTextStyle.of(context).style.merge(widget.textStyle);
    var style = (widget.useTabularFigures && widget.textStyle?.fontFeatures == null)
        ? baseStyle.merge(const TextStyle(fontFeatures: [FontFeature.tabularFigures()]))
        : baseStyle;
    if (widget.colorResolver != null) {
      final resolved = widget.colorResolver!(_currentValue);
      if (resolved != null) style = style.merge(TextStyle(color: resolved));
    }
    return style;
  }

  /// Resolve the glyph a digit renders as, mirroring [_DigitColumn]'s logic:
  /// custom [numeralMapper] wins, else the [numeralSystem] table, else the
  /// Latin digit. Kept in sync with `digit_column.dart` so the prototype cell
  /// is measured with the exact glyph that will be painted.
  ///
  /// 解析某个数字实际渲染成的字形，逻辑与 [_DigitColumn] 一致：优先自定义
  /// [numeralMapper]，其次 [numeralSystem] 表，最后回退到拉丁数字。与
  /// `digit_column.dart` 保持同步，使原型单元格用真正绘制的字形来测量。
  ///
  /// @param digit The digit 0–9 to resolve.
  ///
  ///   要解析的数字 0–9。
  ///
  /// @returns The display string for [digit].
  ///
  ///   [digit] 对应的显示字符串。
  String _glyphForDigit(int digit) => widget.numeralMapper != null
      ? widget.numeralMapper!(digit)
      : (numeralSystemDigits[widget.numeralSystem]?[digit] ?? '$digit');

  void _updatePrototypeSize(TextStyle style, TextScaler textScaler) {
    // Resolve the glyphs first (cheap, no layout) so a change of
    // numeralMapper / numeralSystem invalidates the cached size even when the
    // text style is unchanged.
    //
    // 先解析字形（廉价，无需布局），使 numeralMapper / numeralSystem 变化时
    // 即便文本样式不变也能让缓存尺寸失效。
    final glyphs = [for (var d = 0; d <= 9; d++) _glyphForDigit(d)];
    final glyphSig = glyphs.join(' ');
    if (_prototypeSize != null &&
        style == _lastStyle &&
        textScaler == _lastTextScaler &&
        glyphSig == _lastGlyphSig) return;
    _lastStyle = style; _lastTextScaler = textScaler; _lastGlyphSig = glyphSig;
    // Measure every digit 0–9 as it will actually render (numeralMapper /
    // numeralSystem may yield glyphs wider or taller than Latin '0', e.g.
    // circled numbers ①–⑨), and size the cell to the widest & tallest so no
    // glyph is clipped.
    //
    // 按实际渲染字形逐一测量数字 0–9（numeralMapper / numeralSystem 可能产生
    // 比拉丁 '0' 更宽或更高的字形，例如圆圈数字 ①–⑨），单元格取最大宽高，
    // 使任何字形都不会被裁剪。
    double w = 0, h = 0;
    for (final g in glyphs) {
      final tp = TextPainter(
        text: TextSpan(text: g, style: style),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      if (tp.size.width  > w) w = tp.size.width;
      if (tp.size.height > h) h = tp.size.height;
      tp.dispose();
    }
    _prototypeSize = Size(w, h);
  }

  int _effectiveFractionDigits() => widget.compactNotation
      ? (widget.compactFractionDigits ?? (widget.fractionDigits == 0 ? 1 : widget.fractionDigits))
      : widget.fractionDigits;

  Widget _wrapColorTint(Widget child, Color baseColor) {
    if (_directionColor == null) return child;
    return TweenAnimationBuilder<Color?>(
      key: ValueKey(_colorAnimKey),
      tween: ColorTween(begin: _directionColor, end: baseColor),
      duration: widget.colorFadeDuration,
      builder: (_, Color? c, ch) =>
          DefaultTextStyle.merge(style: TextStyle(color: c), child: ch!),
      child: child,
    );
  }

  Widget _wrapSemantics(Widget child, String label) {
    // Apply the style's container decoration around the whole counter.
    //
    // 应用样式的容器装饰，包裹整个计数器。
    final decorated = applyBoxStyle(child, decoration: widget.decoration);
    if (label.isEmpty) return decorated;
    return Semantics(label: label, child: ExcludeSemantics(child: decorated));
  }

  String _buildSemanticText(int intValue) {
    final absValue = intValue.abs() / math.pow(10, widget.fractionDigits);
    final sign = intValue < 0 ? '-' : (widget.showPositiveSign && intValue > 0 ? '+' : '');
    return '$sign${absValue.toStringAsFixed(widget.fractionDigits)}';
  }

  Widget _buildAffix(String text, TextStyle? style, TextOverflow? overflow) {
    final w = Text(text, style: style, overflow: overflow);
    return overflow != null ? Flexible(child: w) : w;
  }
}
