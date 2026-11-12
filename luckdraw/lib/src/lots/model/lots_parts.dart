import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../core/foundation/fill.dart';
import '../../core/foundation/image.dart';
import '../../core/foundation/text.dart';

/// 录制签文卡自定义内容；画布坐标与 [bounds] 使用布局盒子的逻辑像素。
typedef LotsStickPainter = void Function(Canvas canvas, Rect bounds);

/// 一支签；升起后显示标签，签文在展示卡内绘制。
@immutable
final class LotsStick {
  /// 创建配置；列表在使用期间不可修改。
  const LotsStick(
      {required this.label,
      this.texts = const [],
      this.images = const [],
      this.fill,
      this.weight,
      this.disabled = false,
      this.painter});

  /// 签的显示名称。
  final String label;

  /// 展示卡文字。
  final List<LuckyText> texts;

  /// 展示卡图片。
  final List<LuckyImage> images;

  /// 目标签填充，空时使用默认签色。
  final LuckyFill? fill;

  /// 随机选奖权重，空值不参与。
  final double? weight;

  /// 是否禁止随机选中。
  final bool disabled;

  /// 自定义展示卡内容，仅录制时调用。
  final LotsStickPainter? painter;

  /// 返回只替换非空参数的副本。
  LotsStick copyWith(
          {String? label,
          List<LuckyText>? texts,
          List<LuckyImage>? images,
          LuckyFill? fill,
          double? weight,
          bool? disabled,
          LotsStickPainter? painter}) =>
      LotsStick(
          label: label ?? this.label,
          texts: texts ?? this.texts,
          images: images ?? this.images,
          fill: fill ?? this.fill,
          weight: weight ?? this.weight,
          disabled: disabled ?? this.disabled,
          painter: painter ?? this.painter);

  /// 按全部字段比较值。
  @override
  bool operator ==(Object other) =>
      other is LotsStick &&
      other.label == label &&
      listEquals(other.texts, texts) &&
      listEquals(other.images, images) &&
      other.fill == fill &&
      other.weight == weight &&
      other.disabled == disabled &&
      other.painter == painter;

  /// 与值相等性一致的哈希值。
  @override
  int get hashCode => Object.hashAll([
        label,
        Object.hashAll(texts),
        Object.hashAll(images),
        fill,
        weight,
        disabled,
        painter
      ]);
}
