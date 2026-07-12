// OdometerCounter — sliding-digit counter driven by a persistent CustomPainter.
//
// Replaced the external `odometer` package with a painter that is updated
// in-place each frame via markNeedsPaint(). Zero widget rebuilds per frame.
//
// Visual behaviour:
//   • Ones digit transitions smoothly (fractional progress).
//   • Higher digits snap at integer carry boundaries.
//   • Increasing: old digit exits UPWARD, new arrives from below.
//   • Decreasing: old exits DOWNWARD, new arrives from above.
//     (Direction is fixed once per segment and matches AnimatedCounter:
//      increase → up, decrease → down.)
//   • Optional bounce: each ones-digit transition briefly overshoots the target
//     then springs back, direction-aware.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:countman/src/counter/plugin.dart';

import 'reduce_motion.dart';
import 'style_support.dart';
import 'providers.dart';
import 'animated_counter/animated_counter.dart';

/// Visual style for [OdometerCounter].
///
/// Groups digit text style, slot geometry, per-affix styling, and container
/// [decoration]/[padding]. All fields nullable; unset fields fall back to the
/// deprecated loose params then framework defaults.
///
/// [OdometerCounter] 的视觉样式。聚合数字文本样式、槽位几何、前后缀样式、容器
/// [decoration]/[padding]。所有字段可空；未设置回退到弃用松散参数再到框架默认值。
@immutable
class OdometerCounterStyle with BoxStyleFields, StyleProps {
  /// Creates a [OdometerCounter] style. All fields optional.
  ///
  /// 创建 [OdometerCounter] 样式。所有字段可选。
  const OdometerCounterStyle({
    this.numberTextStyle,
    this.letterWidth,
    this.verticalOffset,
    this.fadeEnabled,
    this.digitAlignment,
    this.crossAxisAlignment,
    this.prefixStyle,
    this.suffixStyle,
    this.padding,
    this.decoration,
  });

  /// Text style for the digits.
  final TextStyle? numberTextStyle;

  /// Fixed width per digit slot.
  final double? letterWidth;

  /// Vertical slide distance in logical pixels.
  final double? verticalOffset;

  /// Cross-fade incoming/outgoing digits.
  final bool? fadeEnabled;

  /// Alignment of each digit within its slot.
  final Alignment? digitAlignment;

  /// Cross-axis alignment of the number row (and prefix/suffix).
  final CrossAxisAlignment? crossAxisAlignment;

  /// Text style for the prefix string (falls back to [numberTextStyle]).
  final TextStyle? prefixStyle;

  /// Text style for the suffix string (falls back to [numberTextStyle]).
  final TextStyle? suffixStyle;

  @override
  final EdgeInsetsGeometry? padding;
  @override
  final Decoration? decoration;

  /// Returns a copy with the given fields replaced.
  ///
  /// 返回替换了给定字段的副本。
  OdometerCounterStyle copyWith({
    TextStyle? numberTextStyle,
    double? letterWidth,
    double? verticalOffset,
    bool? fadeEnabled,
    Alignment? digitAlignment,
    CrossAxisAlignment? crossAxisAlignment,
    TextStyle? prefixStyle,
    TextStyle? suffixStyle,
    EdgeInsetsGeometry? padding,
    Decoration? decoration,
  }) =>
      OdometerCounterStyle(
        numberTextStyle: numberTextStyle ?? this.numberTextStyle,
        letterWidth: letterWidth ?? this.letterWidth,
        verticalOffset: verticalOffset ?? this.verticalOffset,
        fadeEnabled: fadeEnabled ?? this.fadeEnabled,
        digitAlignment: digitAlignment ?? this.digitAlignment,
        crossAxisAlignment: crossAxisAlignment ?? this.crossAxisAlignment,
        prefixStyle: prefixStyle ?? this.prefixStyle,
        suffixStyle: suffixStyle ?? this.suffixStyle,
        padding: padding ?? this.padding,
        decoration: decoration ?? this.decoration,
      );

