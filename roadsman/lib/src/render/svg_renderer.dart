/// SVG 渲染器（[renderToSvg]）。
///
/// 纯函数，不依赖 `dart:ui`/Flutter，可在纯 Dart（服务端/CLI）环境直接运行。
/// 把 [RoadLayout] + [Theme] 转成完整 `<svg>...</svg>` 字符串，用于服务端出图、
/// 分享卡片、报表邮件。移植自 `src/renderer-svg/svg-renderer.ts`。
library;

import '../core/types.dart';

/// [renderToSvg] 的选项。
class SvgRenderOptions {
  /// 输出 SVG 宽度（px），默认 `layout.contentWidth`。
  final double? width;

  /// 输出 SVG 高度（px），默认 `layout.contentHeight`。
  final double? height;

  /// 是否绘制网格线，默认 false。
  final bool grid;

  const SvgRenderOptions({this.width, this.height, this.grid = false});
}

/// XML 转义（防止文本内容破坏 SVG 结构）。
String _xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

/// 把 ARGB 32 位整数颜色转成 `rgba(r,g,b,a)` CSS 字符串（保留自身 alpha 通道，
/// SVG 的 `opacity` 属性再叠加 [DrawCommand.alpha] 这一层动画插值 alpha，
/// 二者相乘的语义与 SVG 规范一致）。
String _cssColor(int argb) {
  final a = ((argb >> 24) & 0xFF) / 255;
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  return 'rgba($r,$g,$b,${a.toStringAsFixed(3)})';
}

/// 将单条 [DrawCommand] 转为 SVG 元素字符串。
String _commandToSvg(DrawCommand cmd) {
  final op = cmd.alpha ?? 1;
  return switch (cmd) {
    CircleCommand c => () {
      final fill = c.fill != null ? _cssColor(c.fill!) : 'none';
      final stroke = c.stroke != null
          ? 'stroke="${_cssColor(c.stroke!)}" stroke-width="${c.lineWidth ?? 2}"'
          : '';
      return '<circle cx="${c.x}" cy="${c.y}" r="${c.r}" fill="${_xmlEscape(fill)}" $stroke opacity="$op"/>';
    }(),
    DotCommand c => '<circle cx="${c.x}" cy="${c.y}" r="${c.r}" fill="${_xmlEscape(_cssColor(c.fill))}" opacity="$op"/>',
    LineCommand c => () {
      final pts = <String>[];
      for (var i = 0; i + 1 < c.points.length; i += 2) {
        pts.add('${c.points[i]},${c.points[i + 1]}');
      }
      return '<polyline points="${pts.join(' ')}" stroke="${_xmlEscape(_cssColor(c.stroke))}" '
          'stroke-width="${c.lineWidth ?? 2}" fill="none" opacity="$op"/>';
    }(),
    SlashCommand c =>
      '<line x1="${c.x - c.r}" y1="${c.y + c.r}" x2="${c.x + c.r}" y2="${c.y - c.r}" '
          'stroke="${_xmlEscape(_cssColor(c.stroke))}" stroke-width="${c.lineWidth ?? 2}" opacity="$op"/>',
    BadgeCommand c => () {
      final fill = c.fill != null ? _cssColor(c.fill!) : '#fff';
      final fs = c.fontSize ?? 12;
      return '<text x="${c.x}" y="${c.y}" text-anchor="middle" dominant-baseline="central" '
          'font-size="$fs" fill="${_xmlEscape(fill)}" opacity="$op">${_xmlEscape(c.text)}</text>';
    }(),
    RectCommand c => () {
      final fill = c.fill != null ? _cssColor(c.fill!) : 'none';
      final stroke = c.stroke != null ? 'stroke="${_xmlEscape(_cssColor(c.stroke!))}"' : '';
      final rx = c.radius != null ? 'rx="${c.radius}"' : '';
      return '<rect x="${c.x}" y="${c.y}" width="${c.w}" height="${c.h}" '
          'fill="${_xmlEscape(fill)}" $stroke $rx opacity="$op"/>';
    }(),
  };
}

/// 将路布局和主题渲染为完整 SVG 字符串（零 Flutter 依赖）。
///
/// ```dart
/// final svg = renderToSvg(layout, defaultTheme, grid: true);
/// File('output.svg').writeAsStringSync(svg);
/// ```
String renderToSvg(RoadLayout layout, Theme theme, {double? width, double? height, bool grid = false}) {
  final w = width ?? layout.contentWidth;
  final h = height ?? layout.contentHeight;

  final parts = <String>[];

  // 背景。
  parts.add('<rect x="0" y="0" width="$w" height="$h" fill="${_xmlEscape(_cssColor(theme.canvas.background))}"/>');

  // 网格线。
  if (grid) {
    const cs = 36.0; // SVG 网格默认格子尺寸。
    final stroke = _xmlEscape(_cssColor(theme.grid.stroke));
    final lw = theme.grid.lineWidth;
    for (var x = 0.0; x <= w; x += cs) {
      parts.add('<line x1="$x" y1="0" x2="$x" y2="$h" stroke="$stroke" stroke-width="$lw"/>');
    }
    for (var y = 0.0; y <= h; y += cs) {
      parts.add('<line x1="0" y1="$y" x2="$w" y2="$y" stroke="$stroke" stroke-width="$lw"/>');
    }
  }

  // decorations。
  for (final cmd in layout.decorations ?? const <DrawCommand>[]) {
    parts.add(_commandToSvg(cmd));
  }

  // cells。
  for (final cell in layout.cells) {
    for (final cmd in cell.commands) {
      parts.add(_commandToSvg(cmd));
    }
  }

  final body = parts.where((p) => p.isNotEmpty).join('\n  ');

  return '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<svg xmlns="http://www.w3.org/2000/svg" width="$w" height="$h" viewBox="0 0 $w $h">\n'
      '  $body\n'
      '</svg>';
}
