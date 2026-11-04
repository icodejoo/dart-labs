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

  /// 创建计数器；[format] 的非空字段覆盖同名平铺参数，空字段回退。
  /// [timeline] 的非空字段同样覆盖同名平铺动画参数，空字段回退。
  ///
  /// 示例：`AnimatedCounterBuilder(value: 12, format: CounterFormat(fractionDigits: 2))`。
  /// 动画示例：`AnimatedCounterBuilder(value: 12, timeline: CounterTimeline(fast: true))`。
  const AnimatedCounterBuilder({
    super.format,
    super.timeline,
    super.key,
    super.value,
    super.controller,
    super.plugin,
    super.animateOnce,
    @Deprecated('改用 timeline: CounterTimeline(duration: ...)')
    super.duration,
    super.negativeSignDuration,
    @Deprecated('改用 timeline: CounterTimeline(curve: ...)')
    super.curve,
    @Deprecated('改用 style: AnimatedCounterStyle(textStyle: ...)')
    super.textStyle,
    super.prefix,
    super.infix,
    super.suffix,
    @Deprecated('改用 format: CounterFormat(fractionDigits: ...)')
    super.fractionDigits,
    @Deprecated('改用 format: CounterFormat(wholeDigits: ...)')
    super.wholeDigits,
    @Deprecated('改用 format: CounterFormat(hideLeadingZeroes: ...)')
    super.hideLeadingZeroes,
    @Deprecated('改用 format: CounterFormat(thousandSeparator: ...)')
    super.thousandSeparator,
    @Deprecated('改用 format: CounterFormat(groupingPattern: ...)')
    super.groupingPattern,
    @Deprecated('改用 format: CounterFormat(decimalSeparator: ...)')
    super.decimalSeparator,
    @Deprecated('改用 style: AnimatedCounterStyle(separatorStyle: ...)')
    super.separatorStyle,
    @Deprecated('改用 style: AnimatedCounterStyle(mainAxisAlignment: ...)')
    super.mainAxisAlignment,
    @Deprecated('改用 style: AnimatedCounterStyle(crossAxisAlignment: ...)')
    super.crossAxisAlignment,
    @Deprecated('改用 style: AnimatedCounterStyle(padding: ...)')
    super.padding,
    @Deprecated('改用 style: AnimatedCounterStyle(useTabularFigures: ...)')
    super.useTabularFigures,
    @Deprecated('改用 style: AnimatedCounterStyle(prefixStyle: ...)')
    super.prefixStyle,
    @Deprecated('改用 style: AnimatedCounterStyle(infixStyle: ...)')
    super.infixStyle,
    @Deprecated('改用 style: AnimatedCounterStyle(suffixStyle: ...)')
    super.suffixStyle,
    super.prefixOverflow,
    super.infixOverflow,
    super.suffixOverflow,
    @Deprecated('改用 format: CounterFormat(showPositiveSign: ...)')
    super.showPositiveSign,
    super.positiveSignDuration,
    super.semanticsLabel,
    super.onAnimationEnd,
    super.onAnimationStart,
    super.flipDirection,
    super.minValue,
    super.maxValue,
    @Deprecated('改用 style: AnimatedCounterStyle(increasingColor: ...)')
    super.increasingColor,
    @Deprecated('改用 style: AnimatedCounterStyle(decreasingColor: ...)')
    super.decreasingColor,
    @Deprecated('改用 style: AnimatedCounterStyle(colorFadeDuration: ...)')
    super.colorFadeDuration,
    super.prefixWidget,
    super.infixWidget,
    super.suffixWidget,
    super.thousandSeparatorWidget,
    super.decimalSeparatorWidget,
    super.negativeSignWidget,
    super.positiveSignWidget,
    @Deprecated('改用 timeline: CounterTimeline(staggerDelay: ...)')
    super.staggerDelay,
    @Deprecated('改用 timeline: CounterTimeline(staggerDirection: ...)')
    super.staggerDirection,
    @Deprecated('改用 format: CounterFormat(compactNotation: ...)')
    super.compactNotation,
    super.triggerHaptics,
    @Deprecated('改用 format: CounterFormat(compactFractionDigits: ...)')
    super.compactFractionDigits,
    super.initialValue,
    @Deprecated('改用 format: CounterFormat(numeralSystem: ...)')
    super.numeralSystem,
    @Deprecated('改用 format: CounterFormat(numeralMapper: ...)')
    super.numeralMapper,
    super.transition,
    @Deprecated('改用 timeline: CounterTimeline(reverseDuration: ...)')
    super.reverseDuration,
    @Deprecated('改用 timeline: CounterTimeline(reverseCurve: ...)')
    super.reverseCurve,
    @Deprecated('改用 timeline: CounterTimeline(startDelay: ...)')
    super.startDelay,
    @Deprecated('改用 timeline: CounterTimeline(speedMultiplier: ...)')
    super.speedMultiplier,
    @Deprecated('改用 format: CounterFormat(compactAbbreviations: ...)')
    super.compactAbbreviations,
    super.onPause,
    super.onResume,
    super.onReset,
    super.onRepeat,
    super.onReverse,
    super.repaintBoundary,
    @Deprecated('改用 timeline: CounterTimeline(autoEaseThreshold: ...)')
    super.autoEaseThreshold,
    @Deprecated('改用 timeline: CounterTimeline(curveForDigit: ...)')
    super.curveForDigit,
    super.colorResolver,
    @Deprecated('改用 timeline: CounterTimeline(interpolation: ...)')
    super.interpolation,
    @Deprecated('改用 timeline: CounterTimeline(bounceOvershoot: ...)')
    super.bounceOvershoot,
    // 仅保留旧参数的源码兼容性。
    @Deprecated('No effect; use bounceOvershoot instead')
    super.bounceElasticity,
    @Deprecated('改用 timeline: CounterTimeline(fast: ...)')
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

/// 按数位通知重建的自定义组件渲染路径。
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

  /// 两条路径共用端点可见性和量化颜色；仅数字子树逐帧更新。
  @override
  Widget build(BuildContext context) {
    final style      = _resolveStyle(context);
    final textScaler = MediaQuery.textScalerOf(context);
    _updatePrototypeSize(style, textScaler);

    // 与动画端点共用格式计算，避免符号、缩写和小数位分叉。
    final display = _displayNumber(_currentValue);
    final effFD = display.fractionDigits;
    final val = display.scaledValue;
    final compactSuffix = display.suffix;
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
        final color = _digitTint ?? style.color ?? const Color(0xFF000000);
        final digitStyle = _digitStyleFor(style);
        final integerDigitCount = _engine.currentDigits.length - effFD;

        // In fast mode _engine.currentDigits carries progress (not magnitude), so
        // leading-zero visibility must read the endpoint digits instead.
        //
        // 快速模式下 _engine.currentDigits 携带进度（非磁量），故隐藏前导零需改读端点位。
        bool digitNonZero(int j) => widget._timeFast
            ? ((_currentT < 1 && j < _engine.fastFromDigits.length && _engine.fastFromDigits[j] != 0) ||
                (j < _engine.fastToDigits.length && _engine.fastToDigits[j] != 0))
            : _engine.currentDigits[j].round() != 0;

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
          if (!widget._fmtHideLeadingZeroes) {
            vis = true;
            reveal = 1.0;
          } else if (widget._timeFast) {
            vis = nzI || isLast || anySigBefore;
            reveal = 1.0;
          } else {
            final double cum = _engine.currentDigits[i];
            vis = isLast || cum > _kLeadingRevealEps;
            reveal = isLast ? 1.0 : cum.clamp(0.0, 1.0);
          }
          Widget digit = DigitColumn(
            key: ValueKey(_engine.currentDigits.length - i),
            value: _engine.targetDigits[i],
            oldValue: _engine.oldDigits[i],
            animationValue: _engine.currentDigits[i],
            size: _prototypeSize!,
            color: color,
            style: digitStyle,
            padding: widget.padding,
            flipDirection: _effectiveFlipDirection,
            digitBuilder: widget.digitBuilder,
            digitTransitionBuilder: widget.digitTransitionBuilder,
            triggerHaptics: widget.triggerHaptics,
            numeralSystem: widget._fmtNumeralSystem,
            numeralMapper: widget._fmtNumeralMapper,
            transition: widget.transition,
            fast: widget._timeFast,
            fastFromDigit: i < _engine.fastFromDigits.length ? _engine.fastFromDigits[i] : 0,
            fastToDigit: i < _engine.fastToDigits.length ? _engine.fastToDigits[i] : 0,
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
        if (widget._fmtThousandSeparator != null) {
          int firstVisible = 0;
          if (widget._fmtHideLeadingZeroes) {
            firstVisible = -1;
            for (var j = 0; j < integerDigitCount; j++) {
              if (digitNonZero(j)) { firstVisible = j; break; }
            }
            if (firstVisible == -1) firstVisible = _engine.currentDigits.length - 1;
          }
          // 从右插入，保持左侧索引稳定；边界算法与 Painter 共用。
          for (int i = integerDigitCount - 1; i > firstVisible; i--) {
            if (isGroupingBoundary(integerDigitCount - i, widget._fmtGroupingPattern)) {
              integerWidgets.insert(i,
                  widget.thousandSeparatorWidget ??
                      Text(widget._fmtThousandSeparator!, style: widget.separatorStyle));
            }
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
                        // 自定义符号可能包含图片等任意内容，无法用文字颜色 alpha 表达，因此例外使用 Opacity。
                        ? Opacity(opacity: v, child: widget.negativeSignWidget!)
                        : Text('-', style: TextStyle(color: color.withValues(alpha: color.a * v))),
                  ),
                ),
              ),

              // Positive sign (animated width)
              if (widget._fmtShowPositiveSign)
                ClipRect(
                  child: TweenAnimationBuilder(
                    duration: _effectivePositiveSignDuration,
                    tween: Tween(end: val > 0 ? 1.0 : 0.0),
                    builder: (_, double v, __) => Center(
                      widthFactor: v,
                      child: widget.positiveSignWidget != null
                          // 自定义符号可能包含图片等任意内容，无法用文字颜色 alpha 表达，因此例外使用 Opacity。
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
                    Text(widget._fmtDecimalSeparator, style: widget.separatorStyle),
                for (int i = _engine.currentDigits.length - effFD;
                    i < _engine.currentDigits.length; i++)
                  () {
                    Widget d = DigitColumn(
                      key: ValueKey('decimal$i'),
                      value: _engine.targetDigits[i],
                      oldValue: _engine.oldDigits[i],
                      animationValue: _engine.currentDigits[i],
                      size: _prototypeSize!,
                      color: color,
                      style: digitStyle,
                      padding: widget.padding,
                      flipDirection: _effectiveFlipDirection,
                      digitBuilder: widget.digitBuilder,
                      digitTransitionBuilder: widget.digitTransitionBuilder,
                      triggerHaptics: widget.triggerHaptics,
                      numeralSystem: widget._fmtNumeralSystem,
                      numeralMapper: widget._fmtNumeralMapper,
                      transition: widget.transition,
                      fast: widget._timeFast,
                      fastFromDigit: i < _engine.fastFromDigits.length ? _engine.fastFromDigits[i] : 0,
                      fastToDigit: i < _engine.fastToDigits.length ? _engine.fastToDigits[i] : 0,
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
    return _wrapOnce(_wrapSemantics(content, widget.semanticsLabel ?? _buildSemanticText(val)));
  }
}