  /// Merges with lower-priority [other]: this object's non-null fields win.
  ///
  /// 与更低优先级的 [other] 合并：本对象非空字段优先。
  OdometerCounterStyle merge(OdometerCounterStyle? other) => other == null
      ? this
      : OdometerCounterStyle(
          numberTextStyle: numberTextStyle ?? other.numberTextStyle,
          letterWidth: letterWidth ?? other.letterWidth,
          verticalOffset: verticalOffset ?? other.verticalOffset,
          fadeEnabled: fadeEnabled ?? other.fadeEnabled,
          digitAlignment: digitAlignment ?? other.digitAlignment,
          crossAxisAlignment: crossAxisAlignment ?? other.crossAxisAlignment,
          prefixStyle: prefixStyle ?? other.prefixStyle,
          suffixStyle: suffixStyle ?? other.suffixStyle,
          padding: padding ?? other.padding,
          decoration: decoration ?? other.decoration,
        );

  @override
  List<Object?> get props => [
        numberTextStyle,
        letterWidth,
        verticalOffset,
        fadeEnabled,
        digitAlignment,
        crossAxisAlignment,
        prefixStyle,
        suffixStyle,
        padding,
        decoration,
      ];
}

/// A sliding-digit "odometer" counter. Now a thin preset over
/// [AnimatedCounter] with [CounterTransition.slide] and odometer defaults
/// (fixed-width leading zeros). The previous standalone painter was removed —
/// [AnimatedCounter]'s slide is the same look — so most rendering knobs are
/// inherited from it.
///
/// Retained-but-inert (source compatibility only): [plugin], [controller],
/// [slideCurve], [onUpdate], [onReady], [onCancel], and the
/// [OdometerCounterStyle.letterWidth] / `verticalOffset` / `fadeEnabled`
/// fields. Prefer [AnimatedCounter] directly for full control.
///
/// 滑动数位「里程表」计数器。现为 [AnimatedCounter] 的薄预设（[CounterTransition.slide]
/// + 里程表默认值：固定位宽前导零）。独立 painter 已移除（AnimatedCounter 的 slide 是
/// 同款外观），故大部分渲染参数继承自它。
///
/// 保留但失效（仅为源码兼容）：[plugin]、[controller]、[slideCurve]、[onUpdate]、
/// [onReady]、[onCancel]，以及 [OdometerCounterStyle] 的 letterWidth / verticalOffset /
/// fadeEnabled 字段。需要完全控制请直接用 [AnimatedCounter]。
class OdometerCounter extends StatelessWidget {
  /// Creates an odometer counter animating [from] → [to].
  ///
  /// 创建一个从 [from] 动画到 [to] 的里程表计数器。
  const OdometerCounter({
    super.key,
    this.from,
    required this.to,
    this.duration = const Duration(milliseconds: 1000),
    this.curve = Curves.easeOut,
    this.allowNegative = false,
    this.plugin,
    this.controller,
    this.style,
    this.slideCurve,
    this.groupSeparator,
    this.prefix,
    this.suffix,
    this.prefixWidget,
    this.suffixWidget,
    this.onUpdate,
    this.onComplete,
    this.onReady,
    this.onStart,
    this.onCancel,
    this.bounceOvershoot = 0.0,
    this.bounceElasticity = 4.0,
  })  : assert(bounceOvershoot >= 0.0),
        assert(bounceElasticity >= 1.0);

  /// Start value (default 0).
  ///
  /// 起始值（默认 0）。
  final double? from;

  /// Target value.
  ///
  /// 目标值。
  final double to;

  /// Animation duration.
  ///
  /// 动画时长。
  final Duration duration;

  /// Easing curve.
  ///
  /// 缓动曲线。
  final Curve curve;

  /// When `false` (default) the value never goes below 0.
  ///
  /// 为 `false`（默认）时数值不会低于 0。
  final bool allowNegative;

  /// Inert (source compatibility only).
  ///
  /// 失效（仅源码兼容）。
  final Counter? plugin;

  /// Inert (source compatibility only).
  ///
  /// 失效（仅源码兼容）。
  final CounterValueController? controller;

  /// Visual style. Merged over the enclosing [CounterProvider]'s odometer
  /// style, then built-in defaults.
  ///
  /// 视觉样式。叠加在所在 [CounterProvider] 的 odometer 样式之上，再到内建默认值。
  final OdometerCounterStyle? style;

