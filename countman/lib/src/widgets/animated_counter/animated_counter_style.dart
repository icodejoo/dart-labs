part of 'animated_counter.dart';

/// Visual style for [AnimatedCounter] and [AnimatedCounterBuilder].
///
/// Groups the appearance knobs (number/affix/separator text styles, digit
/// alignment, row alignment, padding, tabular figures, direction tint colors,
/// and container [decoration]) into one reusable, mergeable object. All fields
/// nullable; unset fields fall back to the widget's deprecated loose params
/// then to framework defaults.
///
/// [AnimatedCounter] 与 [AnimatedCounterBuilder] 的视觉样式。把外观项（数字/词缀/分隔符
/// 文本样式、数字对齐、行对齐、内边距、等宽数字、增减方向着色、容器 [decoration]）
/// 聚合为一个可复用、可合并的对象。所有字段可空；未设置的字段回退到 widget 的弃用
/// 松散参数，再到框架默认值。
@immutable
// 与其他组件样式共用字段列表及运行时类型相等性约束。
class AnimatedCounterStyle with StyleProps {
  /// Creates an [AnimatedCounter] style. All fields optional.
  ///
  /// 创建 [AnimatedCounter] 样式。所有字段可选。
  const AnimatedCounterStyle({
    this.textStyle,
    this.prefixStyle,
    this.infixStyle,
    this.suffixStyle,
    this.separatorStyle,
    this.numberAlignment,
    this.mainAxisAlignment,
    this.crossAxisAlignment,
    this.padding,
    this.useTabularFigures,
    this.increasingColor,
    this.decreasingColor,
    this.colorFadeDuration,
    this.decoration,
  });

  /// Text style for the digits.
  final TextStyle? textStyle;

  /// Text style for the prefix (falls back to [textStyle]).
  final TextStyle? prefixStyle;

  /// Text style for the infix (falls back to [textStyle]).
  final TextStyle? infixStyle;

  /// Text style for the suffix (falls back to [textStyle]).
  final TextStyle? suffixStyle;

  /// Text style for group/decimal separators.
  final TextStyle? separatorStyle;

  /// Horizontal alignment of visible digits within the stable full-width slot.
  /// -1.0 = left, 0.0 = center, 1.0 = right.
  final double? numberAlignment;

  /// Main-axis alignment of the decoration row.
  final MainAxisAlignment? mainAxisAlignment;

  /// Cross-axis alignment of the decoration row.
  final CrossAxisAlignment? crossAxisAlignment;

  /// Padding applied inside the counter (around the digits).
  final EdgeInsets? padding;

  /// Whether to use tabular (fixed-width) figures.
  final bool? useTabularFigures;

  /// Tint color applied while the value increases.
  final Color? increasingColor;

  /// Tint color applied while the value decreases.
  final Color? decreasingColor;

  /// Duration of the increase/decrease color tint fade.
  final Duration? colorFadeDuration;

  /// Container decoration (background/border/radius/gradient/shadow) drawn
  /// around the whole counter.
  ///
  /// 绘制在整个计数器外围的容器装饰（背景/边框/圆角/渐变/阴影）。
  final Decoration? decoration;

  /// Returns a copy with the given fields replaced.
  ///
  /// 返回替换了给定字段的副本。
  AnimatedCounterStyle copyWith({
    TextStyle? textStyle,
    TextStyle? prefixStyle,
    TextStyle? infixStyle,
    TextStyle? suffixStyle,
    TextStyle? separatorStyle,
    double? numberAlignment,
    MainAxisAlignment? mainAxisAlignment,
    CrossAxisAlignment? crossAxisAlignment,
    EdgeInsets? padding,
    bool? useTabularFigures,
    Color? increasingColor,
    Color? decreasingColor,
    Duration? colorFadeDuration,
    Decoration? decoration,
  }) =>
      AnimatedCounterStyle(
        textStyle: textStyle ?? this.textStyle,
        prefixStyle: prefixStyle ?? this.prefixStyle,
        infixStyle: infixStyle ?? this.infixStyle,
        suffixStyle: suffixStyle ?? this.suffixStyle,
        separatorStyle: separatorStyle ?? this.separatorStyle,
        numberAlignment: numberAlignment ?? this.numberAlignment,
        mainAxisAlignment: mainAxisAlignment ?? this.mainAxisAlignment,
        crossAxisAlignment: crossAxisAlignment ?? this.crossAxisAlignment,
        padding: padding ?? this.padding,
        useTabularFigures: useTabularFigures ?? this.useTabularFigures,
        increasingColor: increasingColor ?? this.increasingColor,
        decreasingColor: decreasingColor ?? this.decreasingColor,
        colorFadeDuration: colorFadeDuration ?? this.colorFadeDuration,
        decoration: decoration ?? this.decoration,
      );

