import 'package:flutter/foundation.dart';

import 'border.dart';
import 'fill.dart';
import 'shadow.dart';
import 'text.dart';

/// 普通态和激活态共用的单元格样式；null 字段由玩法回退。
///
/// 例如 `const LuckyCellStyle(borderRadius: 8)` 只指定背景圆角。
@immutable
final class LuckyCellStyle {
  /// 创建配置，未指定的可选字段使用声明的默认值。
  const LuckyCellStyle(
      {this.background,
      this.shadow,
      this.borderRadius,
      this.border,
      this.foreground,
      this.text});

  /// 背景；null 表示未指定，全透明填充仍表示有背景。
  final LuckyFill? background;

  /// 格子阴影。
  final LuckyShadow? shadow;

  /// 背景圆角半径（逻辑像素）。
  final double? borderRadius;

  /// 绘制在背景之后、图片之前的描边。
  final LuckyBorder? border;

  /// 绘制在图片和文字之后的前景填充。
  final LuckyFill? foreground;

  /// 文字样式覆盖。
  final LuckyTextOverride? text;

  /// 返回只替换指定字段的副本；参数为 null 时保留原值。
  ///
  /// 例如 `style.copyWith(borderRadius: 0)` 显式禁用圆角。
  LuckyCellStyle copyWith(
          {LuckyFill? background,
          LuckyShadow? shadow,
          double? borderRadius,
          LuckyBorder? border,
          LuckyFill? foreground,
          LuckyTextOverride? text}) =>
      LuckyCellStyle(
          background: background ?? this.background,
          shadow: shadow ?? this.shadow,
          borderRadius: borderRadius ?? this.borderRadius,
          border: border ?? this.border,
          foreground: foreground ?? this.foreground,
          text: text ?? this.text);

  /// 按全部样式字段比较配置。
  @override
  bool operator ==(Object other) =>
      other is LuckyCellStyle &&
      other.background == background &&
      other.shadow == shadow &&
      other.borderRadius == borderRadius &&
      other.border == border &&
      other.foreground == foreground &&
      other.text == text;

  /// 与字段值相等性一致的哈希值。
  @override
  int get hashCode =>
      Object.hash(background, shadow, borderRadius, border, foreground, text);
}