  /// Inert (source compatibility only).
  ///
  /// 失效（仅源码兼容）。
  final Curve? slideCurve;

  /// Text drawn between every 3 digits (e.g. `','`).
  ///
  /// 每 3 位之间绘制的文本（如 `','`）。
  final String? groupSeparator;

  /// Prefix string.
  ///
  /// 前缀字符串。
  final String? prefix;

  /// Suffix string.
  ///
  /// 后缀字符串。
  final String? suffix;

  /// Prefix widget (wins over [prefix]).
  ///
  /// 前缀组件（优先于 [prefix]）。
  final Widget? prefixWidget;

  /// Suffix widget (wins over [suffix]).
  ///
  /// 后缀组件（优先于 [suffix]）。
  final Widget? suffixWidget;

  /// Inert (source compatibility only).
  ///
  /// 失效（仅源码兼容）。
  final void Function(double value)? onUpdate;

  /// Called once the animation reaches [to].
  ///
  /// 动画到达 [to] 时回调一次。
  final void Function(double value)? onComplete;

  /// Inert (source compatibility only).
  ///
  /// 失效（仅源码兼容）。
  final VoidCallback? onReady;

  /// Called when the animation starts.
  ///
  /// 动画开始时回调。
  final VoidCallback? onStart;

  /// Inert (source compatibility only).
  ///
  /// 失效（仅源码兼容）。
  final VoidCallback? onCancel;

  /// Per-digit settle overshoot (`0.0` disables). See [AnimatedCounter].
  ///
  /// 逐位落定过冲（`0.0` 关闭）。见 [AnimatedCounter]。
  final double bounceOvershoot;

  /// Overshoot peak timing (≥ 1). See [AnimatedCounter].
  ///
  /// 过冲峰值时机（≥ 1）。见 [AnimatedCounter]。
  final double bounceElasticity;

  @override
  Widget build(BuildContext context) {
    // Style: this widget's style over the enclosing provider's odometer style.
    //
    // 样式：本组件样式叠加在所在 provider 的 odometer 样式之上。
    final scope = CountmanScope.maybeOf<Counter>(context);
    final st = style?.merge(scope?.odometerCounterStyle) ?? scope?.odometerCounterStyle;

    // Fixed-width leading zeros — the mechanical-odometer look. Width = digit
    // count of the larger endpoint.
    //
    // 固定位宽前导零——机械里程表外观。位宽 = 较大端点的位数。
    final int maxAbs = math.max((from ?? 0).abs(), to.abs()).floor();
    final int wholeDigits = maxAbs == 0 ? 1 : maxAbs.toString().length;

    final Widget counter = AnimatedCounter(
      initialValue: from ?? 0,
      value: to,
      // Honor the OS "reduce motion" flag, like CounterBuilder / CardCountdown.
      //
      // 遵循系统「减弱动态」标志，与 CounterBuilder / CardCountdown 一致。
      duration: motionDuration(duration),
      curve: curve,
      transition: CounterTransition.slide,
      minValue: allowNegative ? null : 0,
      wholeDigits: wholeDigits,
      hideLeadingZeroes: false,
      thousandSeparator: groupSeparator,
      prefix: prefix,
      suffix: suffix,
      prefixWidget: prefixWidget,
      suffixWidget: suffixWidget,
      bounceOvershoot: bounceOvershoot,
      bounceElasticity: bounceElasticity,
      onAnimationStart: onStart,
      onAnimationEnd: onComplete == null ? null : () => onComplete!(to),
      style: AnimatedCounterStyle(
        textStyle: st?.numberTextStyle,
        numberAlignment: st?.digitAlignment?.x ?? 0.0,
        // Forward per-affix + cross-axis styling (previously silently dropped).
        //
        // 转发前后缀 + 交叉轴样式（此前被静默丢弃）。
        prefixStyle: st?.prefixStyle,
        suffixStyle: st?.suffixStyle,
        crossAxisAlignment: st?.crossAxisAlignment,
      ),
    );

    // Container-level padding / decoration from the style.
    //
    // 来自样式的容器级 padding / decoration。
    return applyBoxStyle(counter, padding: st?.padding, decoration: st?.decoration);
  }
}
