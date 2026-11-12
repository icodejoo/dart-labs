import 'package:flutter/foundation.dart';

import 'border.dart';
import 'edge_insets.dart';
import 'fill.dart';
import 'image.dart';

/// 九宫格和老虎机共用的矩形装饰块。
///
/// 例如 `const LuckyBoxBlock(padding: LuckyEdgeInsets.all(8))` 为内容预留边距。
@immutable
final class LuckyBoxBlock {
  /// 创建配置，未指定的可选字段使用声明的默认值。
  const LuckyBoxBlock(
      {this.padding = LuckyEdgeInsets.zero,
      this.borderRadius = 0,
      this.background,
      this.border,
      this.images = const []});

  /// 四边内边距（逻辑像素）。
  final LuckyEdgeInsets padding;

  /// 背景圆角半径（逻辑像素）。
  final double borderRadius;

  /// 块背景；null 表示无背景。
  final LuckyFill? background;

  /// 块描边。
  final LuckyBorder? border;

  /// 块图片列表；调用方须保持列表不可变。
  final List<LuckyImage> images;

  /// 返回只替换指定字段的副本；参数为 null 时保留原值。
  ///
  /// 列表参数须由调用方保持不可变；例如 `value.copyWith()` 保留全部字段。
  LuckyBoxBlock copyWith(
          {LuckyEdgeInsets? padding,
          double? borderRadius,
          LuckyFill? background,
          LuckyBorder? border,
          List<LuckyImage>? images}) =>
      LuckyBoxBlock(
          padding: padding ?? this.padding,
          borderRadius: borderRadius ?? this.borderRadius,
          background: background ?? this.background,
          border: border ?? this.border,
          images: images ?? this.images);

  /// 按字段值比较配置，列表按内容比较。
  @override
  bool operator ==(Object other) =>
      other is LuckyBoxBlock &&
      other.padding == padding &&
      other.borderRadius == borderRadius &&
      other.background == background &&
      other.border == border &&
      listEquals(other.images, images);

  /// 与字段值相等性一致的哈希值。
  @override
  int get hashCode => Object.hash(
      padding, borderRadius, background, border, Object.hashAll(images));
}
