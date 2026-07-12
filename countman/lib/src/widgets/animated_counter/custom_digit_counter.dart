part of 'animated_counter.dart';

// ── widget ────────────────────────────────────────────────────────────────────

/// Animated rolling-digit counter using Flutter's widget tree.
///
/// Use this when you need [digitBuilder] or [digitTransitionBuilder] to render
/// each digit as an arbitrary widget. For the common case — styled text digits —
/// prefer [AnimatedCounter], which uses [CustomPainter] with zero build cost
/// per animation frame.
class AnimatedCounterBuilder extends _BaseAnimatedCounter {
  /// Builds a custom widget for each digit (0–9).
  /// Called with the digit's integer value and the resolved text style.
  final Widget Function(BuildContext context, int digit, TextStyle style)? digitBuilder;

  /// Fully custom transition between [currentDigit] and [nextDigit].
  /// [progress] is the fractional animation position within this column (0–1).
  final Widget Function(
    BuildContext context,
    Widget currentDigit,
    Widget nextDigit,
    double progress,
    Size size,
  )? digitTransitionBuilder;

  /// Wraps each [DigitColumn] after it is built, indexed left-to-right.
  final Widget Function(BuildContext context, int index, Widget child)? digitWrapperBuilder;

  const AnimatedCounterBuilder({
    super.key,
    super.value,
    super.controller,
    super.duration,
    super.negativeSignDuration,
    super.curve,
    super.textStyle,
    super.prefix,
    super.infix,
    super.suffix,
    super.fractionDigits,
    super.wholeDigits,
    super.hideLeadingZeroes,
    super.thousandSeparator,
    super.groupingPattern,
    super.decimalSeparator,
    super.separatorStyle,
    super.mainAxisAlignment,
    super.crossAxisAlignment,
    super.padding,
    super.useTabularFigures,
    super.prefixStyle,
    super.infixStyle,
    super.suffixStyle,
    super.prefixOverflow,
    super.infixOverflow,
    super.suffixOverflow,
    super.showPositiveSign,
    super.positiveSignDuration,
    super.semanticsLabel,
    super.onAnimationEnd,
    super.onAnimationStart,
    super.flipDirection,
    super.minValue,
    super.maxValue,
    super.increasingColor,
    super.decreasingColor,
    super.colorFadeDuration,
    super.prefixWidget,
    super.infixWidget,
    super.suffixWidget,
    super.thousandSeparatorWidget,
    super.decimalSeparatorWidget,
    super.negativeSignWidget,
    super.positiveSignWidget,
    super.staggerDelay,
    super.staggerDirection,
    super.compactNotation,
    super.triggerHaptics,
    super.compactFractionDigits,
    super.initialValue,
    super.numeralSystem,
    super.numeralMapper,
    super.transitionType,
    super.reverseDuration,
    super.reverseCurve,
    super.startDelay,
    super.speedMultiplier,
    super.compactAbbreviations,
    super.onPause,
    super.onResume,
    super.onReset,
    super.onRepeat,
    super.onReverse,
    super.repaintBoundary,
    super.autoEaseThreshold,
    super.curveForDigit,
    super.colorResolver,
    super.interpolation,
    super.bounceOvershoot,
    super.bounceElasticity,
    super.style,
    this.digitBuilder,
    this.digitTransitionBuilder,
    this.digitWrapperBuilder,
  });

  @override
  State<AnimatedCounterBuilder> createState() => _AnimatedCounterBuilderState();
}

// ── state ─────────────────────────────────────────────────────────────────────

class _AnimatedCounterBuilderState extends _BaseCounterState<AnimatedCounterBuilder> {
  final _rebuildNotifier = ValueNotifier<int>(0);

  // ── frame hooks ───────────────────────────────────────────────────────────

  @override
  void _onFrameUpdate() => _rebuildNotifier.value++;

  @override
  void _onAnimationComplete() => _rebuildNotifier.value++;

  @override
  void dispose() {
    _rebuildNotifier.dispose();
    super.dispose();
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final style      = _resolveStyle(context);
    final textScaler = MediaQuery.textScalerOf(context);
    _updatePrototypeSize(style, textScaler);

    final effFD = _effectiveFractionDigits();
    final num safeCurrent = _currentValue.isFinite ? _currentValue : 0;
    final num clamped = safeCurrent.clamp(
      widget.minValue ?? double.negativeInfinity,
      widget.maxValue ?? double.infinity,
    );
    num displayValue = clamped;
    String? compactSuffix;
    if (widget.compactNotation) {
      final abbreviations = widget.compactAbbreviations ?? {1e3: 'K', 1e6: 'M', 1e9: 'B', 1e12: 'T'};
      final sorted = abbreviations.keys.toList()..sort((a, b) => b.compareTo(a));
      for (final t in sorted) {
        if (clamped.abs() >= t) { displayValue = clamped / t; compactSuffix = abbreviations[t]; break; }
      }
    }
    final int   val   = (displayValue * math.pow(10, effFD)).round();
    final Color color = style.color ?? const Color(0xffff0000);

    final inner = ValueListenableBuilder<int>(
      valueListenable: _rebuildNotifier,
      builder: (ctx, _, __) {
        final integerDigitCount = _currentDigitValues.length - effFD;

        // ── integer digits ────────────────────────────────────────────────
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

        // ── thousand separators ───────────────────────────────────────────
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
                  widget.thousandSeparatorWidget ??
                      Text(widget.thousandSeparator!, style: widget.separatorStyle));
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

              // Positive sign (animated width)
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
        );
      },
    );

    Widget content = widget.repaintBoundary ? RepaintBoundary(child: inner) : inner;
    content = _wrapColorTint(content, style.color ?? const Color(0xFF000000));
    return _wrapSemantics(content, widget.semanticsLabel ?? _buildSemanticText(val));
  }
}
