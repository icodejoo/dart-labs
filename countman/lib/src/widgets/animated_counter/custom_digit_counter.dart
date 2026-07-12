part of 'animated_counter.dart';

/// Below this cumulative place value a normal-mode leading column counts as
/// "not yet reached" (collapsed); above it the column is shown and its opacity
/// ramps `cum → 1` for a fade-in.
///
/// 低于此累计位值，普通模式的前导列视为"尚未到达"（收起）；高于则显示，其不透明度按
/// `cum → 1` 渐变实现淡入。
const double _kLeadingRevealEps = 1e-3;

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
    super.transition,
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
    super.fast,
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
    // Digit tint: explicit style color -> ambient DefaultTextStyle color -> black.
    // (Aligns with AnimatedCounter; was a hardcoded red that read like a bug.)
    //
    // 数字着色：显式样式色 -> 环境 DefaultTextStyle 色 -> 黑色。
    // （与 AnimatedCounter 对齐；原为硬编码红色，看起来像 bug。）
    final Color color =
        style.color ?? DefaultTextStyle.of(context).style.color ?? const Color(0xFF000000);

    final inner = ValueListenableBuilder<int>(
      valueListenable: _rebuildNotifier,
      builder: (ctx, _, __) {
        final integerDigitCount = _currentDigitValues.length - effFD;

        // In fast mode _currentDigitValues carries progress (not magnitude), so
        // leading-zero visibility must read the endpoint digits instead.
        //
        // 快速模式下 _currentDigitValues 携带进度（非磁量），故隐藏前导零需改读端点位。
        bool digitNonZero(int j) => widget.fast
            ? ((j < _fastFromDigits.length && _fastFromDigits[j] != 0) ||
                (j < _fastToDigits.length && _fastToDigits[j] != 0))
            : _currentDigitValues[j].round() != 0;

        // ── integer digits ────────────────────────────────────────────────
        final integerWidgets = <Widget>[];
        // Running "any earlier column significant" flag — replaces a per-column
        // List.generate(i).any(...) that was O(n²) allocations per frame.
        //
        // 累进的「更高位有非零」标志——取代原来逐列 List.generate(i).any(...) 的
        // 每帧 O(n²) 分配。
        bool anySigBefore = false;
        for (int i = 0; i < integerDigitCount; i++) {
          final bool isLast = i == integerDigitCount - 1;
          final bool nzI = digitNonZero(i);
          // Leading-zero handling.
          //   • !hideLeadingZeroes → always shown, full opacity.
          //   • fast → binary (progress carries no magnitude); keep the old
          //     endpoint-based visibility.
          //   • normal → live cumulative place value: collapse a place still at
          //     ~0, fade it in (opacity = cum) while it grows into view, full
          //     once cum ≥ 1. Hides leading zeros at rest (e.g. 1000 → 7 → "7").
          //
          // 前导零处理：
          //   • !hideLeadingZeroes → 始终显示，全不透明。
          //   • fast → 二值（进度不含幅值），沿用旧的端点可见性。
          //   • 普通 → 用实时累计位值：仍约为 0 的位收起，随其增长淡入（opacity = cum），
          //     cum ≥ 1 后全显。静止时隐藏前导零（如 1000 → 7 → "7"）。
          final bool vis;
          final double reveal;
          if (!widget.hideLeadingZeroes) {
            vis = true;
            reveal = 1.0;
          } else if (widget.fast) {
            vis = nzI || isLast || anySigBefore;
            reveal = 1.0;
          } else {
            final double cum = _currentDigitValues[i];
            vis = isLast || cum > _kLeadingRevealEps;
            reveal = isLast ? 1.0 : cum.clamp(0.0, 1.0);
          }
          Widget digit = DigitColumn(
            key: ValueKey(_currentDigitValues.length - i),
            value: _targetDigitValues[i],
            oldValue: _oldDigitValues[i],
            animationValue: _currentDigitValues[i],
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
            transition: widget.transition,
            fast: widget.fast,
            fastFromDigit: i < _fastFromDigits.length ? _fastFromDigits[i] : 0,
            fastToDigit: i < _fastToDigits.length ? _fastToDigits[i] : 0,
            increasing: !_isAnimatingDecrease,
            visible: vis,
            revealAlpha: reveal,
            bounceOffset: i < _bounceOffsets.length ? _bounceOffsets[i] : 0.0,
          );
          if (widget.digitWrapperBuilder != null) {
            digit = widget.digitWrapperBuilder!(ctx, i, digit);
          }
          integerWidgets.add(digit);
          anySigBefore = anySigBefore || nzI;
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
                      transition: widget.transition,
                      fast: widget.fast,
                      fastFromDigit: i < _fastFromDigits.length ? _fastFromDigits[i] : 0,
                      fastToDigit: i < _fastToDigits.length ? _fastToDigits[i] : 0,
                      increasing: !_isAnimatingDecrease,
                      bounceOffset: i < _bounceOffsets.length ? _bounceOffsets[i] : 0.0,
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
    content = _wrapColorTint(content, color);
    return _wrapSemantics(content, widget.semanticsLabel ?? _buildSemanticText(val));
  }
}
