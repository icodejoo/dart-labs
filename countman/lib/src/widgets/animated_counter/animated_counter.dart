// Adapted from flip_counter_plus (MIT).
// Original: https://github.com/Itsxhadi/flip_counter_plus
//
// Changes from original:
//   1. Renamed AnimatedFlipCounter -> AnimatedCounter.
//   2. Replaced AnimationController (per-instance vsync ticker) with
//      Counter driving the shared Countman scheduleFrameCallback.
//      N counters share ONE frame callback instead of N AnimationControllers.
//   3. Replaced setState(){ _updateCurrentDigitValues() } with
//      ValueNotifier<int> (_rebuildNotifier) so only the digit Row rebuilds
//      each frame - prefix/suffix/color-tint are static.
//   4. roll transition rendering moved to digit_column.dart (Transform.translate).
//      Other transition types are unchanged.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:countman/src/counter/plugin.dart';
import 'package:countman/src/counter/types.dart';

import 'package:countman/src/core/start_scheduler.dart';

import '../painter/counter_painter.dart';
import 'counter_controller.dart';
import 'digit_column.dart';
import 'types.dart';

export 'counter_controller.dart';
export 'types.dart';

/// True when [n] consists entirely of 9s (9, 99, 999, …): `(n + 1)` is a power
/// of ten. `AnimatedCounter` uses this to detect the degenerate all-nines
/// target (which stalls the digit interpolation) and animate to `n - ε`,
/// snapping to the real target at `onComplete`. Every multiple of 9 (18, 27, …)
/// must NOT trigger this.
@visibleForTesting
bool isAllNinesTarget(int n) {
  if (n < 9) return false;
  var m = n + 1;
  while (m % 10 == 0) {
    m ~/= 10;
  }
  return m == 1;
}

// ── widget ────────────────────────────────────────────────────────────────

class AnimatedCounter extends StatefulWidget {
  final num? value;
  final AnimatedCounterController? controller;
  final Duration duration;
  final Duration negativeSignDuration;
  final Curve curve;
  final TextStyle? textStyle;
  final String? prefix;
  final String? infix;
  final String? suffix;
  final TextStyle? prefixStyle;
  final TextStyle? infixStyle;
  final TextStyle? suffixStyle;
  final TextOverflow? prefixOverflow;
  final TextOverflow? infixOverflow;
  final TextOverflow? suffixOverflow;
  final int fractionDigits;
  final int wholeDigits;
  final bool hideLeadingZeroes;
  final String? thousandSeparator;
  final List<int> groupingPattern;
  final String decimalSeparator;
  final TextStyle? separatorStyle;
  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;
  final EdgeInsets padding;
  final bool useTabularFigures;
  final bool showPositiveSign;
  final Duration? positiveSignDuration;
  final String? semanticsLabel;
  final VoidCallback? onAnimationEnd;
  final VoidCallback? onAnimationStart;
  final AxisDirection flipDirection;
  final Widget Function(BuildContext context, int digit, TextStyle style)? digitBuilder;
  final num? minValue;
  final num? maxValue;
  final Color? increasingColor;
  final Color? decreasingColor;
  final Duration colorFadeDuration;
  final Widget? prefixWidget;
  final Widget? infixWidget;
  final Widget? suffixWidget;
  final Widget? thousandSeparatorWidget;
  final Widget? decimalSeparatorWidget;
  final Widget? negativeSignWidget;
  final Widget? positiveSignWidget;
  final Widget Function(BuildContext context, int index, Widget child)? digitWrapperBuilder;
  final Widget Function(BuildContext context, Widget currentDigit, Widget nextDigit, double progress, Size size)? digitTransitionBuilder;
  final Duration? staggerDelay;
  final StaggerDirection staggerDirection;
  final bool compactNotation;
  final bool triggerHaptics;
  final int? compactFractionDigits;
  final num? initialValue;
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

  /// Wraps the digit row in a [RepaintBoundary].
  /// Default: true. Set to false when many instances share one layer.
  final bool repaintBoundary;

  /// When no explicit [curve] is set (i.e. [Curves.linear]) and the animated
  /// range exceeds this threshold, [Curves.easeInOut] is applied automatically
  /// to the digit-value computation to prevent large first/last-frame jumps.
  /// Default: 100 000. Set to [double.infinity] to disable auto-ease.
  final double autoEaseThreshold;


  const AnimatedCounter({
    super.key,
    this.value,
    this.controller,
    this.duration = const Duration(milliseconds: 300),
    this.negativeSignDuration = const Duration(milliseconds: 150),
    this.curve = Curves.linear,
    this.textStyle,
    this.prefix,
    this.infix,
    this.suffix,
    this.fractionDigits = 0,
    this.wholeDigits = 1,
    this.hideLeadingZeroes = true,
    this.thousandSeparator,
    this.groupingPattern = const [3],
    this.decimalSeparator = '.',
    this.separatorStyle,
    this.mainAxisAlignment = MainAxisAlignment.center,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.padding = EdgeInsets.zero,
    this.useTabularFigures = true,
    this.prefixStyle,
    this.infixStyle,
    this.suffixStyle,
    this.prefixOverflow,
    this.infixOverflow,
    this.suffixOverflow,
    this.showPositiveSign = false,
    this.positiveSignDuration,
    this.semanticsLabel,
    this.onAnimationEnd,
    this.onAnimationStart,
    this.flipDirection = AxisDirection.up,
    this.digitBuilder,
    this.minValue,
    this.maxValue,
    this.increasingColor,
    this.decreasingColor,
    this.colorFadeDuration = const Duration(milliseconds: 800),
    this.prefixWidget,
    this.infixWidget,
    this.suffixWidget,
    this.thousandSeparatorWidget,
    this.decimalSeparatorWidget,
    this.negativeSignWidget,
    this.positiveSignWidget,
    this.digitWrapperBuilder,
    this.digitTransitionBuilder,
    this.staggerDelay,
    this.staggerDirection = StaggerDirection.rightToLeft,
    this.compactNotation = false,
    this.triggerHaptics = false,
    this.compactFractionDigits,
    this.initialValue,
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
  })  : assert(value != null || controller != null,
            'Either value or controller must be provided'),
        assert(fractionDigits >= 0),
        assert(wholeDigits >= 0),
        assert(speedMultiplier > 0);

