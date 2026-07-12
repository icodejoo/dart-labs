import 'dart:math' as math;
import 'package:flutter/widgets.dart';

import 'painter/ring_painter.dart';
import 'style_support.dart';

/// Shared visual-field contract for [CounterRingStyle] / [CountdownRingStyle].
///
/// Declares every ring appearance knob as an abstract getter so the two
/// independent style classes reuse one field set and one painter builder
/// ([ringPainterFrom]) without duplicating the drawing wiring.
///
/// [CounterRingStyle] / [CountdownRingStyle] 共享的视觉字段契约。把每个环形外观项
/// 声明为抽象 getter，使两个独立样式类复用同一字段集与同一画笔构建器
/// （[ringPainterFrom]），无需重复绘制接线。
mixin RingStyleFields {
  /// Logical pixel size (both width and height — the ring is square).
  ///
  /// 逻辑像素尺寸（宽高相同——环形为正方形）。
  double? get size;

  /// Progress arc stroke width.
  ///
  /// 进度弧描边宽度。
  double? get strokeWidth;

  /// Track stroke width. Falls back to [strokeWidth].
  ///
  /// 轨道描边宽度。回退到 [strokeWidth]。
  double? get trackStrokeWidth;

  /// Arc color. Falls back to provider then theme primary.
  ///
  /// 弧颜色。回退到 provider，再到主题 primary。
  Color? get color;

  /// Track color. Falls back to provider then a muted theme color.
  ///
  /// 轨道颜色。回退到 provider，再到淡色主题色。
  Color? get trackColor;

  /// Arc gradient, overriding [color].
  ///
  /// 弧渐变，覆盖 [color]。
  Gradient? get gradient;

  /// Track gradient, overriding [trackColor].
  ///
  /// 轨道渐变，覆盖 [trackColor]。
  Gradient? get trackGradient;

  /// Angle (radians) the arc starts from. Default 12 o'clock (`-pi/2`).
  ///
  /// 弧起始角（弧度）。默认 12 点方向（`-pi/2`）。
  double? get startAngle;

  /// Cap at the arc ends.
  ///
  /// 弧端点样式。
  StrokeCap? get strokeCap;

  /// Arc direction; true = clockwise.
  ///
  /// 弧方向；true = 顺时针。
  bool? get clockwise;

  /// Total angular span (radians). `< 2*pi` makes a partial-arc gauge.
  ///
  /// 总角跨度（弧度）。`< 2*pi` 得到部分弧仪表盘。
  double? get sweepAngle;

  /// Whether the background track is drawn.
  ///
  /// 是否绘制背景轨道。
  bool? get showTrack;

  /// Solid fill of the disc behind the ring.
  ///
  /// 环形背后圆盘的实心填充。
  Color? get backgroundColor;

  /// Alignment of the [center] child within the ring. Default: center.
  ///
  /// [center] 子组件在环内的对齐。默认居中。
  AlignmentGeometry? get centerAlignment;

  /// Whether a filled "thumb" dot rides the arc's moving edge. Defaults on for
  /// `CountdownRing` (makes slow depletion visibly move), off for `CounterRing`.
  ///
  /// 是否在弧的移动边缘显示实心"游标"圆点。`CountdownRing` 默认开（让缓慢递减明显
  /// 在动），`CounterRing` 默认关。
  bool? get showThumb;

  /// Thumb fill color. Falls back to the arc color.
  ///
  /// 游标填充色。回退到弧色。
  Color? get thumbColor;

  /// Thumb radius. Falls back to `strokeWidth * 0.7`.
  ///
  /// 游标半径。回退到 `strokeWidth * 0.7`。
  double? get thumbRadius;
}

