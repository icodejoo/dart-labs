import 'package:flutter/material.dart';

/// 演示专用配色，保留原设计稿的紫色与粉色组合。
abstract final class DemoPalette {
  /// 主紫色。
  static const purple = Color(0xFF7C4DFF);

  /// 浅紫底色。
  static const pale = Color(0xFFEDE7F6);

  /// 深色面板与文字颜色。
  static const ink = Color(0xFF2B2640);

  /// 次级深色文字。
  static const mutedInk = Color(0xFF4A3F72);

  /// 强调粉色。
  static const pink = Color(0xFFEC4899);

  /// 蓝色描边。
  static const blue = Color(0xFF2196F3);

  /// 浅紫渐变终点。
  static const lavender = Color(0xFFB388FF);

  /// 底板边框颜色。
  static const outline = Color(0xFFB39DDB);

  /// 暗色底板上的亮色填充。
  static const cream = Color(0xFFF3EEFC);

  /// 分割线的半透明阴影。
  static const glow = Color(0x807C4DFF);
}
