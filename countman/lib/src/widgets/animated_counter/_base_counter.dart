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