/// Builds a [RingPainter] from a resolved style, given the current [progress]
/// and the theme-resolved [color] / [trackColor] fallbacks.
///
/// 依据已解析样式、当前 [progress] 及主题解析后的 [color]/[trackColor] 回退值，
/// 构建一个 [RingPainter]。
///
/// @param s The resolved ring style fields.
///
///   已解析的环形样式字段。
///
/// @param progress Current 0–1 fill fraction.
///
///   当前 0–1 填充比例。
///
/// @param color Theme-resolved arc color fallback.
///
///   主题解析后的弧颜色回退值。
///
/// @param trackColor Theme-resolved track color fallback.
///
///   主题解析后的轨道颜色回退值。
///
/// @returns A configured [RingPainter].
///
///   配置好的 [RingPainter]。
RingPainter ringPainterFrom(
  RingStyleFields s, {
  required double progress,
  required Color color,
  required Color trackColor,
  EdgeInsets arcInset = EdgeInsets.zero,
  bool anchorAtEnd = false,
  StrokeCap defaultStrokeCap = StrokeCap.round,
  bool defaultShowThumb = false,
}) {
  return RingPainter(
    progress: progress,
    color: color,
    trackColor: trackColor,
    strokeWidth: s.strokeWidth ?? 8.0,
    trackStrokeWidth: s.trackStrokeWidth,
    clockwise: s.clockwise ?? true,
    startAngle: s.startAngle ?? -math.pi / 2,
    strokeCap: s.strokeCap ?? defaultStrokeCap,
    anchorAtEnd: anchorAtEnd,
    showThumb: s.showThumb ?? defaultShowThumb,
    thumbColor: s.thumbColor,
    thumbRadius: s.thumbRadius,
    gradient: s.gradient,
    trackGradient: s.trackGradient,
    // Ring-internal inset (distinct from the container [BoxStyleFields.padding],
    // which is applied via applyBoxStyle around the whole widget).
    //
    // 环内缩进（区别于容器 [BoxStyleFields.padding]——后者经 applyBoxStyle 应用于
    // 整个 widget 外围）。
    padding: arcInset,
    sweepAngle: s.sweepAngle ?? 2 * math.pi,
    showTrack: s.showTrack ?? true,
    backgroundColor: s.backgroundColor,
  );
}

/// Visual style for the ring displays — shared by `CounterRing` and
/// `CountdownRing` (see the [CounterRingStyle] / [CountdownRingStyle] aliases).
///
/// Groups every ring appearance knob (geometry, colors, gradients, arc span,
/// track visibility, background fill, container decoration) into one reusable,
/// themeable, mergeable object. All fields nullable; unset fields fall back to
/// the provider then to framework defaults.
///
/// 环形显示组件的视觉样式——由 `CounterRing` 与 `CountdownRing` 共用
/// （见 [CounterRingStyle] / [CountdownRingStyle] 别名）。
///
/// 把每个环形外观项（几何、颜色、渐变、弧跨度、轨道可见性、背景填充、容器装饰）
/// 聚合为一个可复用、可主题化、可合并的对象。所有字段可空；未设置的字段回退到
/// provider，再回退到框架默认值。
@immutable
class RingStyle with BoxStyleFields, RingStyleFields, StyleProps {
  /// Creates a ring style. All fields optional.
  ///
  /// 创建环形样式。所有字段可选。
  const RingStyle({
    this.size,
    this.strokeWidth,
    this.trackStrokeWidth,
    this.color,
    this.trackColor,
    this.gradient,
    this.trackGradient,
    this.startAngle,
    this.strokeCap,
    this.clockwise,
    this.sweepAngle,
    this.showTrack,
    this.backgroundColor,
    this.centerAlignment,
    this.showThumb,
    this.thumbColor,
    this.thumbRadius,
    this.padding,
    this.decoration,
  });

  @override
  final double? size;
  @override
  final double? strokeWidth;
  @override
  final double? trackStrokeWidth;
  @override
  final Color? color;
  @override
  final Color? trackColor;
  @override
  final Gradient? gradient;
  @override
  final Gradient? trackGradient;
  @override
  final double? startAngle;
  @override
  final StrokeCap? strokeCap;
  @override
  final bool? clockwise;
  @override
  final double? sweepAngle;
  @override
  final bool? showTrack;
  @override
  final Color? backgroundColor;
  @override
  final AlignmentGeometry? centerAlignment;
  @override
  final bool? showThumb;
  @override
  final Color? thumbColor;
  @override
  final double? thumbRadius;
  @override
  final EdgeInsetsGeometry? padding;
  @override
  final Decoration? decoration;

