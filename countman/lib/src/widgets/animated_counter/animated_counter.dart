// AnimatedCounter — digit-rolling widget backed entirely by CustomPainter.
//
// Architecture: three files form one Dart library via `part`/`part of`:
//   animated_counter.dart    — library root; AnimatedCounter + state
//   _base_counter.dart       — _BaseAnimatedCounter + _BaseCounterState (shared engine)
//   custom_digit_counter.dart — AnimatedCounterBuilder + state (widget-tree path)
//
// Fast path (this file):
//   Every animation frame calls _activePainter.update() + markNeedsPaint().
//   Zero widget builds during animation — paint() is the only cost.
//   Static decorations (prefix/suffix/signs) are wrapped in a Row that
//   rebuilds only once per value change (on setState), not per frame.
//
// Widget-tree path (custom_digit_counter.dart):
//   Use AnimatedCounterBuilder when you need digitBuilder / digitTransitionBuilder.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:countman/src/counter/plugin.dart';
import 'package:countman/src/counter/types.dart';
import 'package:countman/src/core/start_scheduler.dart';

import '../painter/counter_painter.dart';
import 'counter_controller.dart';
import 'digit_column.dart';
import 'types.dart';
import '../style_support.dart';

export 'counter_controller.dart';
export 'types.dart';

part '_base_counter.dart';
part 'custom_digit_counter.dart';
part 'animated_counter_style.dart';

// ── all-nines detection ───────────────────────────────────────────────────────

/// True when [n] consists entirely of 9s (9, 99, 999, …): `(n + 1)` is a power
/// of ten. Used to detect targets where digit interpolation stalls, animating
/// to `n − ε` instead and snapping at completion.
@visibleForTesting
bool isAllNinesTarget(int n) {
  if (n < 9) return false;
  var m = n + 1;
  while (m % 10 == 0) { m ~/= 10; }
  return m == 1;
}

// ── widget ────────────────────────────────────────────────────────────────────

/// Animated rolling-digit counter backed by [CustomPainter].
///
/// Every animation frame updates the persistent [CounterPainter] in-place and
/// calls `markNeedsPaint()` — zero widget builds during animation.
/// Static decorations (prefix, suffix, signs) are rendered in a lightweight
/// [Row] that rebuilds only once per value change.
///
/// For custom per-digit widgets or transition builders use [AnimatedCounterBuilder].
class AnimatedCounter extends _BaseAnimatedCounter {
  /// Optional factory for a custom [CounterPainter] subclass.
  final CounterPainterBuilder? painterBuilder;

  const AnimatedCounter({
    super.key,
    super.style,
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
    super.numberAlignment,
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
    this.painterBuilder,
  });


  @override
  State<AnimatedCounter> createState() => _AnimatedCounterState();
}

// ── state ─────────────────────────────────────────────────────────────────────

class _AnimatedCounterState extends _BaseCounterState<AnimatedCounter> {
  final _repaintTrigger = ValueNotifier<int>(0);
  CounterPainter? _activePainter;
  int _lastHapticHash = 0;

  // ── frame hooks ───────────────────────────────────────────────────────────

  @override
  void _onFrameUpdate() {
    _activePainter?.update(_currentDigitValues, !_isAnimatingDecrease,
        bounceOffsets: _bounceOffsets,
        fast: widget.fast, fastFrom: _fastFromDigits, fastTo: _fastToDigits,
        targets: _targetDigitValues);
    _repaintTrigger.value++;
    if (widget.triggerHaptics) _maybeHaptic();
  }

  @override
  void _onAnimationComplete() {
    _activePainter?.update(_currentDigitValues, !_isAnimatingDecrease,
        bounceOffsets: _bounceOffsets,
        fast: widget.fast, fastFrom: _fastFromDigits, fastTo: _fastToDigits,
        targets: _targetDigitValues);
    _repaintTrigger.value++;
  }

  void _maybeHaptic() {
    final hash = Object.hashAll(_currentDigitValues.map((v) => v.round()));
    if (hash != _lastHapticHash) {
      _lastHapticHash = hash;
      HapticFeedback.selectionClick();
    }
  }

