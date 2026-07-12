import 'package:flutter/widgets.dart';

import 'painter/bar_painter.dart';
import 'style_support.dart';

/// Shared visual-field contract for [BarCounterStyle] / [BarCountdownStyle].
///
/// [BarCounterStyle] / [BarCountdownStyle] 共享的视觉字段契约。
mixin BarStyleFields {
  /// Bar length along the main axis (width when horizontal).
  ///
  /// 主轴长度（水平时为宽度）。
  double? get width;

  /// Bar thickness along the cross axis (height when horizontal).
  ///
  /// 横轴厚度（水平时为高度）。
  double? get height;

  /// Cross-axis thickness of the track/fill band. Falls back to the full extent.
  ///
  /// 轨道/填充带的横轴厚度。回退到全尺寸。
  double? get trackHeight;

  /// Fill color. Falls back to provider then theme primary.
  ///
  /// 填充色。回退到 provider，再到主题 primary。
  Color? get color;

  /// Track color. Falls back to provider then a muted theme color.
  ///
  /// 轨道色。回退到 provider，再到淡色主题色。
  Color? get trackColor;

  /// Fill gradient, overriding [color].
  ///
  /// 填充渐变，覆盖 [color]。
  Gradient? get gradient;

  /// Track gradient, overriding [trackColor].
  ///
  /// 轨道渐变，覆盖 [trackColor]。
  Gradient? get trackGradient;

  /// Uniform corner radius; ignored when [borderRadiusGeometry] is set.
  ///
  /// 统一圆角；设置 [borderRadiusGeometry] 时忽略。
  Radius? get borderRadius;

  /// Per-corner radius, overriding [borderRadius].
  ///
  /// 逐角圆角，覆盖 [borderRadius]。
  BorderRadius? get borderRadiusGeometry;

  /// Fill grows from the start edge (left/bottom) when true.
  ///
  /// 为 true 时从起始边（左/下）填充。
  bool? get fillFromStart;

  /// Whether the background track is drawn.
  ///
  /// 是否绘制背景轨道。
  bool? get showTrack;

  /// Fill along the vertical axis instead of horizontal.
  ///
  /// 沿竖直轴填充而非水平。
  bool? get vertical;
}

/// Builds a [BarPainter] from a resolved style + theme-resolved colors.
///
/// 依据已解析样式与主题解析后的颜色，构建 [BarPainter]。
///
/// @param s Resolved bar style fields.
///
///   已解析的进度条样式字段。
///
/// @param progress Current 0–1 fill fraction.
///
///   当前 0–1 填充比例。
///
/// @param color Theme-resolved fill color fallback.
///
///   主题解析后的填充色回退值。
///
/// @param trackColor Theme-resolved track color fallback.
///
///   主题解析后的轨道色回退值。
///
/// @returns A configured [BarPainter].
///
///   配置好的 [BarPainter]。
BarPainter barPainterFrom(
  BarStyleFields s, {
  required double progress,
  required Color color,
  required Color trackColor,
}) {
  return BarPainter(
    progress: progress,
    color: color,
    trackColor: trackColor,
    borderRadius: s.borderRadius ?? const Radius.circular(4),
    borderRadiusGeometry: s.borderRadiusGeometry,
    gradient: s.gradient,
    trackGradient: s.trackGradient,
    fillFromStart: s.fillFromStart ?? true,
    trackHeight: s.trackHeight,
    showTrack: s.showTrack ?? true,
    vertical: s.vertical ?? false,
  );
}

/// Visual style for the bar displays — shared by `BarCounter` and
/// `BarCountdown` (see the [BarCounterStyle] / [BarCountdownStyle] aliases).
///
/// Groups every bar appearance knob (geometry, colors, gradients, corner
/// radius, fill direction, orientation, container decoration) into one
/// reusable, themeable, mergeable object. All fields nullable.
///
/// 进度条显示组件的视觉样式——由 `BarCounter` 与 `BarCountdown` 共用
/// （见 [BarCounterStyle] / [BarCountdownStyle] 别名）。
///
/// 把每个进度条外观项（几何、颜色、渐变、圆角、填充方向、朝向、容器装饰）聚合为
/// 一个可复用、可主题化、可合并的对象。所有字段可空。
@immutable
class BarStyle with BoxStyleFields, BarStyleFields, StyleProps {
  /// Creates a bar style. All fields optional.
  ///
  /// 创建进度条样式。所有字段可选。
  const BarStyle({
    this.width,
    this.height,
    this.trackHeight,
    this.color,
    this.trackColor,
    this.gradient,
    this.trackGradient,
    this.borderRadius,
    this.borderRadiusGeometry,
    this.fillFromStart,
    this.showTrack,
    this.vertical,
    this.padding,
    this.decoration,
  });

