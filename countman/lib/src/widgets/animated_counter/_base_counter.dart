part of 'animated_counter.dart';

// ── shared widget base ────────────────────────────────────────────────────────

abstract class _BaseAnimatedCounter extends StatefulWidget {
  /// Aggregate visual style. Overrides the deprecated loose visual params
  /// field-by-field (see the resolving getters below).
  ///
  /// 聚合视觉样式。逐字段覆盖弃用的松散视觉参数（见下方解析 getter）。
  final AnimatedCounterStyle? style;

  /// 聚合格式；非空字段优先于平铺参数。
  final CounterFormat? format;

  /// 聚合动画时间轴；非空字段优先于平铺参数，空字段回退。
  final CounterTimeline? timeline;

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
  // 回弹现由 bounceOvershoot 驱动；保留字段以兼容旧代码。
  @Deprecated('No effect; use bounceOvershoot instead')
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

  /// 已解析的小数位数。
  int get _fmtFractionDigits => format?.fractionDigits ?? fractionDigits;
  /// 已解析的最少整数位数。
  int get _fmtWholeDigits => format?.wholeDigits ?? wholeDigits;
  /// 已解析的是否隐藏整数前导零。
  bool get _fmtHideLeadingZeroes => format?.hideLeadingZeroes ?? hideLeadingZeroes;
  /// 已解析的整数分组分隔符。
  String? get _fmtThousandSeparator => format?.thousandSeparator ?? thousandSeparator;
  /// 已解析的从右向左的分组位数
  List<int> get _fmtGroupingPattern => format?.groupingPattern ?? groupingPattern;
  /// 已解析的小数分隔符。
  String get _fmtDecimalSeparator => format?.decimalSeparator ?? decimalSeparator;
  /// 已解析的是否使用紧凑缩写。
  bool get _fmtCompactNotation => format?.compactNotation ?? compactNotation;
  /// 已解析的紧凑缩写的小数位数。
  int? get _fmtCompactFractionDigits => format?.compactFractionDigits ?? compactFractionDigits;
  /// 已解析的阈值到缩写的映射
  Map<num, String>? get _fmtCompactAbbreviations => format?.compactAbbreviations ?? compactAbbreviations;
  /// 已解析的是否显示正号。
  bool get _fmtShowPositiveSign => format?.showPositiveSign ?? showPositiveSign;
  /// 已解析的数字字形体系。
  NumeralSystem get _fmtNumeralSystem => format?.numeralSystem ?? numeralSystem;
  /// 已解析的将 digit（0–9）映射为字形的函数。
  String Function(int digit)? get _fmtNumeralMapper => format?.numeralMapper ?? numeralMapper;

  /// 用解析后的字段比较有效格式，忽略配置对象的实例身份。
  CounterFormat get _resolvedFormat => CounterFormat(
    fractionDigits: _fmtFractionDigits,
    wholeDigits: _fmtWholeDigits,
    hideLeadingZeroes: _fmtHideLeadingZeroes,
    thousandSeparator: _fmtThousandSeparator,
    groupingPattern: _fmtGroupingPattern,
    decimalSeparator: _fmtDecimalSeparator,
    compactNotation: _fmtCompactNotation,
    compactFractionDigits: _fmtCompactFractionDigits,
    compactAbbreviations: _fmtCompactAbbreviations,
    showPositiveSign: _fmtShowPositiveSign,
    numeralSystem: _fmtNumeralSystem,
    numeralMapper: _fmtNumeralMapper,
  );

  /// 已解析的正向滚动时长。
  Duration get _timeDuration => timeline?.duration ?? duration;

  /// 已解析的滚动曲线。
  Curve get _timeCurve => timeline?.curve ?? curve;

  /// 已解析的递减时的滚动时长。
  Duration? get _timeReverseDuration => timeline?.reverseDuration ?? reverseDuration;

  /// 已解析的递减时的滚动曲线。
  Curve? get _timeReverseCurve => timeline?.reverseCurve ?? reverseCurve;

  /// 已解析的开始滚动前的延迟；同样受倍速影响。
  Duration? get _timeStartDelay => timeline?.startDelay ?? startDelay;

  /// 已解析的播放倍速，必须大于零。
  double get _timeSpeedMultiplier => timeline?.speedMultiplier ?? speedMultiplier;

  /// 已解析的相邻数位的启动间隔。
  Duration? get _timeStaggerDelay => timeline?.staggerDelay ?? staggerDelay;

  /// 已解析的数位错峰的启动方向。
  StaggerDirection get _timeStaggerDirection => timeline?.staggerDirection ?? staggerDirection;

  /// 已解析的线性曲线自动转为缓动的数值跨度阈值。
  double get _timeAutoEaseThreshold => timeline?.autoEaseThreshold ?? autoEaseThreshold;