  @override
  void dispose() {
    _activePainter?.disposeCache();
    _repaintTrigger.dispose();
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
    final num clamped     = safeCurrent.clamp(
      widget.minValue ?? double.negativeInfinity,
      widget.maxValue ?? double.infinity,
    );
    num displayValue  = clamped;
    String? compactSuffix;
    if (widget.compactNotation) {
      final abbr   = widget.compactAbbreviations ?? {1e3: 'K', 1e6: 'M', 1e9: 'B', 1e12: 'T'};
      final sorted = abbr.keys.toList()..sort((a, b) => b.compareTo(a));
      for (final t in sorted) {
        if (clamped.abs() >= t) { displayValue = clamped / t; compactSuffix = abbr[t]; break; }
      }
    }
    final int   val   = (displayValue * math.pow(10, effFD)).round();
    // Digit tint: explicit style color → ambient DefaultTextStyle color → black.
    // (Was a hardcoded red, which read like a bug when no color was set.)
    //
    // 数字着色：显式样式色 → 环境 DefaultTextStyle 色 → 黑色。
    // （原为硬编码红色，未设色时看起来像 bug。）
    final Color color = style.color ??
        DefaultTextStyle.of(context).style.color ??
        const Color(0xFF000000);
    final dh          = _prototypeSize!.height + widget.padding.vertical;

    // ── painter: create or reuse in-place ──────────────────────────────────
    // Pass the RAW flipDirection (not _effectiveFlipDirection). The painter's
    // exitDirection() already flips the roll by _increasing; feeding it the
    // pre-flipped direction would cancel that out and make decreases roll the
    // wrong way (up). Raw direction also means no per-reversal recreation —
    // direction changes flow through update(_increasing) alone.
    //
    // 传入原始 flipDirection（而非 _effectiveFlipDirection）。painter 的
    // exitDirection() 已按 _increasing 翻转滚动方向；若再喂入预翻转的方向会互相抵消，
    // 使递减朝错误方向（向上）滚动。用原始方向还能免去每次反向时重建 painter——
    // 方向变化只经由 update(_increasing) 流转。
    if (_activePainter == null ||
        _activePainter!.style         != style ||
        _activePainter!.transition != widget.transition ||
        _activePainter!.flipDirection  != widget.flipDirection) {
      _activePainter?.disposeCache();
      _activePainter = widget.painterBuilder != null
          ? widget.painterBuilder!(
              repaint: _repaintTrigger,
              digitValues: _currentDigitValues,
              style: style,
              digitSize: _prototypeSize!,
              transition: widget.transition,
              flipDirection: widget.flipDirection,
              increasing: !_isAnimatingDecrease,
              fractionDigits: effFD,
              groupingPattern: widget.groupingPattern,
              hideLeadingZeroes: widget.hideLeadingZeroes,
              numeralSystem: widget.numeralSystem,
              numeralMapper: widget.numeralMapper,
              thousandSeparator: widget.thousandSeparator,
              decimalSeparator: widget.decimalSeparator,
              separatorStyle: widget.separatorStyle,
              padding: widget.padding,
              numberAlignment: widget.numberAlignment,
            )
          : CounterPainter(
              repaint: _repaintTrigger,
              digitValues: _currentDigitValues,
              style: style,
              digitSize: _prototypeSize!,
              transition: widget.transition,
              flipDirection: widget.flipDirection,
              increasing: !_isAnimatingDecrease,
              fractionDigits: effFD,
              groupingPattern: widget.groupingPattern,
              hideLeadingZeroes: widget.hideLeadingZeroes,
              numeralSystem: widget.numeralSystem,
              numeralMapper: widget.numeralMapper,
              thousandSeparator: widget.thousandSeparator,
              decimalSeparator: widget.decimalSeparator,
              separatorStyle: widget.separatorStyle,
              padding: widget.padding,
              numberAlignment: widget.numberAlignment,
              fast: widget.fast,
              fastFrom: _fastFromDigits,
              fastTo: _fastToDigits,
              targets: _targetDigitValues,
            );
    } else {
      // Sync direction on every build so a direction reversal takes effect
      // immediately — before the first onUpdate fires.
      _activePainter!.update(_currentDigitValues, !_isAnimatingDecrease,
          bounceOffsets: _bounceOffsets,
          fast: widget.fast, fastFrom: _fastFromDigits, fastTo: _fastToDigits,
          targets: _targetDigitValues);
    }

    // computeFullWidth() counts ALL n digit slots (ignores hideLeadingZeroes)
    // so the SizedBox stays stable width throughout animation — digits don't
    // shift off-center when leading zeros appear/disappear mid-animation.
    final totalW = _activePainter!.computeFullWidth();

    Widget digitBox = SizedBox(
      width: totalW, height: dh,
      child: CustomPaint(painter: _activePainter),
    );
    if (widget.repaintBoundary) digitBox = RepaintBoundary(child: digitBox);

    // ── decoration Row (built once per value change, not per frame) ─────────
    // Included only when at least one decoration is needed; pure digit
    // counters skip the Row entirely and return the SizedBox directly.
    final bool needsRow = val < 0 ||
        widget.prefix        != null || widget.prefixWidget   != null ||
        widget.suffix        != null || widget.suffixWidget   != null ||
        widget.infix         != null || widget.infixWidget    != null ||
        widget.showPositiveSign      || compactSuffix         != null;

    Widget content;
    if (!needsRow) {
      content = digitBox;
    } else {
      content = DefaultTextStyle.merge(
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
              child: TweenAnimationBuilder<double>(
                duration: _effectiveNegativeSignDuration,
                tween: Tween(begin: 0.0, end: val < 0 ? 1.0 : 0.0),
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
                child: TweenAnimationBuilder<double>(
                  duration: _effectivePositiveSignDuration,
                  tween: Tween(begin: 0.0, end: val > 0 ? 1.0 : 0.0),
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

            // The digit columns (painter, zero rebuild cost per frame)
            digitBox,

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
    }

    content = _wrapColorTint(
        content, style.color ?? DefaultTextStyle.of(context).style.color ?? const Color(0xFF000000));
    return _wrapSemantics(content, widget.semanticsLabel ?? _buildSemanticText(val));
  }
}