  // 鈹€鈹€ locale factory constructors (unchanged from original) 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

  factory AnimatedCounter.usd({
    Key? key, num? value, AnimatedCounterController? controller,
    Duration duration = const Duration(milliseconds: 300), Curve curve = Curves.linear,
    TextStyle? textStyle, String? suffix, int fractionDigits = 2, int wholeDigits = 1,
    bool hideLeadingZeroes = false, MainAxisAlignment mainAxisAlignment = MainAxisAlignment.center,
    CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.center,
    EdgeInsets padding = EdgeInsets.zero, bool useTabularFigures = true,
    bool showPositiveSign = false, String? semanticsLabel,
    VoidCallback? onAnimationEnd, VoidCallback? onAnimationStart,
    AxisDirection flipDirection = AxisDirection.up,
    Widget Function(BuildContext, int, TextStyle)? digitBuilder,
    num? minValue, num? maxValue, Color? increasingColor, Color? decreasingColor,
    Duration colorFadeDuration = const Duration(milliseconds: 800),
    Widget? prefixWidget, Widget? infixWidget, Widget? suffixWidget,
    Widget? thousandSeparatorWidget, Widget? decimalSeparatorWidget,
    Widget? negativeSignWidget, Widget? positiveSignWidget,
    Widget Function(BuildContext, int, Widget)? digitWrapperBuilder,
    Widget Function(BuildContext, Widget, Widget, double, Size)? digitTransitionBuilder,
    Duration? staggerDelay, StaggerDirection staggerDirection = StaggerDirection.rightToLeft,
    bool compactNotation = false, bool triggerHaptics = false, int? compactFractionDigits,
    num? initialValue, NumeralSystem numeralSystem = NumeralSystem.latin,
    String Function(int)? numeralMapper, CounterTransitionType transitionType = CounterTransitionType.roll,
    Duration? reverseDuration, Curve? reverseCurve, Duration? startDelay,
    double speedMultiplier = 1.0, Map<num, String>? compactAbbreviations,
  }) => AnimatedCounter(
    key: key, value: value, controller: controller, duration: duration, curve: curve,
    textStyle: textStyle, prefix: r'$', suffix: suffix, fractionDigits: fractionDigits,
    wholeDigits: wholeDigits, hideLeadingZeroes: hideLeadingZeroes,
    thousandSeparator: ',', groupingPattern: const [3], decimalSeparator: '.',
    mainAxisAlignment: mainAxisAlignment, crossAxisAlignment: crossAxisAlignment,
    padding: padding, useTabularFigures: useTabularFigures, showPositiveSign: showPositiveSign,
    semanticsLabel: semanticsLabel, onAnimationEnd: onAnimationEnd, onAnimationStart: onAnimationStart,
    flipDirection: flipDirection, digitBuilder: digitBuilder, minValue: minValue, maxValue: maxValue,
    increasingColor: increasingColor, decreasingColor: decreasingColor,
    colorFadeDuration: colorFadeDuration, prefixWidget: prefixWidget, infixWidget: infixWidget,
    suffixWidget: suffixWidget, thousandSeparatorWidget: thousandSeparatorWidget,
    decimalSeparatorWidget: decimalSeparatorWidget, negativeSignWidget: negativeSignWidget,
    positiveSignWidget: positiveSignWidget, digitWrapperBuilder: digitWrapperBuilder,
    digitTransitionBuilder: digitTransitionBuilder, staggerDelay: staggerDelay,
    staggerDirection: staggerDirection, compactNotation: compactNotation,
    triggerHaptics: triggerHaptics, compactFractionDigits: compactFractionDigits,
    initialValue: initialValue, numeralSystem: numeralSystem, numeralMapper: numeralMapper,
    transitionType: transitionType, reverseDuration: reverseDuration, reverseCurve: reverseCurve,
    startDelay: startDelay, speedMultiplier: speedMultiplier, compactAbbreviations: compactAbbreviations,
  );