  /// Returns a copy with the given fields replaced.
  ///
  /// 返回替换了给定字段的副本。
  RingStyle copyWith({
    double? size,
    double? strokeWidth,
    double? trackStrokeWidth,
    Color? color,
    Color? trackColor,
    Gradient? gradient,
    Gradient? trackGradient,
    double? startAngle,
    StrokeCap? strokeCap,
    bool? clockwise,
    double? sweepAngle,
    bool? showTrack,
    Color? backgroundColor,
    AlignmentGeometry? centerAlignment,
    bool? showThumb,
    Color? thumbColor,
    double? thumbRadius,
    EdgeInsetsGeometry? padding,
    Decoration? decoration,
  }) =>
      RingStyle(
        size: size ?? this.size,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        trackStrokeWidth: trackStrokeWidth ?? this.trackStrokeWidth,
        color: color ?? this.color,
        trackColor: trackColor ?? this.trackColor,
        gradient: gradient ?? this.gradient,
        trackGradient: trackGradient ?? this.trackGradient,
        startAngle: startAngle ?? this.startAngle,
        strokeCap: strokeCap ?? this.strokeCap,
        clockwise: clockwise ?? this.clockwise,
        sweepAngle: sweepAngle ?? this.sweepAngle,
        showTrack: showTrack ?? this.showTrack,
        backgroundColor: backgroundColor ?? this.backgroundColor,
        centerAlignment: centerAlignment ?? this.centerAlignment,
        showThumb: showThumb ?? this.showThumb,
        thumbColor: thumbColor ?? this.thumbColor,
        thumbRadius: thumbRadius ?? this.thumbRadius,
        padding: padding ?? this.padding,
        decoration: decoration ?? this.decoration,
      );

  /// Merges with lower-priority [other]: this object's non-null fields win.
  ///
  /// 与更低优先级的 [other] 合并：本对象非空字段优先。
  RingStyle merge(RingStyle? other) => other == null
      ? this
      : RingStyle(
          size: size ?? other.size,
          strokeWidth: strokeWidth ?? other.strokeWidth,
          trackStrokeWidth: trackStrokeWidth ?? other.trackStrokeWidth,
          color: color ?? other.color,
          trackColor: trackColor ?? other.trackColor,
          gradient: gradient ?? other.gradient,
          trackGradient: trackGradient ?? other.trackGradient,
          startAngle: startAngle ?? other.startAngle,
          strokeCap: strokeCap ?? other.strokeCap,
          clockwise: clockwise ?? other.clockwise,
          sweepAngle: sweepAngle ?? other.sweepAngle,
          showTrack: showTrack ?? other.showTrack,
          backgroundColor: backgroundColor ?? other.backgroundColor,
          centerAlignment: centerAlignment ?? other.centerAlignment,
          showThumb: showThumb ?? other.showThumb,
          thumbColor: thumbColor ?? other.thumbColor,
          thumbRadius: thumbRadius ?? other.thumbRadius,
          padding: padding ?? other.padding,
          decoration: decoration ?? other.decoration,
        );

  @override
  List<Object?> get props => [
        size,
        strokeWidth,
        trackStrokeWidth,
        color,
        trackColor,
        gradient,
        trackGradient,
        startAngle,
        strokeCap,
        clockwise,
        sweepAngle,
        showTrack,
        backgroundColor,
        centerAlignment,
        showThumb,
        thumbColor,
        thumbRadius,
        padding,
        decoration,
      ];
}

/// Visual style for `CounterRing`. Alias of the shared [RingStyle].
///
/// `CounterRing` 的视觉样式。共享 [RingStyle] 的别名。
typedef CounterRingStyle = RingStyle;

/// Visual style for `CountdownRing`. Alias of the shared [RingStyle].
///
/// `CountdownRing` 的视觉样式。共享 [RingStyle] 的别名。
typedef CountdownRingStyle = RingStyle;
