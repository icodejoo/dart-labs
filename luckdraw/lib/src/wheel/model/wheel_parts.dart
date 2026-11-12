import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../core/foundation/fill.dart';
import '../../core/foundation/image.dart';
import '../../core/foundation/length.dart';
import '../../core/foundation/text.dart';

/// 从外到内排列的圆环配置。
@immutable
final class WheelBlock {
  /// 创建圆环；[padding] 为向内收缩的逻辑像素数。
  const WheelBlock({this.padding = 0, this.background, this.images = const []});

  /// 内部奖品区向内收缩的距离。
  final double padding;

  /// 圆环背景，null 表示无背景。
  final LuckyFill? background;

  /// 圆环图片。
  final List<WheelBlockImage> images;

  /// 返回替换非 null 参数的副本。
  WheelBlock copyWith(
          {double? padding,
          LuckyFill? background,
          List<WheelBlockImage>? images}) =>
      WheelBlock(
          padding: padding ?? this.padding,
          background: background ?? this.background,
          images: images ?? this.images);

  /// 按配置值比较。
  @override
  bool operator ==(Object other) =>
      other is WheelBlock &&
      other.padding == padding &&
      other.background == background &&
      listEquals(other.images, images);

  /// 与值相等性一致的哈希。
  @override
  int get hashCode => Object.hash(padding, background, Object.hashAll(images));
}

/// 可选择随转盘一起旋转的圆环图片。
@immutable
class WheelBlockImage extends LuckyImage {
  /// 创建图片；[rotate] 默认关闭，其余参数与 LuckyImage 相同。
  const WheelBlockImage(super.image,
      {super.top,
      super.left,
      super.width,
      super.height,
      super.formatter,
      super.borderRadius,
      super.opacity,
      super.fallback,
      super.semanticLabel,
      this.rotate = false});

  /// 是否绕圆心随盘旋转。
  final bool rotate;

  /// 返回替换非 null 参数的副本，保留旋转设置。
  @override
  WheelBlockImage copyWith(
          {ImageProvider<Object>? image,
          LuckyLength? top,
          LuckyLength? left,
          LuckyLength? width,
          LuckyLength? height,
          LuckyImageFormatter? formatter,
          double? borderRadius,
          double? opacity,
          ImageProvider<Object>? fallback,
          String? semanticLabel,
          bool? rotate}) =>
      WheelBlockImage(image ?? this.image,
          top: top ?? this.top,
          left: left ?? this.left,
          width: width ?? this.width,
          height: height ?? this.height,
          formatter: formatter ?? this.formatter,
          borderRadius: borderRadius ?? this.borderRadius,
          opacity: opacity ?? this.opacity,
          fallback: fallback ?? this.fallback,
          semanticLabel: semanticLabel ?? this.semanticLabel,
          rotate: rotate ?? this.rotate);

  /// 按图片字段及旋转设置比较。
  @override
  bool operator ==(Object other) =>
      other is WheelBlockImage && super == other && other.rotate == rotate;

  /// 与值相等性一致的哈希。
  @override
  int get hashCode => Object.hash(super.hashCode, rotate);
}

/// 奖品扇区；选奖权重与扇区大小互相独立。
@immutable
final class WheelPrize {
  /// 创建奖品；[sectorWeight] 应为有限正数，[weight] 缺省时不可被默认 picker 选中。
  const WheelPrize(
      {this.background,
      this.texts = const [],
      this.images = const [],
      this.weight,
      this.sectorWeight = 1,
      this.disabled = false,
      this.painter,
      this.semanticsLabel});

  /// 背景，null 使用转盘默认样式。
  final LuckyFill? background;

  /// 文字项。
  final List<LuckyText> texts;

  /// 图片项。
  final List<LuckyImage> images;

  /// 随机选奖权重。
  final double? weight;

  /// 扇区相对大小，应为有限正数。
  final double sectorWeight;

  /// 是否排除默认随机选奖。
  final bool disabled;

