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
  final CounterTransitionType transitionType;
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
    this.transitionType = CounterTransitionType.roll,
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
  double _bounceAlpha = 1.0;   // nxt digit alpha during bounce (< 1 = semi-transparent)
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
  int  _maxDigits          = 0;
  bool _isAnimatingDecrease = false;

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

    final effFD = widget.compactNotation
        ? (widget.compactFractionDigits ?? (widget.fractionDigits == 0 ? 1 : widget.fractionDigits))
        : widget.fractionDigits;
    final scaledNew = (newValue.abs() * math.pow(10, effFD)).round();
    _usingAdjustedTarget = newValue > 0 && scaledNew > 0 && isAllNinesTarget(scaledNew);
    if (_usingAdjustedTarget) {
      animTarget = newValue - 1.0 / math.pow(10, effFD);
    }

    final targetDigits = _getDigitsList(animTarget);
    _realTargetDigitValues = List<double>.from(_getDigitsList(newValue));
    // Never shrink _maxDigits — keeps SizedBox stable and numberAlignment
    // consistent when animating to a smaller value (e.g. 1000 → 7).
    _maxDigits = math.max(_maxDigits, math.max(oldDigits.length, targetDigits.length));

    _oldDigitValues    = [...List<double>.filled(_maxDigits - oldDigits.length, 0.0),    ...oldDigits];
    _targetDigitValues = [...List<double>.filled(_maxDigits - targetDigits.length, 0.0), ...targetDigits];
    _currentDigitValues = List<double>.from(_oldDigitValues);

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
        else _maybeTriggerBounce();
      },
    ));
  }

  void _onAnimStatusChange(AnimationStatus status) {
    widget.controller?.$notifyStatusListeners(status);
    if (status == AnimationStatus.completed) widget.onAnimationEnd?.call();
  }

  // ── post-animation bounce ─────────────────────────────────────────────────

  void _maybeTriggerBounce() {
    if (!mounted || widget.bounceOvershoot <= 0.0) return;

    // Each digit column bounces independently by one digit step in the
    // animation direction (increasing → +1, decreasing → −1).
    // This gives every visible digit drum a physical overshoot feel.
    // tanh keeps bounce within one digit unit regardless of parameter value.
    final double ex2     = math.exp(2.0 * widget.bounceOvershoot);
    final double maxFrac = (ex2 - 1) / (ex2 + 1);

    _bounceAlpha = 0.4; // nxt digit is 40% opacity during bounce

    final List<double> settled = List<double>.of(_currentDigitValues);

    _bounceHandle = counter(CounterOptions(
      from: 0.0,
      to: 1.0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.linear,
      allowNegative: false,
      onUpdate: (t) {
        if (!mounted) return;
        // Always add a positive offset: settled[i] → settled[i] + maxFrac*bump.
        // The painter's _increasing flag controls whether nxt = cur+1 (increasing)
        // or cur−1 (decreasing), so the correct adjacent digit appears without us
        // needing to negate the direction here.  The return path (offset → 0) is
        // always smooth: p decreases from maxFrac to 0, nxt fades out cleanly.
        final offset = maxFrac * math.sin(math.pi * t);
        for (int i = 0; i < _currentDigitValues.length; i++) {
          if (i >= settled.length) continue;
          // Leading-zero columns must stay at 0: a positive offset would make
          // them non-zero, defeating hideLeadingZeroes and showing phantom digits.
          if (settled[i] == 0.0) {
            _currentDigitValues[i] = 0.0;
          } else {
            _currentDigitValues[i] = settled[i] + offset;
          }
        }
        _onFrameUpdate();
      },
      onComplete: (_) {
        if (!mounted) return;
        _bounceAlpha = 1.0; // restore full opacity
        for (int i = 0; i < _currentDigitValues.length; i++) {
          if (i < settled.length) _currentDigitValues[i] = settled[i];
        }
        _onFrameUpdate();
        _bounceHandle = null;
      },
    ));
  }

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

    final double maxRange = _maxDigits > 0
        ? (_targetDigitValues.last - _oldDigitValues.last).abs() : 0;
    final bool autoEase = curve == Curves.linear && maxRange > widget.autoEaseThreshold;
    final Curve effectiveComputeCurve = autoEase ? Curves.easeInOut : curve;

    _currentDigitValues = List<double>.filled(_maxDigits, 0.0);

    for (int i = 0; i < _maxDigits; i++) {
      double tDigit = t;
      if (stagger != null && stagger > Duration.zero) {
        final double staggerUs = stagger.inMicroseconds.toDouble() / widget.speedMultiplier;
        final double delayUs   = switch (widget.staggerDirection) {
          StaggerDirection.leftToRight => staggerUs * i,
          StaggerDirection.rightToLeft => staggerUs * (_maxDigits - 1 - i),
        };
        final double elapsedUs = t * totalDurationUs;
        tDigit = ((elapsedUs - delayUs) / baseDurationUs).clamp(0.0, 1.0);
      }
      final Curve  digitCurve = widget.curveForDigit?.call(i) ?? effectiveComputeCurve;
      final double progress   = digitCurve.transform(tDigit);
      final double from       = _oldDigitValues[i];
      final double to         = _targetDigitValues[i];
      double value = widget.interpolation != null
          ? widget.interpolation!(from, to, progress)
          : from + (to - from) * progress;

      // Bounce is applied as a separate post-animation phase in _maybeTriggerBounce()
      // so that it is always visible: the target digit overshoots then snaps back.
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

  bool _hasDigitStarted(int i) {
    if (_currentT == 0.0) return false;
    final stagger = _effectiveStaggerDelay;
    if (stagger == null || stagger == Duration.zero) return true;
    final double staggerUs = stagger.inMicroseconds.toDouble() / widget.speedMultiplier;
    final double delayUs   = switch (widget.staggerDirection) {
      StaggerDirection.leftToRight => staggerUs * i,
      StaggerDirection.rightToLeft => staggerUs * (_maxDigits - 1 - i),
    };
    final double elapsedUs = _currentT * _effectiveDuration.inMicroseconds.toDouble();
    return elapsedUs > delayUs;
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
