// Adapted from flip_counter_plus (MIT).
// Original: https://github.com/Itsxhadi/flip_counter_plus
//
// Change from original:
//   CounterTransitionType.roll: replaced Positioned with Transform.translate
//   + ClipRect so digit transitions run on the GPU compositor layer with no
//   layout pass per frame.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'types.dart';

class DigitColumn extends StatefulWidget {
  final double value;
  final double oldValue;
  final double animationValue;
  final bool hasStarted;
  final Size size;
  final Color color;
  final TextStyle style;
  final EdgeInsets padding;
  final bool visible;
  final AxisDirection flipDirection;
  final Widget Function(BuildContext context, int digit, TextStyle style)? digitBuilder;
  final Widget Function(
    BuildContext context,
    Widget currentDigit,
    Widget nextDigit,
    double progress,
    Size size,
  )? digitTransitionBuilder;
  final bool triggerHaptics;
  final NumeralSystem numeralSystem;
  final String Function(int digit)? numeralMapper;
  final CounterTransitionType transitionType;

  /// Fast mode: this column does a SINGLE step from [fastFromDigit] to
  /// [fastToDigit] (one slot of movement), with [animationValue] carrying the
  /// 0–1 progress. Off (default): [animationValue] is a continuous odometer
  /// position and the column rolls floor → floor+1 through every intermediate.
  ///
  /// 快速模式：本列从 [fastFromDigit] 单步位移到 [fastToDigit]（一个身位），
  /// [animationValue] 携带 0–1 进度。关闭（默认）：[animationValue] 为连续里程表
  /// 位置，逐位 floor → floor+1 滚过所有中间位。
  final bool fast;
  final int fastFromDigit;
  final int fastToDigit;

  const DigitColumn({
    super.key,
    required this.value,
    required this.oldValue,
    required this.animationValue,
    required this.hasStarted,
    required this.size,
    required this.color,
    required this.style,
    required this.padding,
    required this.numeralSystem,
    this.numeralMapper,
    required this.transitionType,
    this.visible = true,
    this.flipDirection = AxisDirection.up,
    this.digitBuilder,
    this.digitTransitionBuilder,
    required this.triggerHaptics,
    this.fast = false,
    this.fastFromDigit = 0,
    this.fastToDigit = 0,
  });

  @override
  State<DigitColumn> createState() => _DigitColumnState();
}

class _DigitColumnState extends State<DigitColumn> {
  int? _lastHapticValue;