  factory AnimatedCounter.cny({
    Key? key, num? value, AnimatedCounterController? controller,
    Duration duration = const Duration(milliseconds: 300), Curve curve = Curves.linear,
    TextStyle? textStyle, String? suffix, int fractionDigits = 2, int wholeDigits = 1,
    bool hideLeadingZeroes = false, MainAxisAlignment mainAxisAlignment = MainAxisAlignment.center,
    CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.center,
    EdgeInsets padding = EdgeInsets.zero, bool useTabularFigures = true,
    bool showPositiveSign = false, String? semanticsLabel,
    VoidCallback? onAnimationEnd, VoidCallback? onAnimationStart,
    AxisDirection flipDirection = AxisDirection.up,
    Widget Function(BuildContext, int, TextStyle)? digitBuilder,
    num? minValue, num? maxValue, Color? increasingColor, Color? decreasingColor,
    Duration colorFadeDuration = const Duration(milliseconds: 800),
    Widget? prefixWidget, Widget? infixWidget, Widget? suffixWidget,
    Widget? thousandSeparatorWidget, Widget? decimalSeparatorWidget,
    Widget? negativeSignWidget, Widget? positiveSignWidget,
    Widget Function(BuildContext, int, Widget)? digitWrapperBuilder,
    Widget Function(BuildContext, Widget, Widget, double, Size)? digitTransitionBuilder,
    Duration? staggerDelay, StaggerDirection staggerDirection = StaggerDirection.rightToLeft,
    bool compactNotation = false, bool triggerHaptics = false, int? compactFractionDigits,
    num? initialValue, NumeralSystem numeralSystem = NumeralSystem.latin,
    String Function(int)? numeralMapper, CounterTransitionType transitionType = CounterTransitionType.roll,
    Duration? reverseDuration, Curve? reverseCurve, Duration? startDelay,
    double speedMultiplier = 1.0, Map<num, String>? compactAbbreviations,
  }) => AnimatedCounter(
    key: key, value: value, controller: controller, duration: duration, curve: curve,
    textStyle: textStyle, prefix: '楼', suffix: suffix, fractionDigits: fractionDigits,
    wholeDigits: wholeDigits, hideLeadingZeroes: hideLeadingZeroes,
    thousandSeparator: ',', groupingPattern: const [4], decimalSeparator: '.',
    mainAxisAlignment: mainAxisAlignment, crossAxisAlignment: crossAxisAlignment,
    padding: padding, useTabularFigures: useTabularFigures, showPositiveSign: showPositiveSign,
    semanticsLabel: semanticsLabel, onAnimationEnd: onAnimationEnd, onAnimationStart: onAnimationStart,
    flipDirection: flipDirection, digitBuilder: digitBuilder, minValue: minValue, maxValue: maxValue,
    increasingColor: increasingColor, decreasingColor: decreasingColor,
    colorFadeDuration: colorFadeDuration, prefixWidget: prefixWidget, infixWidget: infixWidget,
    suffixWidget: suffixWidget, thousandSeparatorWidget: thousandSeparatorWidget,
    decimalSeparatorWidget: decimalSeparatorWidget, negativeSignWidget: negativeSignWidget,
    positiveSignWidget: positiveSignWidget, digitWrapperBuilder: digitWrapperBuilder,
    digitTransitionBuilder: digitTransitionBuilder, staggerDelay: staggerDelay,
    staggerDirection: staggerDirection, compactNotation: compactNotation,
    triggerHaptics: triggerHaptics, compactFractionDigits: compactFractionDigits,
    initialValue: initialValue, numeralSystem: numeralSystem, numeralMapper: numeralMapper,
    transitionType: transitionType, reverseDuration: reverseDuration, reverseCurve: reverseCurve,
    startDelay: startDelay, speedMultiplier: speedMultiplier, compactAbbreviations: compactAbbreviations,
  );

  factory AnimatedCounter.inr({
    Key? key, num? value, AnimatedCounterController? controller,
    Duration duration = const Duration(milliseconds: 300), Curve curve = Curves.linear,
    TextStyle? textStyle, String? suffix, int fractionDigits = 2, int wholeDigits = 1,
    bool hideLeadingZeroes = false, MainAxisAlignment mainAxisAlignment = MainAxisAlignment.center,
    CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.center,
    EdgeInsets padding = EdgeInsets.zero, bool useTabularFigures = true,
    bool showPositiveSign = false, String? semanticsLabel,
    VoidCallback? onAnimationEnd, VoidCallback? onAnimationStart,
    AxisDirection flipDirection = AxisDirection.up,
    Widget Function(BuildContext, int, TextStyle)? digitBuilder,
    num? minValue, num? maxValue, Color? increasingColor, Color? decreasingColor,
    Duration colorFadeDuration = const Duration(milliseconds: 800),
    Widget? prefixWidget, Widget? infixWidget, Widget? suffixWidget,
    Widget? thousandSeparatorWidget, Widget? decimalSeparatorWidget,
    Widget? negativeSignWidget, Widget? positiveSignWidget,
    Widget Function(BuildContext, int, Widget)? digitWrapperBuilder,
    Widget Function(BuildContext, Widget, Widget, double, Size)? digitTransitionBuilder,
    Duration? staggerDelay, StaggerDirection staggerDirection = StaggerDirection.rightToLeft,
    bool compactNotation = false, bool triggerHaptics = false, int? compactFractionDigits,
    num? initialValue, NumeralSystem numeralSystem = NumeralSystem.latin,
    String Function(int)? numeralMapper, CounterTransitionType transitionType = CounterTransitionType.roll,
    Duration? reverseDuration, Curve? reverseCurve, Duration? startDelay,
    double speedMultiplier = 1.0, Map<num, String>? compactAbbreviations,
  }) => AnimatedCounter(
    key: key, value: value, controller: controller, duration: duration, curve: curve,
    textStyle: textStyle, prefix: '₹', suffix: suffix, fractionDigits: fractionDigits,
    wholeDigits: wholeDigits, hideLeadingZeroes: hideLeadingZeroes,
    thousandSeparator: ',', groupingPattern: const [3, 2], decimalSeparator: '.',
    mainAxisAlignment: mainAxisAlignment, crossAxisAlignment: crossAxisAlignment,
    padding: padding, useTabularFigures: useTabularFigures, showPositiveSign: showPositiveSign,
    semanticsLabel: semanticsLabel, onAnimationEnd: onAnimationEnd, onAnimationStart: onAnimationStart,
    flipDirection: flipDirection, digitBuilder: digitBuilder, minValue: minValue, maxValue: maxValue,
    increasingColor: increasingColor, decreasingColor: decreasingColor,
    colorFadeDuration: colorFadeDuration, prefixWidget: prefixWidget, infixWidget: infixWidget,
    suffixWidget: suffixWidget, thousandSeparatorWidget: thousandSeparatorWidget,
    decimalSeparatorWidget: decimalSeparatorWidget, negativeSignWidget: negativeSignWidget,
    positiveSignWidget: positiveSignWidget, digitWrapperBuilder: digitWrapperBuilder,
    digitTransitionBuilder: digitTransitionBuilder, staggerDelay: staggerDelay,
    staggerDirection: staggerDirection, compactNotation: compactNotation,
    triggerHaptics: triggerHaptics, compactFractionDigits: compactFractionDigits,
    initialValue: initialValue, numeralSystem: numeralSystem, numeralMapper: numeralMapper,
    transitionType: transitionType, reverseDuration: reverseDuration, reverseCurve: reverseCurve,
    startDelay: startDelay, speedMultiplier: speedMultiplier, compactAbbreviations: compactAbbreviations,
  );

