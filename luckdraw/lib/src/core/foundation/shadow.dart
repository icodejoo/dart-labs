import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'color_utils.dart';
import 'constants.dart';
import 'fill.dart';

/// 阴影模糊半径的坐标空间。
enum LuckyShadowBlurSpace {
  /// 逻辑像素，sigma 为 blur / 2。
  logical,

  /// 设备像素，sigma 为 blur / (2 * dpr)。
  device,
}

/// 九宫格格子阴影配置。
///
/// 例如 `LuckyShadow(blur: 8, color: Color(0x80000000))` 产生 sigma 为 4 的阴影。
@immutable
final class LuckyShadow {
  /// 创建阴影，模糊半径 [blur] 采用 [blurSpace] 约定的空间。
  ///
  /// 偏移始终是逻辑像素；[blurSpace] 只影响模糊半径。
  const LuckyShadow(
      {this.offsetX = 0,
      this.offsetY = 0,
      this.blur = 0,
      required this.color,
      this.blurSpace = LuckyShadowBlurSpace.logical});

  /// 水平偏移（逻辑像素）。
  final double offsetX;

  /// 垂直偏移（逻辑像素）。
  final double offsetY;

  /// 模糊半径，空间由 [blurSpace] 决定；零表示无模糊。
  final double blur;

  /// 阴影原始颜色。
  final Color color;

  /// 模糊半径采用的坐标空间。
  final LuckyShadowBlurSpace blurSpace;

  /// 返回模糊 sigma；[devicePixelRatio] 必须大于零，零 blur 返回零。
  double sigma(double devicePixelRatio) => switch (blurSpace) {
        LuckyShadowBlurSpace.logical => blur / kLuckyShadowSigmaDivisor,
        LuckyShadowBlurSpace.device =>
          blur / kLuckyShadowSigmaDivisor / devicePixelRatio,
      };

  /// 返回 [fill] 上的阴影颜色；仅纯色填充将阴影 alpha 乘以填充 alpha / 255。
  Color colorOver(LuckyFill? fill) {
    final alpha = fill?.solidAlpha8;
    return alpha == null
        ? color
        : colorWithAlphaFactor(color, alpha / kLuckyMaxAlpha8);
  }

  /// 返回替换指定字段的副本；参数为 null 时保留原值。
  LuckyShadow copyWith(
          {double? offsetX,
          double? offsetY,
          double? blur,
          Color? color,
          LuckyShadowBlurSpace? blurSpace}) =>
      LuckyShadow(
          offsetX: offsetX ?? this.offsetX,
          offsetY: offsetY ?? this.offsetY,
          blur: blur ?? this.blur,
          color: color ?? this.color,
          blurSpace: blurSpace ?? this.blurSpace);

  /// 比较全部阴影配置。
  @override
  bool operator ==(Object other) =>
      other is LuckyShadow &&
      other.offsetX == offsetX &&
      other.offsetY == offsetY &&
      other.blur == blur &&
      other.color == color &&
      other.blurSpace == blurSpace;

  /// 与阴影配置相等性一致的哈希值。
  @override
  int get hashCode => Object.hash(offsetX, offsetY, blur, color, blurSpace);
}