  @override
  Widget build(BuildContext context) {
    if (widget.triggerHaptics) {
      final rounded = widget.animationValue.round();
      if (_lastHapticValue == null) {
        _lastHapticValue = rounded;
      } else if (rounded != _lastHapticValue) {
        _lastHapticValue = rounded;
        HapticFeedback.selectionClick();
      }
    }

    // Resolve (current digit, next digit, 0–1 progress) once; the transition
    // switch below is direction/mode-agnostic and just consumes them.
    // Fast mode = a single step fromDigit → toDigit; normal = odometer roll
    // where the next digit is always the current + 1.
    //
    // 一次解析（当前位、下一位、0–1 进度）；下方过渡 switch 与模式无关，只消费它们。
    // 快速模式 = 从 fromDigit 到 toDigit 单步；普通模式 = 里程表滚动，下一位恒为当前 +1。
    final int curDigit;
    final int nextDigit;
    final double decimal;
    if (widget.fast) {
      curDigit = widget.fastFromDigit;
      nextDigit = widget.fastToDigit;
      // Unchanged digit → stay static (progress 0) instead of sliding X→X.
      decimal = curDigit == nextDigit ? 0.0 : widget.animationValue.clamp(0.0, 1.0);
    } else {
      final whole = widget.animationValue ~/ 1;
      decimal = widget.animationValue - whole;
      curDigit = (whole % 10).toInt();
      nextDigit = ((whole + 1) % 10).toInt();
    }
    final w = widget.size.width  + widget.padding.horizontal;
    final h = widget.size.height + widget.padding.vertical;

    if (!widget.visible) return SizedBox(width: 0, height: h);

    final currentDigitWidget = _buildSingleDigit(
      context: context, digit: curDigit, opacity: 1 - decimal, style: widget.style,
    );
    final nextDigitWidget = _buildSingleDigit(
      context: context, digit: nextDigit, opacity: decimal, style: widget.style,
    );

    final Widget transitionChild;

    if (widget.digitTransitionBuilder != null) {
      transitionChild = widget.digitTransitionBuilder!(
        context, currentDigitWidget, nextDigitWidget, decimal, widget.size,
      );
    } else {
      switch (widget.transitionType) {
        case CounterTransitionType.fade:
          transitionChild = Stack(alignment: Alignment.center, children: [
            currentDigitWidget, nextDigitWidget,
          ]);

        case CounterTransitionType.scale:
          transitionChild = Stack(alignment: Alignment.center, children: [
            Transform.scale(scale: (1.0 - decimal).clamp(0.0, 1.0), child: currentDigitWidget),
            Transform.scale(scale: decimal.clamp(0.0, 1.0), child: nextDigitWidget),
          ]);

        case CounterTransitionType.fadeScale:
          transitionChild = Stack(alignment: Alignment.center, children: [
            Transform.scale(scale: (1.0 - 0.2 * decimal).clamp(0.0, 1.0), child: currentDigitWidget),
            Transform.scale(scale: (0.8 + 0.2 * decimal).clamp(0.0, 1.0), child: nextDigitWidget),
          ]);

        case CounterTransitionType.rotate:
          transitionChild = Stack(alignment: Alignment.center, children: [
            Transform.rotate(angle: -decimal * math.pi / 2, child: currentDigitWidget),
            Transform.rotate(angle: (1.0 - decimal) * math.pi / 2, child: nextDigitWidget),
          ]);

        // ⚠️  flip uses Matrix4 perspective (setEntry 3,2) → GPU compositing layer.
        case CounterTransitionType.flip:
          final angle = decimal * math.pi;
          transitionChild = Stack(alignment: Alignment.center, children: [
            if (decimal < 0.5)
              Transform(
                transform: Matrix4.identity()..setEntry(3, 2, 0.002)..rotateX(-angle),
                alignment: Alignment.center,
                child: currentDigitWidget,
              )
            else
              Transform(
                transform: Matrix4.identity()..setEntry(3, 2, 0.002)..rotateX(math.pi - angle),
                alignment: Alignment.center,
                child: nextDigitWidget,
              ),
          ]);

        // ⚠️  blur triggers ImageFiltered → saveLayer every frame.
        // Avoid for multiple simultaneous instances in production.
        case CounterTransitionType.blur:
          final blurAmount = (0.5 - (decimal - 0.5).abs()) * 8.0;
          Widget stack = Stack(alignment: Alignment.center, children: [
            currentDigitWidget, nextDigitWidget,
          ]);
          if (blurAmount > 0.1) {
            stack = ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: blurAmount, sigmaY: blurAmount),
              child: stack,
            );
          }
          transitionChild = stack;

        // ── roll: Transform.translate replaces Positioned ──────────────────
        // Positioned triggers a layout pass every frame.
        // Transform.translate is a post-layout compositor operation — zero
        // layout cost. ClipRect bounds the slide within the digit slot.
        case CounterTransitionType.roll:
          final isHorizontal = widget.flipDirection == AxisDirection.left ||
              widget.flipDirection == AxisDirection.right;

          if (isHorizontal) {
            transitionChild = ClipRect(
              child: SizedBox(width: w, height: h,
                child: Stack(children: [
                  Transform.translate(
                    offset: Offset(_currentOffset(w, decimal) + widget.padding.left, 0),
                    child: currentDigitWidget,
                  ),
                  Transform.translate(
                    offset: Offset(_nextOffset(w, decimal) + widget.padding.left, 0),
                    child: nextDigitWidget,
                  ),
                ]),
              ),
            );
          } else {
            // Vertical roll.
            // Original used Positioned(bottom: offset) inside a Stack.
            // Equivalent Transform.translate offsets (y axis, sign inverted
            // because Transform.translate uses top-down coords):
            //   current: moves "out" in the exit direction as decimal → 1
            //   next:    arrives from the entry direction as decimal → 1
            transitionChild = ClipRect(
              child: SizedBox(width: w, height: h,
                child: Stack(children: [
                  Transform.translate(
                    offset: Offset(0, -_currentOffset(h, decimal) - widget.padding.bottom),
                    child: currentDigitWidget,
                  ),
                  Transform.translate(
                    offset: Offset(0, -_nextOffset(h, decimal) - widget.padding.bottom),
                    child: nextDigitWidget,
                  ),
                ]),
              ),
            );
          }
      }
    }

    return SizedBox(width: w, height: h, child: transitionChild);
  }

  // Offset helpers — unchanged from original.
  double _currentOffset(double sizeValue, double decimal) {
    switch (widget.flipDirection) {
      case AxisDirection.up:
      case AxisDirection.right:
        return sizeValue * decimal;
      case AxisDirection.down:
      case AxisDirection.left:
        return -(sizeValue * decimal);
    }
  }

  double _nextOffset(double sizeValue, double decimal) {
    switch (widget.flipDirection) {
      case AxisDirection.up:
      case AxisDirection.right:
        return sizeValue * decimal - sizeValue;
      case AxisDirection.down:
      case AxisDirection.left:
        return sizeValue * (1 - decimal);
    }
  }

  Widget _buildSingleDigit({
    required BuildContext context,
    required int digit,
    required double opacity,
    required TextStyle style,
  }) {
    if (widget.digitBuilder != null) {
      return Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: widget.digitBuilder!(context, digit, style),
      );
    }
    final targetAlpha = widget.color.a * opacity.clamp(0.0, 1.0);
    final String digitStr = widget.numeralMapper != null
        ? widget.numeralMapper!(digit)
        : (numeralSystemDigits[widget.numeralSystem]?[digit] ?? '$digit');
    return Text(
      digitStr,
      textAlign: TextAlign.center,
      style: TextStyle(color: widget.color.withValues(alpha: targetAlpha)),
    );
  }
}

