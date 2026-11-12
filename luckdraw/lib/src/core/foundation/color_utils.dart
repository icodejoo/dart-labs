import 'dart:ui' show Color;

import 'constants.dart';

/// 返回 [color] 的八位透明度，范围为 0–255。
///
/// 例如不透明黑色返回 255；兼容 Flutter 3.24。
int colorAlpha8(Color color) {
  // ignore: deprecated_member_use
  return color.alpha;
}

/// 将 [color] 的透明度乘以 [factor] 后四舍五入，并钳至 0–255。
///
/// 保留颜色其余分量；例如不透明颜色乘以 0.5 后透明度为 128。
Color colorWithAlphaFactor(Color color, double factor) => color.withAlpha(
      (colorAlpha8(color) * factor).round().clamp(0, kLuckyMaxAlpha8),
    );
