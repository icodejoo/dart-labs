// Presentation-attribute resolution: inheritance down the element tree,
// `currentColor` substitution, and colour parsing for the small subset of
// SVG presentation attributes this engine paints with. Original
// implementation of standard, publicly documented SVG semantics.
//
// 表现属性解析：沿元素树向下继承、`currentColor` 替换，以及本引擎绘制所需的
// 一小部分 SVG 表现属性的颜色解析。对标准、公开的 SVG 语义的原创实现。

import 'package:flutter/painting.dart';

import 'svg_theme.dart';

/// A fully-resolved set of presentation attributes for one element, after
/// inheritance from ancestors and `currentColor` substitution.
///
/// 一个元素在继承祖先属性、替换 `currentColor` 后，完全解析出的表现属性集合。
class ResolvedStyle {
  /// Creates a resolved style. / 创建一个已解析样式。
  const ResolvedStyle({
    required this.fill,
    required this.stroke,
    required this.strokeWidth,
    required this.strokeLinecap,
    required this.strokeLinejoin,
    required this.strokeDasharray,
    required this.strokeDashoffset,
    required this.opacity,
    this.fillGradientId,
    this.strokeGradientId,
  });

  /// Gradient id from `fill="url(#id)"`, when the fill is a gradient paint
  /// rather than a colour (in which case [fill] is null).
  ///
  /// 来自 `fill="url(#id)"` 的渐变 id；填充为渐变涂料而非纯色时使用（此时
  /// [fill] 为 null）。
  final String? fillGradientId;

  /// Gradient id from `stroke="url(#id)"`; see [fillGradientId].
  ///
  /// 来自 `stroke="url(#id)"` 的渐变 id；见 [fillGradientId]。
  final String? strokeGradientId;

  /// SVG's initial style: black fill, no stroke, 1px stroke width.
  ///
  /// SVG 的初始样式：黑色填充、无描边、1px 描边宽度。
  static const ResolvedStyle initial = ResolvedStyle(
    fill: Color(0xFF000000),
    stroke: null,
    strokeWidth: 1,
    strokeLinecap: StrokeCap.butt,
    strokeLinejoin: StrokeJoin.miter,
    strokeDasharray: <double>[],
    strokeDashoffset: 0,
    opacity: 1,
  );

  /// Fill color, or null for `fill="none"`. / 填充色，`fill="none"` 时为 null。
  final Color? fill;

  /// Stroke color, or null for `stroke="none"`/unset. / 描边色，未设置时为 null。
  final Color? stroke;

  /// Stroke width in user units. / 描边宽度（用户单位）。
  final double strokeWidth;

  /// Stroke cap style. / 描边端点样式。
  final StrokeCap strokeLinecap;

  /// Stroke join style. / 描边连接样式。
  final StrokeJoin strokeLinejoin;

  /// Dash pattern; empty means a solid stroke. / 虚线图案，空表示实线。
  final List<double> strokeDasharray;

  /// Dash phase offset. / 虚线相位偏移。
  final double strokeDashoffset;

  /// Element opacity in `[0, 1]`. / 元素不透明度，范围 `[0, 1]`。
  final double opacity;

  /// Returns a copy with attributes found in [attributes] overriding the
  /// inherited ones in `this`, resolving `currentColor` against [theme].
  ///
  /// 返回一份拷贝，用 [attributes] 中存在的属性覆盖 `this` 继承来的值，并按
  /// [theme] 解析 `currentColor`。
  ResolvedStyle inherit(Map<String, String> attributes, SvgTheme theme) {
    Color? parseColor(String raw) {
      final v = raw.trim();
      if (v == 'none') return null;
      if (v == 'currentColor') return theme.currentColor;
      return parseSvgHexColor(v);
    }

    /// A `url(#id)` paint reference, or null when the value isn't one.
    /// `url(#id)` 涂料引用；不是引用时返回 null。
    String? gradientId(String? raw) {
      if (raw == null) return null;
      final v = raw.trim();
      if (!v.startsWith('url(') || !v.endsWith(')')) return null;
      final inner = v.substring(4, v.length - 1).trim().replaceAll("'", '').replaceAll('"', '');
      return inner.startsWith('#') ? inner.substring(1) : null;
    }

    return ResolvedStyle(
      fill: attributes.containsKey('fill') ? parseColor(attributes['fill']!) : fill,
      stroke: attributes.containsKey('stroke') ? parseColor(attributes['stroke']!) : stroke,
      fillGradientId:
          attributes.containsKey('fill') ? gradientId(attributes['fill']) : fillGradientId,
      strokeGradientId:
          attributes.containsKey('stroke') ? gradientId(attributes['stroke']) : strokeGradientId,
      strokeWidth: double.tryParse(attributes['stroke-width'] ?? '') ?? strokeWidth,
      strokeLinecap: switch (attributes['stroke-linecap']) {
        'round' => StrokeCap.round,
        'square' => StrokeCap.square,
        'butt' => StrokeCap.butt,
        _ => strokeLinecap,
      },
      strokeLinejoin: switch (attributes['stroke-linejoin']) {
        'round' => StrokeJoin.round,
        'bevel' => StrokeJoin.bevel,
        'miter' => StrokeJoin.miter,
        _ => strokeLinejoin,
      },
      strokeDasharray: attributes.containsKey('stroke-dasharray')
          ? _parseDasharray(attributes['stroke-dasharray']!)
          : strokeDasharray,
      strokeDashoffset:
          double.tryParse(attributes['stroke-dashoffset'] ?? '') ?? strokeDashoffset,
      opacity: double.tryParse(attributes['opacity'] ?? '') ?? opacity,
    );
  }
}

List<double> _parseDasharray(String raw) {
  final v = raw.trim();
  if (v.isEmpty || v == 'none') return const [];
  return v
      .split(RegExp(r'[\s,]+'))
      .where((s) => s.isNotEmpty)
      .map((s) => double.tryParse(s) ?? 0)
      .toList();
}

/// Parses `#RGB`/`#RRGGBB`/`#RRGGBBAA` hex colours, or null for anything else.
///
/// Hex is the only literal form this per-frame path handles, on purpose: CSS
/// named colours (`red`, `cornflowerblue`) are resolved to hex **once**, at
/// document-parse time, by the Rust `parse_color` (see
/// `native_svg_values.dart`), so no colour table is needed here.
///
/// 解析 `#RGB`/`#RRGGBB`/`#RRGGBBAA` 十六进制颜色；其它一律返回 null。
///
/// 逐帧路径刻意只处理十六进制这一种字面形式：CSS 具名颜色（`red`、
/// `cornflowerblue`）已由 Rust 的 `parse_color` 在文档解析阶段**一次性**转成
/// 十六进制（见 `native_svg_values.dart`），因此这里不需要颜色表。
///
/// Example:
/// ```dart
/// parseSvgHexColor('#FF7A00'); // Color(0xFFFF7A00)
/// ```
Color? parseSvgHexColor(String v) {
  if (!v.startsWith('#')) return null;
  final hex = v.substring(1);
  int channel(String s) => int.parse(s.length == 1 ? s * 2 : s, radix: 16);
  switch (hex.length) {
    case 3:
      return Color.fromARGB(255, channel(hex[0]), channel(hex[1]), channel(hex[2]));
    case 6:
      return Color(0xFF000000 | int.parse(hex, radix: 16));
    case 8:
      final a = channel(hex.substring(6, 8));
      final rgb = int.parse(hex.substring(0, 6), radix: 16);
      return Color((a << 24) | rgb);
    default:
      return null;
  }
}
