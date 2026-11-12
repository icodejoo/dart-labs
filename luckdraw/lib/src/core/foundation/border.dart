import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// 描边配置，宽度采用逻辑像素。
///
/// 例如 `const LuckyBorder(width: 2, color: Color(0xFFFF0000))` 表示红色描边。
@immutable
final class LuckyBorder {
  /// 创建配置，未指定的可选字段使用声明的默认值。
  const LuckyBorder({required this.width, required this.color});

  /// 描边宽度（逻辑像素）。
  final double width;

  /// 描边颜色。
  final Color color;

  /// 返回只替换指定字段的副本；参数为 null 时保留原值。
  ///
  /// 例如 `border.copyWith(width: 0)` 只替换宽度。
  LuckyBorder copyWith({double? width, Color? color}) =>
      LuckyBorder(width: width ?? this.width, color: color ?? this.color);

  /// 按宽度和颜色比较配置。
  @override
  bool operator ==(Object other) =>
      other is LuckyBorder && other.width == width && other.color == color;

  /// 与字段值相等性一致的哈希值。
  @override
  int get hashCode => Object.hash(width, color);
}
