part of 'animated_counter.dart';

// ── shared widget base ────────────────────────────────────────────────────────

/// 共享数字格式与动画参数；小数位仅支持 0–20。
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
        assert(fractionDigits >= 0 && fractionDigits <= counterMaxFractionDigits),
        assert(compactFractionDigits == null ||
            (compactFractionDigits >= 0 && compactFractionDigits <= counterMaxFractionDigits)),
        assert(wholeDigits >= 0),
        assert(speedMultiplier > 0),
        assert(bounceOvershoot >= 0.0),
        assert(bounceElasticity >= 1.0);
}

// ── shared state base ─────────────────────────────────────────────────────────

/// 动画生命周期；只有暂停态允许恢复。
enum _CounterPlayback { idle, running, paused, completed }

/// 两条渲染路径共用的可中断动画状态机。
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
  /// 当前转换版本；用户回调重入后旧转换必须退出。
  int _requestVersion = 0;
  /// 显式播放状态，避免完成后 resume 重播旧任务。
  _CounterPlayback _playback = _CounterPlayback.idle;
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
  double _currentT = 0.0;
  double _pausedT  = 0.0;
  bool _repeating  = false;
  // repeat 时每轮结束后是否交换端点往返播放。
  bool _repeatReverse = false;
  // 尚未真正开始的启动动作（startDelay 或批量队列中）；pause 时保留，resume 时执行。
  VoidCallback? _pendingStart;

  // ── digit state ───────────────────────────────────────────────────────────
  Timer? _startDelayTimer;
  Color? _directionColor;
  int   _colorAnimKey = 0;
  /// 一次方向变色仅生成有限档位，帧间复用颜色和段落。
  List<Color> _tintPalette = const [];
  /// 当前色板对应的文字样式，避免 Builder 每帧复制 TextStyle。
  List<TextStyle> _tintStyles = const [];
  /// 文字样式缓存的基准配置。
  TextStyle? _tintStyleBase;
  /// 文字样式缓存对应的色板。
  List<Color>? _tintStylePalette;
  /// 上次应用的档位，避免同一量化档位重复触发重绘。
  int _appliedTintBucket = -1;
  /// 当前颜色档位；未配置方向色时保持空色板。
  int _tintBucket = 0;
  /// 已准备色板的动画标识。
  int _paletteKey = -1;
  /// 当前数字颜色；Builder 和 painter 共用同一档位。
  Color? get _digitTint => _tintPalette.isEmpty ? null : _tintPalette[_tintBucket];
  /// 方向色渐变的有限档位数。
  static const int _tintSteps = 16;
  num   _lastValue    = 0;
  num   _currentValue = 0;

  /// 数位滚动引擎：持有各列端点与当前位置，进度到位置的换算都在其中。
  /// 快速模式（widget._timeFast）下 currentDigits[i] 携带 0–1 进度。
  final _engine = DigitRollEngine();
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

  /// 动画完成且数位已到达真实端点时通知两条渲染路径。
  void _onAnimationComplete();

  // ── helpers ───────────────────────────────────────────────────────────────

  num get _effectiveValue =>
      widget.controller != null ? widget.controller!.value : (widget.value ?? 0);

  /// 单列滚动的基础时长：控制器临时覆盖 > 递减专用时长 > 常规时长（未按倍速缩放）。
  Duration get _baseDuration =>
      (widget.controller != null && widget.controller!.overrideDuration != null)
          ? widget.controller!.overrideDuration!
          : ((_isAnimatingDecrease && widget._timeReverseDuration != null)
              ? widget._timeReverseDuration!
              : widget._timeDuration);

  /// 零时长命令跳过错峰，其他时长统一按倍速缩放。
  Duration get _effectiveDuration {
    final base = _baseDuration;
    // 系统减少动画时直接落位；错峰按原始时间累加后统一缩放一次。
    if (reduceMotion || base == Duration.zero) return Duration.zero;
    Duration d = base;
    final stagger = widget._timeStaggerDelay;
    if (stagger != null && stagger > Duration.zero) {
      d += stagger * (_engine.maxDigits - 1);
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

  /// 初始化两套数位端点，静态 fast 直接处于完成进度。
  @override
  void initState() {
    super.initState();
    _currentValue = widget.initialValue.isFinite ? widget.initialValue : 0;
    _fromValue = _currentValue;
    _lastValue    = _currentValue;
    _engine.settle(_getDigitsList(_currentValue), fast: widget._timeFast);
    _currentT = 1.0;
    _bindController();
    widget.controller?.addListener(_handleControllerUpdate);
    if (widget.initialValue != _effectiveValue) {
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

  // ── controller binding ────────────────────────────────────────────────────

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
    if (targetColor != null) { _directionColor = targetColor; _colorAnimKey++; }
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
    _bounceHandle = counter(CounterOptions(
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

  /// 单列滚动时长（微秒，已按倍速缩放，不含错峰）；零时长按 1µs 计避免除零。
  double get _baseDurationUs {
    Duration base = _baseDuration;
    if (base == Duration.zero) base = const Duration(microseconds: 1);
    return base.inMicroseconds.toDouble() / widget._timeSpeedMultiplier;
  }

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
    final glyphSig = glyphs.join('\u0000');
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

  /// 返回当前方向色的缓存文字样式；每次配置变更最多构建一个有限色板。
  TextStyle _digitStyleFor(TextStyle base) {
    if (_tintPalette.isEmpty) return base;
    if (_tintStyleBase != base || !identical(_tintStylePalette, _tintPalette)) {
      _tintStyleBase = base;
      _tintStylePalette = _tintPalette;
      _tintStyles = [for (final color in _tintPalette) base.copyWith(color: color)];
    }
    return _tintStyles[_tintBucket];
  }

  /// 量化方向色并直接更新数字；子树与 painter 均不依赖外层文字继承。
  Widget _wrapColorTint(Widget child, Color baseColor) {
    if (_directionColor == null) return child;
    if (_paletteKey != _colorAnimKey) {
      _paletteKey = _colorAnimKey;
      _tintPalette = List<Color>.generate(_tintSteps,
          (i) => Color.lerp(_directionColor, baseColor, i / (_tintSteps - 1))!);
      _tintBucket = 0;
      _appliedTintBucket = -1;
    }
    return TweenAnimationBuilder<double>(
      key: ValueKey(_colorAnimKey),
      tween: Tween(begin: 0, end: 1),
      duration: widget.colorFadeDuration,
      builder: (_, t, ch) {
        final bucket = (t * (_tintSteps - 1)).round();
        if (_appliedTintBucket != bucket) {
          _tintBucket = bucket;
          _appliedTintBucket = bucket;
          _onFrameUpdate();
        }
        return ch!;
      },
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

  /// 语义文本与屏幕共用缩写、小数位和有限值处理。
  String _buildSemanticText(int intValue) {
    final display = _displayNumber(_currentValue);
    final absValue = display.scaledValue.abs() / math.pow(10, display.fractionDigits);
    final sign = display.scaledValue < 0 ? '-' :
        (widget._fmtShowPositiveSign && display.scaledValue > 0 ? '+' : '');
    return '$sign${absValue.toStringAsFixed(display.fractionDigits)}${display.suffix ?? ""}';
  }

  Widget _buildAffix(String text, TextStyle? style, TextOverflow? overflow) {
    final w = Text(text, style: style, overflow: overflow);
    return overflow != null ? Flexible(child: w) : w;
  }
}