  @override
  State<AnimatedCounter> createState() => _AnimatedCounterState();
}

// 鈹€鈹€ state 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

class _AnimatedCounterState extends State<AnimatedCounter> {
  // 鈹€鈹€ ticker (replaces AnimationController) 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
  CounterHandle? _handle;
  double _currentT = 0.0;
  double _pausedT  = 0.0;
  bool _repeating  = false;

  // Repaint trigger for the persistent CounterPainter.
  // Incrementing this calls markNeedsPaint() — NO widget build cost.
  final _repaintTrigger = ValueNotifier<int>(0);

  // When n%9==0, we animate to n-1 and snap to n at onComplete.
  bool _usingAdjustedTarget = false;
  List<double> _realTargetDigitValues = [];

  // Persistent painter; updated in-place each frame instead of recreating.
  // Null until _prototypeSize is known (first build).
  CounterPainter? _activePainter;

  // Legacy notifier kept for the widget path (digitBuilder / blur / flip).
  final _rebuildNotifier = ValueNotifier<int>(0);

  // 鈹€鈹€ digit state (unchanged from original) 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
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

  // 鈹€鈹€ helpers (unchanged from original) 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

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

  /// When decreasing, flip the axis so the visual effect stays consistent
  /// (digits always exit in the "natural" direction) while the incoming
  /// digit is the next smaller value. The double-flip (flipDirection + _increasing=false)
  /// produces the same exit direction as increasing but with decreasing content.
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

  // 鈹€鈹€ init / update / dispose 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

