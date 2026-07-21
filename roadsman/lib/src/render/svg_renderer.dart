/// SVG renderer ([renderToSvg]).
///
/// A pure function with no dependency on `dart:ui`/Flutter, so it can run
/// directly in a pure Dart (server/CLI) environment. Converts [RoadLayout] +
/// [Theme] into a complete `<svg>...</svg>` string, for server-side image
/// generation, share cards, report emails. Ported from
/// `src/renderer-svg/svg-renderer.ts`.
library;

import '../core/types.dart';

/// Options for [renderToSvg].
class SvgRenderOptions {
  /// Output SVG width (px), defaults to `layout.contentWidth`.
  final double? width;

  /// Output SVG height (px), defaults to `layout.contentHeight`.
  final double? height;

  /// Whether to draw grid lines, defaults to false.
  final bool grid;

  const SvgRenderOptions({this.width, this.height, this.grid = false});
}

/// XML escaping (prevents text content from breaking the SVG structure).
String _xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

/// Converts an ARGB 32-bit integer color into an `rgba(r,g,b,a)` CSS string
/// (keeping its own alpha channel; the SVG `opacity` attribute then layers on
/// the [DrawCommand.alpha] animation-interpolated alpha on top, and
/// multiplying the two matches SVG's own semantics).
String _cssColor(int argb) {
  final a = ((argb >> 24) & 0xFF) / 255;
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  return 'rgba($r,$g,$b,${a.toStringAsFixed(3)})';
}

/// Converts a single [DrawCommand] into an SVG element string.
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

/// Renders a road layout and theme into a complete SVG string (zero Flutter
/// dependency).
///
/// ```dart
/// final svg = renderToSvg(layout, defaultTheme, grid: true);
/// File('output.svg').writeAsStringSync(svg);
/// ```
String renderToSvg(RoadLayout layout, Theme theme, {double? width, double? height, bool grid = false}) {
  final w = width ?? layout.contentWidth;
  final h = height ?? layout.contentHeight;

  final parts = <String>[];

  // Background.
  parts.add('<rect x="0" y="0" width="$w" height="$h" fill="${_xmlEscape(_cssColor(theme.canvas.background))}"/>');

  // Grid lines.
  if (grid) {
    const cs = 36.0; // Default SVG grid cell size.
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
