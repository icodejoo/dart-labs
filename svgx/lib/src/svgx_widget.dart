// Top-level dispatch widget: routes an SVG source string to the animated
// (original Dart-side SMIL engine) or static (Rust usvg → ui.Picture)
// renderer, per the "split by asset" architecture decision in CLAUDE.md.
//
// 顶层分发组件：按 CLAUDE.md 的"按资产切分"架构决定，把 SVG 源串路由到动画
// 路径（原创 Dart 侧 SMIL 引擎）或静态路径（Rust usvg → ui.Picture）。

import 'package:flutter/widgets.dart';

import 'animation/animated_svg_widget.dart';
import 'animation/animation_detector.dart';
import 'animation/svg_theme.dart';
import 'rust_static_svg.dart';

/// Renders an SVG string, automatically picking the animated or static
/// rendering path.
///
/// Detection is done via [AnimationDetector.hasAnimations]: if the source
/// contains SMIL (`<animate>`, `<set>`) animation markers, it renders through
/// [SvgXAnimated.string] (this project's original SMIL engine); otherwise it
/// renders through [SvgXStatic] (Rust `usvg` parser → cached [ui.Picture]).
/// CSS `@keyframes`/`animation-*` animation is not yet detected/supported —
/// see `lib/src/animation/animation_detector.dart`.
///
/// 渲染 SVG 字符串，自动选择动画或静态渲染路径。
///
/// 通过 [AnimationDetector.hasAnimations] 判定：若源串含 SMIL（`<animate>`、
/// `<set>`）动画标记，走 [SvgXAnimated.string]（本项目原创 SMIL 引擎）；否则走
/// [SvgXStatic]（Rust `usvg` 解析器 → 缓存的 [ui.Picture]）。CSS
/// `@keyframes`/`animation-*` 动画暂不检测/支持——见
/// `lib/src/animation/animation_detector.dart`。
///
/// Example:
/// ```dart
/// SvgX.string(svgSource, width: 48, height: 48)
/// ```
class SvgX extends StatelessWidget {
  /// Creates the dispatch widget from a raw SVG string.
  ///
  /// 用原始 SVG 字符串创建分发组件。
  const SvgX.string(
    this.source, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.colorFilter,
    this.theme,
  });

  /// Raw SVG markup, animated or static. / 原始 SVG 源，动画或静态均可。
  final String source;

  /// Target width; null uses the SVG's intrinsic width. / 目标宽度，null 用固有宽。
  final double? width;

  /// Target height; null uses the SVG's intrinsic height. / 目标高度，null 用固有高。
  final double? height;

  /// How the picture is inscribed into the box. / picture 如何适配到盒子。
  final BoxFit fit;

  /// Alignment within the box. / 在盒子内的对齐方式。
  final Alignment alignment;

  /// Optional recolor filter. / 可选的重着色滤镜。
  final ColorFilter? colorFilter;

  /// Theme controlling `currentColor`, honored by both the animated and
  /// static rendering paths.
  ///
  /// 控制 `currentColor` 的主题，动画与静态两条渲染路径均生效。
  final SvgTheme? theme;

  @override
  Widget build(BuildContext context) {
    if (AnimationDetector.hasAnimations(source)) {
      return SvgXAnimated.string(
        source,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        theme: theme,
      );
    }
    return SvgXStatic(
      source,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      colorFilter: colorFilter,
      theme: theme,
    );
  }
}