  /// Merges with lower-priority [other]: this object's non-null fields win.
  ///
  /// 与更低优先级的 [other] 合并：本对象非空字段优先。
  AnimatedCounterStyle merge(AnimatedCounterStyle? other) => other == null
      ? this
      : AnimatedCounterStyle(
          textStyle: textStyle ?? other.textStyle,
          prefixStyle: prefixStyle ?? other.prefixStyle,
          infixStyle: infixStyle ?? other.infixStyle,
          suffixStyle: suffixStyle ?? other.suffixStyle,
          separatorStyle: separatorStyle ?? other.separatorStyle,
          numberAlignment: numberAlignment ?? other.numberAlignment,
          mainAxisAlignment: mainAxisAlignment ?? other.mainAxisAlignment,
          crossAxisAlignment: crossAxisAlignment ?? other.crossAxisAlignment,
          padding: padding ?? other.padding,
          useTabularFigures: useTabularFigures ?? other.useTabularFigures,
          increasingColor: increasingColor ?? other.increasingColor,
          decreasingColor: decreasingColor ?? other.decreasingColor,
          colorFadeDuration: colorFadeDuration ?? other.colorFadeDuration,
          decoration: decoration ?? other.decoration,
        );

  // 字段顺序同时用于相等性与哈希，新增字段只需维护一处。
  /// 在 [a] 与 [b] 之间按 [t]（0–1）插值，用于 `ThemeExtension.lerp`。
  ///
  /// 文字样式、对齐系数、颜色、渐隐时长、内边距、装饰逐字段插值；主轴/交叉轴对齐、
  /// 等宽数字开关不可插值，在 `t < 0.5` 时取 [a]，否则取 [b]；任一端为空时同样按
  /// `t < 0.5` 取一端。例如 `AnimatedCounterStyle.lerp(a, b, 0.5)`。
  static AnimatedCounterStyle? lerp(
      AnimatedCounterStyle? a, AnimatedCounterStyle? b, double t) {
    if (identical(a, b)) return a;
    if (a == null || b == null) return t < 0.5 ? a : b;
    return AnimatedCounterStyle(
      textStyle: TextStyle.lerp(a.textStyle, b.textStyle, t),
      prefixStyle: TextStyle.lerp(a.prefixStyle, b.prefixStyle, t),
      infixStyle: TextStyle.lerp(a.infixStyle, b.infixStyle, t),
      suffixStyle: TextStyle.lerp(a.suffixStyle, b.suffixStyle, t),
      separatorStyle: TextStyle.lerp(a.separatorStyle, b.separatorStyle, t),
      numberAlignment: lerpNum(a.numberAlignment, b.numberAlignment, t),
      mainAxisAlignment:
          pickField(a.mainAxisAlignment, b.mainAxisAlignment, t),
      crossAxisAlignment:
          pickField(a.crossAxisAlignment, b.crossAxisAlignment, t),
      padding: EdgeInsets.lerp(a.padding, b.padding, t),
      useTabularFigures: pickField(a.useTabularFigures, b.useTabularFigures, t),
      increasingColor: lerpColor(a.increasingColor, b.increasingColor, t),
      decreasingColor: lerpColor(a.decreasingColor, b.decreasingColor, t),
      colorFadeDuration:
          lerpDuration(a.colorFadeDuration, b.colorFadeDuration, t),
      decoration: Decoration.lerp(a.decoration, b.decoration, t),
    );
  }

  @override
  List<Object?> get props => [
        textStyle,
        prefixStyle,
        infixStyle,
        suffixStyle,
        separatorStyle,
        numberAlignment,
        mainAxisAlignment,
        crossAxisAlignment,
        padding,
        useTabularFigures,
        increasingColor,
        decreasingColor,
        colorFadeDuration,
        decoration,
      ];
}
