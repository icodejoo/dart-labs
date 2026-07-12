// Adapted from flip_counter_plus (MIT).
// Original: https://github.com/Itsxhadi/flip_counter_plus
//
// Change from original:
//   CounterTransition.slide: replaced Positioned with Transform.translate
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
  final CounterTransition transition;

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

  /// Global animation direction, fixed before the transition runs: `true` =
  /// increasing (digits roll up, next = cur + 1), `false` = decreasing (roll
  /// down, next = cur − 1). Only consulted in normal (non-[fast]) mode; must
  /// match the sign the parent used to build [animationValue]'s trajectory.
  ///
  /// 全局动画方向，在过渡开始前定好：`true` = 递增（数位向上滚，下一位 = 当前 + 1），
  /// `false` = 递减（向下滚，下一位 = 当前 − 1）。仅普通（非 [fast]）模式使用；
  /// 必须与父级构造 [animationValue] 轨迹时所用的方向一致。
  final bool increasing;

  /// Opacity for a leading place that is fading into view as the number grows
  /// into it (normal mode, `hideLeadingZeroes`). `1.0` = fully shown. Lets a
  /// newly-significant digit fade in instead of popping at full opacity.
  ///
  /// 前导位随数字增长淡入时的不透明度（普通模式，`hideLeadingZeroes`）。`1.0` = 完全
  /// 显示。让新变得有效的数位淡入，而非以全不透明突现。
  final double revealAlpha;

  /// Post-animation bounce nudge as a fraction of digit height (0 = none). The
  /// digit is pinned to its target (progress 0) and slid by this fraction in
  /// the motion direction, then back — no adjacent digit shown.
  ///
  /// 动画后回弹轻推，按数位高度的比例（0 = 无）。数位钉在目标（进度 0），沿运动方向
  /// 滑动该比例再返回——不显示相邻数位。
  final double bounceOffset;

  const DigitColumn({
    super.key,
    required this.value,
    required this.oldValue,
    required this.animationValue,
    required this.size,
    required this.color,
    required this.style,
    required this.padding,
    required this.numeralSystem,
    this.numeralMapper,
    required this.transition,
    this.visible = true,
    this.flipDirection = AxisDirection.up,
    this.digitBuilder,
    this.digitTransitionBuilder,
    required this.triggerHaptics,
    this.fast = false,
    this.fastFromDigit = 0,
    this.fastToDigit = 0,
    this.increasing = true,
    this.revealAlpha = 1.0,
    this.bounceOffset = 0.0,
  });

  @override
  State<DigitColumn> createState() => _DigitColumnState();
}

class _DigitColumnState extends State<DigitColumn> {
  int? _lastHapticValue;

  /// Reused each build by [resolveDigitPhase] so no per-frame record is
  /// allocated on the widget-tree path.
  ///
  /// 每次 build 由 [resolveDigitPhase] 复用，使组件树路径不逐帧分配 record。
  final DigitPhase _phase = DigitPhase();

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

    // Resolve (current digit, next digit, 0–1 progress) via the shared
    // odometer helper — same math the painter path uses — so the transition
    // switch below stays direction/mode-agnostic and just consumes them.
    //
    // 经共享里程表 helper 解析（当前位、下一位、0–1 进度）——与 painter 路径同一套
    // 数学——故下方过渡 switch 与方向/模式无关，只消费它们。
    resolveDigitPhase(
      _phase,
      fast: widget.fast,
      fastFrom: widget.fastFromDigit,
      fastTo: widget.fastToDigit,
      position: widget.animationValue,
      increasing: widget.increasing,
      targetDigit: widget.value.toInt().abs() % 10,
      target: widget.value,
      hasTarget: !widget.fast,
    );
    final int curDigit = _phase.cur;
    final int nextDigit = _phase.nxt;
    double decimal = _phase.p;
    final w = widget.size.width  + widget.padding.horizontal;
    final h = widget.size.height + widget.padding.vertical;

    if (!widget.visible) return SizedBox(width: 0, height: h);

    // fade modifier: bake the cross-fade opacity into the two digits (else full
    // opacity). scale/motion/blur are composed below, mirroring the painter.
    //
    // fade 修饰：把交叉淡入不透明度写入两个数位（否则全不透明）。scale/运动/blur 在下方
    // 组合，与 painter 对齐。
    final double curOp = widget.transition.fade ? (1 - decimal).clamp(0.0, 1.0) : 1.0;
    final double nxtOp = widget.transition.fade ? decimal.clamp(0.0, 1.0) : 1.0;
    Widget currentDigitWidget = _buildSingleDigit(
      context: context, digit: curDigit, opacity: curOp, style: widget.style,
    );
    Widget nextDigitWidget = _buildSingleDigit(
      context: context, digit: nextDigit, opacity: nxtOp, style: widget.style,
    );

    Widget transitionChild;

    if (widget.digitTransitionBuilder != null) {
      transitionChild = widget.digitTransitionBuilder!(
        context, currentDigitWidget, nextDigitWidget, decimal, widget.size,
      );
    } else {
      // scale modifier: shrink the leaving digit / grow the arriving one.
      if (widget.transition.scale) {
        currentDigitWidget = Transform.scale(
            scale: (1.0 - decimal).clamp(0.0, 1.0), child: currentDigitWidget);
        nextDigitWidget = Transform.scale(
            scale: decimal.clamp(0.0, 1.0), child: nextDigitWidget);
      }

      switch (widget.transition.motion) {
        case CounterMotion.none:
          transitionChild = Stack(alignment: Alignment.center,
              children: [currentDigitWidget, nextDigitWidget]);

        case CounterMotion.rotate:
          transitionChild = Stack(alignment: Alignment.center, children: [
            Transform.rotate(angle: -decimal * math.pi / 2, child: currentDigitWidget),
            Transform.rotate(angle: (1.0 - decimal) * math.pi / 2, child: nextDigitWidget),
          ]);

        case CounterMotion.flip:
          {
            // ⚠️ Matrix4 perspective (setEntry 3,2) → GPU compositing layer.
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
          }

        // ── slide: Transform.translate (post-layout compositor op, zero layout
        // cost); ClipRect bounds the slide within the digit slot. ──────────────
        case CounterMotion.slide:
          {
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

      // blur modifier: ⚠️ ImageFiltered → saveLayer every frame; avoid many
      // simultaneous instances in production.
      if (widget.transition.blur) {
        final blurAmount = (0.5 - (decimal - 0.5).abs()) * 8.0;
        if (blurAmount > 0.1) {
          transitionChild = ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: blurAmount, sigmaY: blurAmount),
            child: transitionChild,
          );
        }
      }
    }

    Widget box = SizedBox(width: w, height: h, child: transitionChild);
    if (widget.bounceOffset != 0.0) {
      // Nudge the resting digit in the motion direction (up for up/right flip,
      // down otherwise), clipped to the slot; progress is 0 so only the target
      // digit shows.
      //
      // 沿运动方向轻推静止数位（up/right 翻转向上，否则向下），裁剪到槽内；进度为 0，
      // 故只显示目标数位。
      final double sign = (widget.flipDirection == AxisDirection.up ||
              widget.flipDirection == AxisDirection.right)
          ? -1.0
          : 1.0;
      box = ClipRect(
        child: Transform.translate(
          offset: Offset(0, widget.bounceOffset * h * sign),
          child: box,
        ),
      );
    }
    if (widget.revealAlpha < 1.0) {
      box = Opacity(opacity: widget.revealAlpha.clamp(0.0, 1.0), child: box);
    }
    return box;
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

