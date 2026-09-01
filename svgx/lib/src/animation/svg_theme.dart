// Theming for the original SMIL animation engine: resolves the `currentColor`
// keyword used by icon SVGs (e.g. `stroke="currentColor"`).
//
// 原创 SMIL 动画引擎的主题：解析图标 SVG 常用的 `currentColor` 关键字
// （例如 `stroke="currentColor"`）。

import 'package:flutter/painting.dart';

/// Theme controlling how `currentColor` resolves when painting an animated
/// SVG through this engine's renderer.
///
/// Example:
/// ```dart
/// const theme = SvgxTheme(currentColor: Color(0xFFFF7A00));
/// ```
///
/// 控制本引擎渲染动画 SVG 时 `currentColor` 如何解析的主题。
///
/// 用例：
/// ```dart
/// const theme = SvgxTheme(currentColor: Color(0xFFFF7A00));
/// ```
class SvgxTheme {
  /// Creates a theme; [currentColor] defaults to opaque black.
  ///
  /// 创建主题；[currentColor] 默认不透明黑色。
  const SvgxTheme({this.currentColor = const Color(0xFF000000)});

  /// The color substituted for the `currentColor` keyword.
  ///
  /// 替换 `currentColor` 关键字所用的颜色。
  final Color currentColor;
}