  /// 已解析的按从左到右的 digitIndex 返回逐位曲线；返回空时使用整体曲线。
  Curve? Function(int digitIndex)? get _timeCurveForDigit => timeline?.curveForDigit ?? curveForDigit;

  /// 已解析的根据起点 from、终点 to 与曲线进度 t 计算数位值。
  double Function(double from, double to, double t)? get _timeInterpolation => timeline?.interpolation ?? interpolation;

  /// 已解析的落位回弹幅度，必须非负；零表示关闭回弹。
  double get _timeBounceOvershoot => timeline?.bounceOvershoot ?? bounceOvershoot;

  /// 已解析的是否让每个数位仅滚动一步。
  bool get _timeFast => timeline?.fast ?? fast;

  /// 按有效字段值比较时间轴，忽略对象实例身份及被覆盖的平铺参数。
  CounterTimeline get _resolvedTimeline => CounterTimeline(
    duration: _timeDuration,
    curve: _timeCurve,
    reverseDuration: _timeReverseDuration,
    reverseCurve: _timeReverseCurve,
    startDelay: _timeStartDelay,
    speedMultiplier: _timeSpeedMultiplier,
    staggerDelay: _timeStaggerDelay,
    staggerDirection: _timeStaggerDirection,
    autoEaseThreshold: _timeAutoEaseThreshold,
    curveForDigit: _timeCurveForDigit,
    interpolation: _timeInterpolation,
    bounceOvershoot: _timeBounceOvershoot,
    fast: _timeFast,
  );

