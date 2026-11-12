import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../core/foundation/cell_style.dart';
import '../../core/foundation/fill.dart';
import '../../core/foundation/image.dart';
import '../../core/foundation/text.dart';
import '../../core/kinematics/physics_options.dart';
import '../../core/motion/motion_options.dart';

/// 奖品卡自定义绘制；[bounds] 为卡片区域，不得保留画布。
typedef CapsulePrizePainter = void Function(Canvas canvas, Rect bounds);

/// 扭蛋奖品；文字和图片在开蛋卡片中展示。
@immutable
final class CapsulePrize {
  /// 创建不可变配置；列表由调用方保持不可变。
  const CapsulePrize(
      {required this.topFill,
      required this.bottomFill,
      this.texts = const [],
      this.images = const [],
      this.weight,
      this.disabled = false,
      this.painter});

  /// 上半球填充。
  final LuckyFill topFill;

  /// 下半球填充。
  final LuckyFill bottomFill;

  /// 奖品卡文字。
  final List<LuckyText> texts;

  /// 奖品卡图片。
  final List<LuckyImage> images;

  /// 选奖权重；空权重不可选。
  final double? weight;

  /// 是否禁止随机选中。
  final bool disabled;

  /// 卡片自定义绘制回调。
  final CapsulePrizePainter? painter;

  /// 返回替换非空参数的副本，例如 `value.copyWith()` 保留全部字段。
  CapsulePrize copyWith(
          {LuckyFill? topFill,
          LuckyFill? bottomFill,
          List<LuckyText>? texts,
          List<LuckyImage>? images,
          double? weight,
          bool? disabled,
          CapsulePrizePainter? painter}) =>
      CapsulePrize(
          topFill: topFill ?? this.topFill,
          bottomFill: bottomFill ?? this.bottomFill,
          texts: texts ?? this.texts,
          images: images ?? this.images,
          weight: weight ?? this.weight,
          disabled: disabled ?? this.disabled,
          painter: painter ?? this.painter);

  /// 按字段值比较，列表按内容比较。
  @override
  bool operator ==(Object other) =>
      other is CapsulePrize &&
      other.topFill == topFill &&
      other.bottomFill == bottomFill &&
      listEquals(other.texts, texts) &&
      listEquals(other.images, images) &&
      other.weight == weight &&
      other.disabled == disabled &&
      other.painter == painter;

  /// 与字段值一致的哈希。
  @override
  int get hashCode => Object.hashAll([
        topFill,
        bottomFill,
        Object.hashAll(texts),
        Object.hashAll(images),
        weight,
        disabled,
        painter
      ]);
}

/// 扭蛋机几何与动画参数。
@immutable
final class CapsuleOptions {
  /// 创建不可变配置；列表由调用方保持不可变。
  const CapsuleOptions(
      {this.globeRadiusFactor = 0.42,
      this.capsuleRadiusFactor = 0.14,
      this.dropTime = const Duration(milliseconds: 600),
      this.revealTime = const Duration(milliseconds: 400),
      this.revealOnSettle = true,
      this.motion = const LuckyMotionOptions(
          speed: 12,
          accelerationTime: Duration(milliseconds: 800),
          decelerationTime: Duration(milliseconds: 1500)),
      this.physics});

  /// 球体半径相对盒子宽度的比例。
  final double globeRadiusFactor;

  /// 胶囊半径相对球体半径的比例。
  final double capsuleRadiusFactor;

  /// 掉落时长，运行期至少一毫秒。
  final Duration dropTime;

  /// 展示时长，运行期至少一毫秒。
  final Duration revealTime;

  /// 是否在掉落后展开奖品卡。
  final bool revealOnSettle;

  /// 搅拌动画配置。
  final LuckyMotionOptions motion;

  /// 实验性（可能调整）：物理碰撞模式参数；null 保持参数化轨迹（默认）。
  ///
  /// 例如 `CapsuleOptions(physics: LuckyPhysics())`，胶囊从顶部落下并与球壁、拨杆碰撞。
  final LuckyPhysics? physics;