  @override
  final double? width;
  @override
  final double? height;
  @override
  final double? trackHeight;
  @override
  final Color? color;
  @override
  final Color? trackColor;
  @override
  final Gradient? gradient;
  @override
  final Gradient? trackGradient;
  @override
  final Radius? borderRadius;
  @override
  final BorderRadius? borderRadiusGeometry;
  @override
  final bool? fillFromStart;
  @override
  final bool? showTrack;
  @override
  final bool? vertical;
  @override
  final EdgeInsetsGeometry? padding;
  @override
  final Decoration? decoration;

  /// Returns a copy with the given fields replaced.
  ///
  /// 返回替换了给定字段的副本。
  BarStyle copyWith({
    double? width,
    double? height,
    double? trackHeight,
    Color? color,
    Color? trackColor,
    Gradient? gradient,
    Gradient? trackGradient,
    Radius? borderRadius,
    BorderRadius? borderRadiusGeometry,
    bool? fillFromStart,
    bool? showTrack,
    bool? vertical,
    EdgeInsetsGeometry? padding,
    Decoration? decoration,
  }) =>
      BarStyle(
        width: width ?? this.width,
        height: height ?? this.height,
        trackHeight: trackHeight ?? this.trackHeight,
        color: color ?? this.color,
        trackColor: trackColor ?? this.trackColor,
        gradient: gradient ?? this.gradient,
        trackGradient: trackGradient ?? this.trackGradient,
        borderRadius: borderRadius ?? this.borderRadius,
        borderRadiusGeometry: borderRadiusGeometry ?? this.borderRadiusGeometry,
        fillFromStart: fillFromStart ?? this.fillFromStart,
        showTrack: showTrack ?? this.showTrack,
        vertical: vertical ?? this.vertical,
        padding: padding ?? this.padding,
        decoration: decoration ?? this.decoration,
      );

  /// Merges with lower-priority [other]: this object's non-null fields win.
  ///
  /// 与更低优先级的 [other] 合并：本对象非空字段优先。
  BarStyle merge(BarStyle? other) => other == null
      ? this
      : BarStyle(
          width: width ?? other.width,
          height: height ?? other.height,
          trackHeight: trackHeight ?? other.trackHeight,
          color: color ?? other.color,
          trackColor: trackColor ?? other.trackColor,
          gradient: gradient ?? other.gradient,
          trackGradient: trackGradient ?? other.trackGradient,
          borderRadius: borderRadius ?? other.borderRadius,
          borderRadiusGeometry: borderRadiusGeometry ?? other.borderRadiusGeometry,
          fillFromStart: fillFromStart ?? other.fillFromStart,
          showTrack: showTrack ?? other.showTrack,
          vertical: vertical ?? other.vertical,
          padding: padding ?? other.padding,
          decoration: decoration ?? other.decoration,
        );

  @override
  List<Object?> get props => [
        width,
        height,
        trackHeight,
        color,
        trackColor,
        gradient,
        trackGradient,
        borderRadius,
        borderRadiusGeometry,
        fillFromStart,
        showTrack,
        vertical,
        padding,
        decoration,
      ];
}

/// Visual style for `BarCounter`. Alias of the shared [BarStyle].
///
/// `BarCounter` 的视觉样式。共享 [BarStyle] 的别名。
typedef BarCounterStyle = BarStyle;

/// Visual style for `BarCountdown`. Alias of the shared [BarStyle].
///
/// `BarCountdown` 的视觉样式。共享 [BarStyle] 的别名。
typedef BarCountdownStyle = BarStyle;