  /// 在扇区局部坐标中录制的自定义内容。
  final WheelPrizePainter? painter;

  /// 无障碍描述。
  final String? semanticsLabel;

  /// 返回仅替换非 null 参数的副本。
  WheelPrize copyWith(
          {LuckyFill? background,
          List<LuckyText>? texts,
          List<LuckyImage>? images,
          double? weight,
          double? sectorWeight,
          bool? disabled,
          WheelPrizePainter? painter,
          String? semanticsLabel}) =>
      WheelPrize(
          background: background ?? this.background,
          texts: texts ?? this.texts,
          images: images ?? this.images,
          weight: weight ?? this.weight,
          sectorWeight: sectorWeight ?? this.sectorWeight,
          disabled: disabled ?? this.disabled,
          painter: painter ?? this.painter,
          semanticsLabel: semanticsLabel ?? this.semanticsLabel);

  /// 按奖品字段比较。
  @override
  bool operator ==(Object other) =>
      other is WheelPrize &&
      other.background == background &&
      listEquals(other.texts, texts) &&
      listEquals(other.images, images) &&
      other.weight == weight &&
      other.sectorWeight == sectorWeight &&
      other.disabled == disabled &&
      other.painter == painter &&
      other.semanticsLabel == semanticsLabel;

  /// 与值相等性一致的哈希。
  @override
  int get hashCode => Object.hash(
      background,
      Object.hashAll(texts),
      Object.hashAll(images),
      weight,
      sectorWeight,
      disabled,
      painter,
      semanticsLabel);
}

/// 扇区录制回调；原点在外缘中点，正 y 指向圆心。
typedef WheelPrizePainter = void Function(
    Canvas canvas, WheelPrizePaintContext context);

/// 自定义奖品内容的只读几何参数。
@immutable
final class WheelPrizePaintContext {
  /// 创建上下文；角宽为弧度，其余长度为逻辑像素。
  const WheelPrizePaintContext(
      {required this.index,
      required this.sweepRad,
      required this.prizeRadius,
      required this.prizeHeight,
      required this.shortSide});

  /// 奖品下标。
  final int index;

  /// 扇区角宽，单位为弧度。
  final double sweepRad;

  /// 奖品区半径。
  final double prizeRadius;

  /// 外缘到最大按钮边缘的高度。
  final double prizeHeight;

  /// 扇区外缘弦长。
  final double shortSide;
}

/// 同心圆按钮，可附带指针。
@immutable
final class WheelButton {
  /// 创建按钮；[radius] 百分比相对奖品区半径。
  const WheelButton(
      {this.radius = LuckyLength.zero,
      this.pointer = false,
      this.background,
      this.texts = const [],
      this.images = const []});

  /// 按钮半径。
  final LuckyLength radius;

  /// 有背景时是否绘制朝上的三角指针。
  final bool pointer;

  /// 按钮背景，null 时不绘制指针。
  final LuckyFill? background;

  /// 不自动折行的文字。
  final List<LuckyText> texts;

  /// 图片项。
  final List<LuckyImage> images;

  /// 返回仅替换非 null 参数的副本。
  WheelButton copyWith(
          {LuckyLength? radius,
          bool? pointer,
          LuckyFill? background,
          List<LuckyText>? texts,
          List<LuckyImage>? images}) =>
      WheelButton(
          radius: radius ?? this.radius,
          pointer: pointer ?? this.pointer,
          background: background ?? this.background,
          texts: texts ?? this.texts,
          images: images ?? this.images);

  /// 按按钮字段比较。
  @override
  bool operator ==(Object other) =>
      other is WheelButton &&
      other.radius == radius &&
      other.pointer == pointer &&
      other.background == background &&
      listEquals(other.texts, texts) &&
      listEquals(other.images, images);

  /// 与值相等性一致的哈希。
  @override
  int get hashCode => Object.hash(radius, pointer, background,
      Object.hashAll(texts), Object.hashAll(images));
}