  /// 返回替换非空参数的副本，例如 `value.copyWith()` 保留全部字段；
  /// 无法用 null 清除 [physics]，需要关闭物理模式时重新构造。
  CapsuleOptions copyWith(
          {double? globeRadiusFactor,
          double? capsuleRadiusFactor,
          Duration? dropTime,
          Duration? revealTime,
          bool? revealOnSettle,
          LuckyMotionOptions? motion,
          LuckyPhysics? physics}) =>
      CapsuleOptions(
          globeRadiusFactor: globeRadiusFactor ?? this.globeRadiusFactor,
          capsuleRadiusFactor: capsuleRadiusFactor ?? this.capsuleRadiusFactor,
          dropTime: dropTime ?? this.dropTime,
          revealTime: revealTime ?? this.revealTime,
          revealOnSettle: revealOnSettle ?? this.revealOnSettle,
          motion: motion ?? this.motion,
          physics: physics ?? this.physics);

  /// 返回去掉物理模式、其余字段不变的副本，例如关闭 `CapsuleOptions(physics: ...)`。
  CapsuleOptions withoutPhysics() => CapsuleOptions(
      globeRadiusFactor: globeRadiusFactor,
      capsuleRadiusFactor: capsuleRadiusFactor,
      dropTime: dropTime,
      revealTime: revealTime,
      revealOnSettle: revealOnSettle,
      motion: motion);

  /// 按字段值比较，列表按内容比较。
  @override
  bool operator ==(Object other) =>
      other is CapsuleOptions &&
      other.globeRadiusFactor == globeRadiusFactor &&
      other.capsuleRadiusFactor == capsuleRadiusFactor &&
      other.dropTime == dropTime &&
      other.revealTime == revealTime &&
      other.revealOnSettle == revealOnSettle &&
      other.motion == motion &&
      other.physics == physics;

  /// 与字段值一致的哈希。
  @override
  int get hashCode => Object.hashAll([
        globeRadiusFactor,
        capsuleRadiusFactor,
        dropTime,
        revealTime,
        revealOnSettle,
        motion,
        physics
      ]);
}

/// 扭蛋机配色与奖品卡样式。
@immutable
final class CapsuleStyle {
  /// 创建不可变配置；列表由调用方保持不可变。
  const CapsuleStyle(
      {this.globeFill,
      this.bodyFill,
      this.knobFill,
      this.seamColor = const Color(0x33000000),
      this.card = const LuckyCellStyle(
          background: LuckyFill.color(Color(0xFFFFFFFF)), borderRadius: 12),
      this.text = const LuckyTextDefaults()});

  /// 球体背面填充；空时使用透明蓝色。
  final LuckyFill? globeFill;

  /// 机身填充；空时使用红色。
  final LuckyFill? bodyFill;

  /// 旋钮填充；空时使用白色。
  final LuckyFill? knobFill;

  /// 胶囊接缝颜色。
  final Color seamColor;

  /// 奖品卡样式。
  final LuckyCellStyle card;

  /// 卡片文字默认值。
  final LuckyTextDefaults text;

  /// 返回替换非空参数的副本，例如 `value.copyWith()` 保留全部字段。
  CapsuleStyle copyWith(
          {LuckyFill? globeFill,
          LuckyFill? bodyFill,
          LuckyFill? knobFill,
          Color? seamColor,
          LuckyCellStyle? card,
          LuckyTextDefaults? text}) =>
      CapsuleStyle(
          globeFill: globeFill ?? this.globeFill,
          bodyFill: bodyFill ?? this.bodyFill,
          knobFill: knobFill ?? this.knobFill,
          seamColor: seamColor ?? this.seamColor,
          card: card ?? this.card,
          text: text ?? this.text);

  /// 按字段值比较，列表按内容比较。
  @override
  bool operator ==(Object other) =>
      other is CapsuleStyle &&
      other.globeFill == globeFill &&
      other.bodyFill == bodyFill &&
      other.knobFill == knobFill &&
      other.seamColor == seamColor &&
      other.card == card &&
      other.text == text;

  /// 与字段值一致的哈希。
  @override
  int get hashCode =>
      Object.hashAll([globeFill, bodyFill, knobFill, seamColor, card, text]);
}