  @override
  void initState() {
    super.initState();
    _currentValue = widget.initialValue ?? _effectiveValue;
    _lastValue    = _currentValue;

    final initialDigits = _getDigitsList(_currentValue);
    _maxDigits          = initialDigits.length;
    _oldDigitValues     = List<double>.from(initialDigits);
    _targetDigitValues  = List<double>.from(initialDigits);
    _currentDigitValues = List<double>.from(initialDigits);

    _bindController();
    widget.controller?.addListener(_handleControllerUpdate);

    if (widget.initialValue != null && widget.initialValue != _effectiveValue) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _triggerTransitionWithDelay(widget.initialValue!, _effectiveValue);
      });
    }
  }

  @override
  void didUpdateWidget(AnimatedCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_handleControllerUpdate);
      _unbindController(oldWidget.controller); // clear the OLD controller's callbacks
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

  // 鈹€鈹€ ticker binding (replaces AnimationController bindings) 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

  void _bindController() {
    final c = widget.controller;
    if (c == null) return;
    c.$pauseCallback = () {
      _pausedT = _currentT;
      _handle?.cancel();
      widget.onPause?.call();
    };
    c.$resumeCallback = () {
      _launchHandle(fromT: _pausedT);
      widget.onResume?.call();
    };
    c.$stopCallback = () { _handle?.cancel(); };
    c.$restartCallback = () {
      _launchHandle(fromT: 0);
      widget.onAnimationStart?.call();
    };
    c.$repeatCallback = ({bool reverse = false}) {
      _repeating = true;
      _launchHandle(fromT: 0);
      widget.onRepeat?.call();
    };
    c.$reverseCallback = () {
      final tmp = List<double>.from(_oldDigitValues);
      _oldDigitValues    = List<double>.from(_targetDigitValues);
      _targetDigitValues = tmp;
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

  // 鈹€鈹€ transition triggering 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

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
    // Non-finite guard: .round() throws on Infinity/NaN. Snap to 0.
    if (!oldValue.isFinite) oldValue = 0;
    if (!newValue.isFinite) newValue = 0;
    _isAnimatingDecrease = newValue < oldValue;
    widget.onAnimationStart?.call();

    final oldDigits = _getDigitsList(oldValue);
    var   animTarget = newValue;

    // n % 9 == 0 detection: numbers like 9, 99, 999, 999999999 produce
    // degenerate digit patterns (stuck visuals). Animate to n-1 so the
    // interpolation avoids the all-9 pattern, then snap to n at onComplete.
    final effFD = widget.compactNotation
        ? (widget.compactFractionDigits ?? (widget.fractionDigits == 0 ? 1 : widget.fractionDigits))
        : widget.fractionDigits;
    final scaledNew = (newValue.abs() * math.pow(10, effFD)).round();
    // All-nines (repunit) targets — 9, 99, 999, … — are the ones with the
    // degenerate pattern, NOT every multiple of 9. A value is all-nines iff
    // (value + 1) is a power of ten.
    _usingAdjustedTarget = newValue > 0 && scaledNew > 0 && isAllNinesTarget(scaledNew);

    if (_usingAdjustedTarget) {
      // Subtract the smallest representable unit (1 digit at fractionDigits place)
      animTarget = newValue - 1.0 / math.pow(10, effFD);
    }

    final targetDigits = _getDigitsList(animTarget);
    _realTargetDigitValues = List<double>.from(_getDigitsList(newValue));
    _maxDigits = math.max(oldDigits.length, targetDigits.length);

    _oldDigitValues    = [...List<double>.filled(_maxDigits - oldDigits.length, 0.0), ...oldDigits];
    _targetDigitValues = [...List<double>.filled(_maxDigits - targetDigits.length, 0.0), ...targetDigits];

    // Ensure _currentDigitValues has _maxDigits elements before build() runs,
    // so SizedBox width is computed correctly.
    _currentDigitValues = List<double>.from(_oldDigitValues);

    final isIncrease = newValue > oldValue;
    final isDecrease = newValue < oldValue;
    final targetColor = isIncrease ? widget.increasingColor
        : isDecrease ? widget.decreasingColor : null;

    if (targetColor != null) {
      _directionColor = targetColor;
      _colorAnimKey++;
    }
    _lastValue    = newValue;
    _currentValue = newValue;

    // Rebuild static wrappers (color tint key, sign widgets) once per value change.
    if (mounted) setState(() {});

    final totalDuration = _effectiveDuration;
    if (totalDuration == Duration.zero) {
      _currentT = 1.0;
      _updateCurrentDigitValues();
      _rebuildNotifier.value++;
      _onAnimStatusChange(AnimationStatus.completed);
    } else {
      // Batch size resolved from StartScheduler.instance (global or per-group).
      StartScheduler.instance.enqueue(
        () { if (mounted) _launchHandle(fromT: 0); },
        tag: this,
      ); // no group — uses defaultBatchSize
    }
  }

  /// Start (or restart) the shared-ticker handle.
  /// [fromT] allows resuming from a paused position.
  void _launchHandle({double fromT = 0}) {
    _handle?.cancel();
    _currentT = fromT;

    final totalDuration = _effectiveDuration;
    if (totalDuration == Duration.zero) return;

    // Scale remaining duration proportionally (linear time progress).
    final remaining = Duration(microseconds:
        ((1.0 - fromT) * totalDuration.inMicroseconds).round());
    if (remaining <= Duration.zero) return;

    _handle = counter(CounterOptions(
      from: fromT,
      to:   1.0,
      duration: remaining,
      curve: Curves.linear, // curve is applied inside _updateCurrentDigitValues
      onUpdate: (t) {
        _currentT = t;
        _updateCurrentDigitValues();
        // Fast path: update persistent painter + markNeedsPaint (no build).
        // Slow path (widget): increment rebuild notifier as before.
        if (_activePainter != null) {
          _activePainter!.update(_currentDigitValues, !_isAnimatingDecrease);
          _repaintTrigger.value++;
        } else {
          _rebuildNotifier.value++;
        }
      },
      onComplete: (_) {
        _currentT = 1.0;

        // Snap to real target if we used adjusted target (n%9==0 case).
        if (_activePainter != null) {
          if (_usingAdjustedTarget && _realTargetDigitValues.isNotEmpty) {
            // Snap _currentDigitValues to the real n (not the n-1 we animated to).
            final n = math.max(_realTargetDigitValues.length, _maxDigits);
            _currentDigitValues = [
              ...List<double>.filled(n - _realTargetDigitValues.length, 0.0),
              ..._realTargetDigitValues,
            ];
          }
          _activePainter!.update(_currentDigitValues, !_isAnimatingDecrease);
          _repaintTrigger.value++;
        }
        _usingAdjustedTarget = false;

        _onAnimStatusChange(AnimationStatus.completed);
        if (_repeating) {
          _repeating = false;
          _launchHandle(fromT: 0);
        }
      },
    ));
  }

  void _onAnimStatusChange(AnimationStatus status) {
    widget.controller?.$notifyStatusListeners(status);
    if (status == AnimationStatus.completed) widget.onAnimationEnd?.call();
  }

  // 鈹€鈹€ digit value computation (unchanged from original, except t source) 鈹€鈹€鈹€鈹€鈹€

  void _updateCurrentDigitValues() {
    final double t       = _currentT;
    final Curve  curve   = _effectiveCurve;
    final Duration? stagger = _effectiveStaggerDelay;

    Duration baseDuration = (widget.controller != null && widget.controller!.overrideDuration != null)
        ? widget.controller!.overrideDuration!
        : ((_isAnimatingDecrease && widget.reverseDuration != null)
            ? widget.reverseDuration! : widget.duration);
    if (baseDuration == Duration.zero) baseDuration = const Duration(microseconds: 1);

    final double baseDurationUs = baseDuration.inMicroseconds.toDouble() / widget.speedMultiplier;
    final double totalDurationUs = _effectiveDuration.inMicroseconds.toDouble();

    // Auto-ease for large number ranges when curve is linear:
    // prevents the first/last frame from jumping too far.
    // External curve (non-linear) is respected as-is.
    final double maxRange = _maxDigits > 0
        ? (_targetDigitValues.last - _oldDigitValues.last).abs()
        : 0;
    final bool autoEase = curve == Curves.linear &&
        maxRange > widget.autoEaseThreshold;
    final Curve effectiveComputeCurve =
        autoEase ? Curves.easeInOut : curve;

    _currentDigitValues = List<double>.filled(_maxDigits, 0.0);

    for (int i = 0; i < _maxDigits; i++) {
      double tDigit = t;
      if (stagger != null && stagger > Duration.zero) {
        final double staggerUs = stagger.inMicroseconds.toDouble() / widget.speedMultiplier;
        final double delayUs = switch (widget.staggerDirection) {
          StaggerDirection.leftToRight  => staggerUs * i,
          StaggerDirection.rightToLeft  => staggerUs * (_maxDigits - 1 - i),
        };
        final double elapsedUs = t * totalDurationUs;
        tDigit = ((elapsedUs - delayUs) / baseDurationUs).clamp(0.0, 1.0);
      }
      final double progress = effectiveComputeCurve.transform(tDigit);
      _currentDigitValues[i] = _oldDigitValues[i] +
          (_targetDigitValues[i] - _oldDigitValues[i]) * progress;
    }
  }

  List<double> _getDigitsList(num targetValue) {
    // Guard against NaN/Infinity: .round() throws UnsupportedError on them,
    // and .clamp() propagates NaN. Fall back to 0 for a non-finite input.
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
    if (_currentT == 0.0) return false;          // 鈫?was: _animController.value == 0.0
    final stagger = _effectiveStaggerDelay;
    if (stagger == null || stagger == Duration.zero) return true;
    final double staggerUs = stagger.inMicroseconds.toDouble() / widget.speedMultiplier;
    final double delayUs = switch (widget.staggerDirection) {
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
    _handle?.cancel();
    _activePainter?.disposeCache();
    _repaintTrigger.dispose();
    _rebuildNotifier.dispose();
    super.dispose();
  }

  // 鈹€鈹€ build 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

  @override
  Widget build(BuildContext context) {
    final baseStyle = DefaultTextStyle.of(context).style.merge(widget.textStyle);
    final style = (widget.useTabularFigures && widget.textStyle?.fontFeatures == null)
        ? baseStyle.merge(const TextStyle(fontFeatures: [FontFeature.tabularFigures()]))
        : baseStyle;
    final textScaler = MediaQuery.textScalerOf(context);

    if (_prototypeSize == null || style != _lastStyle || textScaler != _lastTextScaler) {
      _lastStyle = style; _lastTextScaler = textScaler;
      final painter = TextPainter(
        text: TextSpan(text: '0', style: style),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      _prototypeSize = painter.size;
      painter.dispose(); // one-shot measurement — release the native paragraph
    }

    final num safeCurrent = _currentValue.isFinite ? _currentValue : 0;
    final num clamped = safeCurrent.clamp(
      widget.minValue ?? double.negativeInfinity,
      widget.maxValue ?? double.infinity,
    );
    num displayValue = clamped;
    String? compactSuffix;

    final Map<num, String> abbreviations = widget.compactAbbreviations ?? {
      1e3: 'K', 1e6: 'M', 1e9: 'B', 1e12: 'T',
    };
    if (widget.compactNotation) {
      final absVal = clamped.abs();
      final sorted = abbreviations.keys.toList()..sort((a, b) => b.compareTo(a));
      for (final threshold in sorted) {
        if (absVal >= threshold) { displayValue = clamped / threshold; compactSuffix = abbreviations[threshold]; break; }
      }
    }

    final int effFD  = widget.compactNotation
        ? (widget.compactFractionDigits ?? (widget.fractionDigits == 0 ? 1 : widget.fractionDigits))
        : widget.fractionDigits;
    final int val    = (displayValue * math.pow(10, effFD)).round();
    final Color color = style.color ?? const Color(0xffff0000);

    // ── digit row: only part that rebuilds every frame ───────────────────────
    // Fast path: CustomPainter when no Widget-returning custom builders.
    //   Build cost ≈ 0ms (no widget instantiation). Covers flip too now —
    //   CounterPainter._flip() does the same rotateX perspective transform
    //   directly on Canvas (see countdown_card.dart's flip-card painter for
    //   the same technique applied to a two-half split-flap instead of a
    //   single plane).
    // Slow path: Widget tree when digitBuilder / digitTransitionBuilder
    //   provided (arbitrary widgets can't be paragraph-cached), or blur
    //   (needs ImageFiltered/saveLayer, which the Canvas path deliberately
    //   avoids elsewhere in this package).
    //   Build cost ≈ 0.85ms × numDigits (widget instantiation overhead).
    final useCustomPainter = widget.digitBuilder == null &&
        widget.digitTransitionBuilder == null &&
        widget.transitionType != CounterTransitionType.blur;

    // ── CustomPainter fast path: create / reuse persistent painter ───────────
    if (useCustomPainter) {
      final dw = _prototypeSize!.width + widget.padding.horizontal;
      final dh = _prototypeSize!.height + widget.padding.vertical;
      final n  = _currentDigitValues.length;
      final numSeps = widget.thousandSeparator != null
          ? (n - effFD - 1) ~/ (widget.groupingPattern.firstOrNull ?? 3)
          : 0;
      final totalW = n * dw + numSeps * dw * 0.4;

      // Create or recreate painter when config changes (style, transitionType…)
      // During animation the painter is reused; only its data is updated.
      if (_activePainter == null ||
          _activePainter!.style != style ||
          _activePainter!.transitionType != widget.transitionType ||
          _activePainter!.flipDirection != _effectiveFlipDirection) {
        _activePainter?.disposeCache(); // release the outgoing painter's paragraphs
        _activePainter = CounterPainter(
          repaint: _repaintTrigger,
          digitValues: _currentDigitValues,
          style: style,
          digitSize: _prototypeSize!,
          transitionType: widget.transitionType,
          flipDirection: _effectiveFlipDirection,
          increasing: !_isAnimatingDecrease,
          fractionDigits: effFD,
          groupingPattern: widget.groupingPattern,
          hideLeadingZeroes: widget.hideLeadingZeroes,
          numeralSystem: widget.numeralSystem,
          numeralMapper: widget.numeralMapper,
          thousandSeparator: widget.thousandSeparator,
          separatorStyle: widget.separatorStyle,
          padding: widget.padding,
        );
      } else {
        // Sync direction on every build so direction reversal (e.g. Reset)
        // takes effect immediately — before the first onUpdate fires.
        _activePainter!.update(_currentDigitValues, !_isAnimatingDecrease);
      }

      final painterWidget = SizedBox(
        width: totalW, height: dh,
        child: CustomPaint(painter: _activePainter),
      );
      final inner2 = widget.repaintBoundary
          ? RepaintBoundary(child: painterWidget)
          : painterWidget;

      // Color tint + semantics still wrap the painter widget
      Widget content2 = inner2;
      if (_directionColor != null) {
        final baseColor = style.color ?? const Color(0xFF000000);
        content2 = TweenAnimationBuilder<Color?>(
          key: ValueKey(_colorAnimKey),
          tween: ColorTween(begin: _directionColor, end: baseColor),
          duration: widget.colorFadeDuration,
          builder: (_, Color? c, child) =>
              DefaultTextStyle.merge(style: TextStyle(color: c), child: child!),
          child: content2,
        );
      }
      final lbl2 = widget.semanticsLabel ?? _buildSemanticLabel(val);
      return lbl2.isEmpty
          ? content2
          : Semantics(label: lbl2, child: ExcludeSemantics(child: content2));
    }

    // ── Widget slow path (digitBuilder / blur / flip) ─────────────────────
    _activePainter = null; // clear if transitioning back to widget path
    final inner = ValueListenableBuilder<int>(
        valueListenable: _rebuildNotifier,
        builder: (ctx, _, __) {
          final integerDigitCount = _currentDigitValues.length - effFD;

          // Build integer digit widgets
          final integerWidgets = <Widget>[];
          for (int i = 0; i < integerDigitCount; i++) {
            Widget digit = DigitColumn(
              key: ValueKey(_currentDigitValues.length - i),
              value: _targetDigitValues[i],
              oldValue: _oldDigitValues[i],
              animationValue: _currentDigitValues[i],
              hasStarted: _hasDigitStarted(i),
              size: _prototypeSize!,
              color: color,
              style: style,
              padding: widget.padding,
              flipDirection: _effectiveFlipDirection,
              digitBuilder: widget.digitBuilder,
              digitTransitionBuilder: widget.digitTransitionBuilder,
              triggerHaptics: widget.triggerHaptics,
              numeralSystem: widget.numeralSystem,
              numeralMapper: widget.numeralMapper,
              transitionType: widget.transitionType,
              visible: widget.hideLeadingZeroes
                  ? (_currentDigitValues[i].round() != 0 ||
                      i == integerDigitCount - 1 ||
                      _currentDigitValues.sublist(0, i).any((d) => d.round() != 0))
                  : true,
            );
            if (widget.digitWrapperBuilder != null) {
              digit = widget.digitWrapperBuilder!(ctx, i, digit);
            }
            integerWidgets.add(digit);
          }

          // Thousand separators (groupingPattern-aware)
          if (widget.thousandSeparator != null) {
            int firstVisible = 0;
            if (widget.hideLeadingZeroes) {
              firstVisible = _currentDigitValues.indexWhere((d) => d.round() != 0);
              if (firstVisible == -1) firstVisible = _currentDigitValues.length - 1;
            }
            int counter = 0, patternIdx = 0;
            int nextSepAt = widget.groupingPattern[0];
            for (int i = integerWidgets.length; i > firstVisible; i--) {
              if (counter > 0 && counter == nextSepAt) {
                integerWidgets.insert(i,
                    widget.thousandSeparatorWidget ?? Text(widget.thousandSeparator!, style: widget.separatorStyle));
                patternIdx++;
                final nextGroup = patternIdx < widget.groupingPattern.length
                    ? widget.groupingPattern[patternIdx]
                    : widget.groupingPattern.last;
                nextSepAt += nextGroup;
              }
              counter++;
            }
          }

          return DefaultTextStyle.merge(
            style: style,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: widget.mainAxisAlignment,
              crossAxisAlignment: widget.crossAxisAlignment,
              textDirection: TextDirection.ltr,
              children: [
                // Prefix
                if (widget.prefixWidget != null)
                  widget.prefixWidget!
                else if (widget.prefix != null)
                  _buildAffix(widget.prefix!, widget.prefixStyle, widget.prefixOverflow),

                // Negative sign (animated width)
                ClipRect(
                  child: TweenAnimationBuilder(
                    duration: _effectiveNegativeSignDuration,
                    tween: Tween(end: val < 0 ? 1.0 : 0.0),
                    builder: (_, double v, __) => Center(
                      widthFactor: v,
                      child: widget.negativeSignWidget != null
                          ? Opacity(opacity: v, child: widget.negativeSignWidget!)
                          : Text('-', style: TextStyle(color: color.withValues(alpha: color.a * v))),
                    ),
                  ),
                ),

                // Positive sign
                if (widget.showPositiveSign)
                  ClipRect(
                    child: TweenAnimationBuilder(
                      duration: _effectivePositiveSignDuration,
                      tween: Tween(end: val > 0 ? 1.0 : 0.0),
                      builder: (_, double v, __) => Center(
                        widthFactor: v,
                        child: widget.positiveSignWidget != null
                            ? Opacity(opacity: v, child: widget.positiveSignWidget!)
                            : Text('+', style: TextStyle(color: color.withValues(alpha: color.a * v))),
                      ),
                    ),
                  ),

                // Infix
                if (widget.infixWidget != null)
                  widget.infixWidget!
                else if (widget.infix != null)
                  _buildAffix(widget.infix!, widget.infixStyle, widget.infixOverflow),

                // Integer digits (with thousand separators)
                ...integerWidgets,

                // Decimal separator + fraction digits
                if (effFD != 0) ...[
                  widget.decimalSeparatorWidget ??
                      Text(widget.decimalSeparator, style: widget.separatorStyle),
                  for (int i = _currentDigitValues.length - effFD;
                      i < _currentDigitValues.length; i++)
                    () {
                      Widget d = DigitColumn(
                        key: ValueKey('decimal$i'),
                        value: _targetDigitValues[i],
                        oldValue: _oldDigitValues[i],
                        animationValue: _currentDigitValues[i],
                        hasStarted: _hasDigitStarted(i),
                        size: _prototypeSize!,
                        color: color,
                        style: style,
                        padding: widget.padding,
                        flipDirection: _effectiveFlipDirection,
                        digitBuilder: widget.digitBuilder,
                        digitTransitionBuilder: widget.digitTransitionBuilder,
                        triggerHaptics: widget.triggerHaptics,
                        numeralSystem: widget.numeralSystem,
                        numeralMapper: widget.numeralMapper,
                        transitionType: widget.transitionType,
                      );
                      if (widget.digitWrapperBuilder != null) {
                        d = widget.digitWrapperBuilder!(ctx, i, d);
                      }
                      return d;
                    }(),
                ],

                // Compact suffix (K/M/B/T)
                if (compactSuffix != null)
                  Text(compactSuffix, style: widget.suffixStyle ?? style),

                // Suffix
                if (widget.suffixWidget != null)
                  widget.suffixWidget!
                else if (widget.suffix != null)
                  _buildAffix(widget.suffix!, widget.suffixStyle, widget.suffixOverflow),
              ],
            ),
          ); // end widget path return
        }, // end builder
      );
    Widget content = widget.repaintBoundary ? RepaintBoundary(child: inner) : inner;

    // Color tint on increase/decrease — independent TweenAnimationBuilder
    if (_directionColor != null) {
      final baseColor = style.color ?? const Color(0xFF000000);
      content = TweenAnimationBuilder<Color?>(
        key: ValueKey(_colorAnimKey),
        tween: ColorTween(begin: _directionColor, end: baseColor),
        duration: widget.colorFadeDuration,
        builder: (_, Color? c, child) =>
            DefaultTextStyle.merge(style: TextStyle(color: c), child: child!),
        child: content,
      );
    }

    final effectiveLabel = widget.semanticsLabel ?? _buildSemanticLabel(val);
    if (effectiveLabel.isEmpty) return content;
    return Semantics(label: effectiveLabel, child: ExcludeSemantics(child: content));
  }

  Widget _buildAffix(String text, TextStyle? style, TextOverflow? overflow) {
    final w = Text(text, style: style, overflow: overflow);
    return overflow != null ? Flexible(child: w) : w;
  }

  String _buildSemanticLabel(int intValue) {
    final absValue = intValue.abs() / math.pow(10, widget.fractionDigits);
    final negative = intValue < 0;
    final sign = negative ? '-' : (widget.showPositiveSign && intValue > 0 ? '+' : '');
    return '$sign${absValue.toStringAsFixed(widget.fractionDigits)}';
  }
}