  /// 创建共享计数器；format、timeline 的非空字段优先于同名平铺参数。
  const _BaseAnimatedCounter({
    super.key,
    this.style,
    this.format,
    this.timeline,
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
    @Deprecated('No effect; use bounceOvershoot instead')
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
  // 格式配置随组件更新；一次排序供拆位与构建共同使用。
  final _numberFormat = CounterNumberFormat();

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
  // repeat 时每轮结束后是否交换端点往返播放。
  bool _repeatReverse = false;
  // 尚未真正开始的启动动作（startDelay 或批量队列中）；pause 时保留，resume 时执行。
  VoidCallback? _pendingStart;

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
  // Fast mode (widget._timeFast): per-column old/new digit (0–9), computed once per
  // transition. In fast mode _currentDigitValues[i] carries the 0–1 progress.
  //
  // 快速模式（widget._timeFast）：每列旧/新位（0–9），每次过渡算一次。此模式下
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
        : ((_isAnimatingDecrease && widget._timeReverseDuration != null)
            ? widget._timeReverseDuration!
            : widget._timeDuration);
    // 系统减少动画时直接落位；错峰按原始时间累加后统一缩放一次。
    if (reduceMotion) return Duration.zero;
    Duration d = base;
    final stagger = widget._timeStaggerDelay;
    if (stagger != null && stagger > Duration.zero) {
      d += stagger * (_maxDigits - 1);
    }
    return widget._timeSpeedMultiplier == 1.0
        ? d
        : Duration(microseconds: (d.inMicroseconds / widget._timeSpeedMultiplier).round());
  }

  Curve get _effectiveCurve {
    if (_isAnimatingDecrease && widget._timeReverseCurve != null) return widget._timeReverseCurve!;
    return widget._timeCurve;
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
    if (widget._timeStaggerDelay == null) return null;
    return widget._timeSpeedMultiplier == 1.0
        ? widget._timeStaggerDelay
        : Duration(microseconds: (widget._timeStaggerDelay!.inMicroseconds / widget._timeSpeedMultiplier).round());
  }

  Duration get _effectiveNegativeSignDuration => widget._timeSpeedMultiplier == 1.0
      ? widget.negativeSignDuration
      : Duration(microseconds: (widget.negativeSignDuration.inMicroseconds / widget._timeSpeedMultiplier).round());

  Duration get _effectivePositiveSignDuration {
    final base = widget.positiveSignDuration ?? widget.negativeSignDuration;
    return widget._timeSpeedMultiplier == 1.0
        ? base
        : Duration(microseconds: (base.inMicroseconds / widget._timeSpeedMultiplier).round());
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
    final formatChanged = oldWidget._resolvedFormat != widget._resolvedFormat;
    final timelineChanged = oldWidget._resolvedTimeline != widget._resolvedTimeline;
    if (formatChanged || oldWidget._timeFast != widget._timeFast) {
      // 格式或 fast 改变时重新拆位，避免延迟期间沿用旧端点或进度表示。
      _refreshFormatDigits();
    } else if (timelineChanged) {
      // 新时间轴可能带启动延迟，先取消旧调度以免继续按旧进度更新。
      _cancelActive(dropPending: true);
    }
    if (oldVal != newVal || formatChanged || timelineChanged) {
      _triggerTransitionWithDelay(oldVal ?? 0, newVal ?? 0);
    }
  }

  /// 立即按新格式重建当前值数位，保证启动延迟期间两条路径也可安全绘制。
  void _refreshFormatDigits() {
    _cancelActive(dropPending: true);
    final digits = _getDigitsList(_currentValue);
    _maxDigits = digits.length;
    _oldDigitValues = List<double>.from(digits);
    _targetDigitValues = List<double>.from(digits);
    _currentDigitValues = List<double>.from(digits);
    _realTargetDigitValues = List<double>.from(digits);
    _fastFromDigits = [for (final digit in digits) digit.toInt().abs() % 10];
    _fastToDigits = List<int>.from(_fastFromDigits);
    if (widget._timeFast) {
      _currentDigitValues = List<double>.filled(_maxDigits, 1.0);
    }
    _usingAdjustedTarget = false;
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
      _cancelActive();
      widget.onPause?.call();
    };
    c.$resumeCallback  = () {
      final pending = _pendingStart;
      _pendingStart = null;
      if (pending != null) {
        pending();
      } else {
        _launchHandle(fromT: _pausedT);
      }
      widget.onResume?.call();
    };
    c.$stopCallback    = () {
      _cancelActive(dropPending: true);
      _repeating = false;
    };
    c.$restartCallback = () {
      _cancelActive(dropPending: true);
      _repeating = false;
      _launchHandle(fromT: 0);
      widget.onAnimationStart?.call();
    };
    c.$repeatCallback  = ({bool reverse = false}) {
      _repeating = true;
      _repeatReverse = reverse;
      _launchHandle(fromT: 0);
      widget.onRepeat?.call();
    };
    c.$reverseCallback = () {
      _swapEndpoints();
      _launchHandle(fromT: 1.0 - _currentT);
      _updateCurrentDigitValues();
      _onFrameUpdate();
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
    _pendingStart = null;
    if (widget._timeStartDelay != null && widget._timeStartDelay! > Duration.zero) {
      final delay = Duration(microseconds:
          (widget._timeStartDelay!.inMicroseconds / widget._timeSpeedMultiplier).round());
      void start() {
        _pendingStart = null;
        if (mounted) _startAnimationTransition(oldValue, newValue);
      }
      _pendingStart = start;
      _startDelayTimer = Timer(delay, start);
    } else {
      _startAnimationTransition(oldValue, newValue);
    }
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
    final tmp = List<double>.from(_oldDigitValues);
    _oldDigitValues    = List<double>.from(_targetDigitValues);
    _targetDigitValues = tmp;
    final fastTmp = _fastFromDigits;
    _fastFromDigits = _fastToDigits;
    _fastToDigits   = fastTmp;
    _usingAdjustedTarget = false;
    _isAnimatingDecrease = !_isAnimatingDecrease;
  }

  void _startAnimationTransition(num oldValue, num newValue) {
    // 新转换先取消旧主动画、回弹与排队启动，避免旧任务覆盖新端点。
    _cancelActive(dropPending: true);
    _repeating = false;
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
    if (widget._timeFast) {
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
      void launch() {
        _pendingStart = null;
        if (mounted) _launchHandle(fromT: 0);
      }
      _pendingStart = launch;
      StartScheduler.instance.enqueue(launch, tag: this);
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
    if (!mounted || widget._timeBounceOvershoot <= 0.0) return;

    final double ex2     = math.exp(2.0 * widget._timeBounceOvershoot);
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
        : ((_isAnimatingDecrease && widget._timeReverseDuration != null)
            ? widget._timeReverseDuration! : widget._timeDuration);
    if (baseDuration == Duration.zero) baseDuration = const Duration(microseconds: 1);
    final double baseDurationUs = baseDuration.inMicroseconds.toDouble() / widget._timeSpeedMultiplier;

    final Duration? stagger = _effectiveStaggerDelay;
    // _effectiveStaggerDelay 已按倍速缩放，此处不再重复缩放。
    final double staggerUs =
        (stagger == null) ? 0.0 : stagger.inMicroseconds.toDouble();

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
  double _staggerDelayUs(int i, double staggerUs) => switch (widget._timeStaggerDirection) {
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
        : ((_isAnimatingDecrease && widget._timeReverseDuration != null)
            ? widget._timeReverseDuration! : widget._timeDuration);
    if (baseDuration == Duration.zero) baseDuration = const Duration(microseconds: 1);

    final double baseDurationUs  = baseDuration.inMicroseconds.toDouble() / widget._timeSpeedMultiplier;
    final double totalDurationUs = _effectiveDuration.inMicroseconds.toDouble();

    // autoEase off the total numeric span, not the per-digit wrapped delta
    // (which is now ≤ 10 and would never cross the threshold).
    //
    // autoEase 依据数值总跨度，而非逐位环绕增量（后者现已 ≤ 10，永远够不到阈值）。
    final bool autoEase = curve == Curves.linear && _valueRange > widget._timeAutoEaseThreshold;
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
        ? stagger.inMicroseconds.toDouble() // 已按倍速缩放
        : 0.0;
    final double elapsedUs = t * totalDurationUs;

    for (int i = 0; i < _maxDigits; i++) {
      double tDigit = t;
      // t 到终点（含减少动画直接落位）时各位一律到位，不再按错峰延迟折算。
      if (staggerUs > 0.0 && t < 1.0) {
        final double delayUs = _staggerDelayUs(i, staggerUs);
        tDigit = ((elapsedUs - delayUs) / baseDurationUs).clamp(0.0, 1.0);
      }
      final Curve  digitCurve = widget._timeCurveForDigit?.call(i) ?? effectiveComputeCurve;
      final double progress   = digitCurve.transform(tDigit);

      // Fast mode: the column just carries its 0–1 progress; the from→new-digit
      // single step is rendered by the painter / DigitColumn (no cascade here).
      //
      // 快速模式：列只携带 0–1 进度；from→新位 的单步由 painter / DigitColumn 渲染
      // （此处不做级联）。
      if (widget._timeFast) {
        _currentDigitValues[i] = progress;
        continue;
      }

      final double from       = _oldDigitValues[i];
      final double to         = _targetDigitValues[i];
      double value = widget._timeInterpolation != null
          ? widget._timeInterpolation!(from, to, progress)
          : from + (to - from) * progress;

      // Bounce is applied separately as a per-column positional nudge in
      // _startBounceWave() (concurrent with the roll), not baked into the value.
      //
      // 回弹在 _startBounceWave() 中作为逐列位置轻推单独施加（与滚动并发），不写入数值。
      _currentDigitValues[i] = value;
    }
  }

  // 初始化、动画端点和渲染使用相同的格式解析结果。
  CounterDisplayNumber _displayNumber(num value) {
    // 控制器更新也可能伴随字典原地修改；仅配置变化时重新排序。
    _numberFormat.updateAbbreviations(widget._fmtCompactAbbreviations);
    return _numberFormat.resolve(
      value,
      minValue: widget.minValue,
      maxValue: widget.maxValue,
      fractionDigits: widget._fmtFractionDigits,
      compactNotation: widget._fmtCompactNotation,
      compactFractionDigits: widget._fmtCompactFractionDigits,
    );
  }

  List<double> _getDigitsList(num targetValue) =>
      _displayNumber(targetValue).digits(widget._fmtWholeDigits);

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
  String _glyphForDigit(int digit) => widget._fmtNumeralMapper != null
      ? widget._fmtNumeralMapper!(digit)
      : (numeralSystemDigits[widget._fmtNumeralSystem]?[digit] ?? '$digit');

  void _updatePrototypeSize(TextStyle style, TextScaler textScaler) {
    // Resolve the glyphs first (cheap, no layout) so a change of
    // numeralMapper / numeralSystem invalidates the cached size even when the
    // text style is unchanged.
    //
    // 先解析字形（廉价，无需布局），使 numeralMapper / numeralSystem 变化时
    // 即便文本样式不变也能让缓存尺寸失效。
    final glyphs = [for (var d = 0; d <= 9; d++) _glyphForDigit(d)];
    final glyphSig = glyphs.join(' ');
    // 缓存命中时直接返回，显式括号满足静态检查。
    if (_prototypeSize != null &&
        style == _lastStyle &&
        textScaler == _lastTextScaler &&
        glyphSig == _lastGlyphSig) {
      return;
    }
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

  // 动画位数与格式解析使用同一规则。
  int _effectiveFractionDigits() => counterFractionDigits(
    compactNotation: widget._fmtCompactNotation,
    fractionDigits: widget._fmtFractionDigits,
    compactFractionDigits: widget._fmtCompactFractionDigits,
  );

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
    final absValue = intValue.abs() / math.pow(10, widget._fmtFractionDigits);
    final sign = intValue < 0 ? '-' : (widget._fmtShowPositiveSign && intValue > 0 ? '+' : '');
    return '$sign${absValue.toStringAsFixed(widget._fmtFractionDigits)}';
  }

  Widget _buildAffix(String text, TextStyle? style, TextOverflow? overflow) {
    final w = Text(text, style: style, overflow: overflow);
    return overflow != null ? Flexible(child: w) : w;
  }
}
