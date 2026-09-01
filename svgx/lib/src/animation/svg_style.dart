// Presentation-attribute resolution: inheritance down the element tree,
// `currentColor` substitution, and colour parsing for the small subset of
// SVG presentation attributes this engine paints with. Original
// implementation of standard, publicly documented SVG semantics.
//
// 表现属性解析：沿元素树向下继承、`currentColor` 替换，以及本引擎绘制所需的
// 一小部分 SVG 表现属性的颜色解析。对标准、公开的 SVG 语义的原创实现。

import 'package:flutter/painting.dart';

import 'svg_dom.dart';
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
  ResolvedStyle inherit(Map<String, String> attributes, SvgxTheme theme) {
    Color? parseColor(String raw) {
      final v = raw.trim();
      if (v == 'none') return null;
      if (v == 'currentColor') return theme.currentColor;
      return parseSvgHexColor(v);
    }

    return ResolvedStyle(
      fill: attributes.containsKey('fill')
          ? parseColor(attributes['fill']!)
          : fill,
      stroke: attributes.containsKey('stroke')
          ? parseColor(attributes['stroke']!)
          : stroke,
      fillGradientId: attributes.containsKey('fill')
          ? parseUrlId(attributes['fill'])
          : fillGradientId,
      strokeGradientId: attributes.containsKey('stroke')
          ? parseUrlId(attributes['stroke'])
          : strokeGradientId,
      strokeWidth:
          double.tryParse(attributes['stroke-width'] ?? '') ?? strokeWidth,
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
          double.tryParse(attributes['stroke-dashoffset'] ?? '') ??
          strokeDashoffset,
      opacity: double.tryParse(attributes['opacity'] ?? '') ?? opacity,
    );
  }
}

/// Memo for [_parseDasharray], keyed by the raw attribute string.
///
/// `stroke-dasharray` is re-resolved on every node on every frame (see
/// [ResolvedStyle.inherit]), yet its value is a pure function of a string that
/// almost never changes: `d`-style geometry is what animates in a line-md
/// icon, the dash *pattern* is a constant like `"24"` while only
/// `stroke-dashoffset` moves. So the parse is memoized rather than repeated
/// ~60 times a second per dashed element.
///
/// Cardinality is what makes this safe: a document set uses a handful of
/// distinct dash patterns, so [_dasharrayMemoLimit] is never reached in
/// practice. Past the limit the memo is dropped wholesale (a generational
/// clear, no LRU bookkeeping on the read path) and refills.
///
/// [_parseDasharray] 的记忆表，键为原始属性字符串。
///
/// `stroke-dasharray` 每帧、每个节点都会被重新解析（见
/// [ResolvedStyle.inherit]），但它是一个几乎不变的字符串的纯函数：line-md 风格
/// 图标里动的是 `stroke-dashoffset`，虚线*图案*本身是 `"24"` 这样的常量。因此把
/// 解析结果记下来，而不是每秒对每个虚线元素重复约 60 次。
///
/// 低基数是这么做安全的前提：一批文档只会用到少数几种虚线图案，实践中根本触
/// 不到 [_dasharrayMemoLimit]。超限时整表丢弃重建（分代式清空，读路径上不做
/// LRU 记账）。
final Map<String, List<double>> _dasharrayMemo = <String, List<double>>{};

/// Entry cap for [_dasharrayMemo] — see that field.
///
/// [_dasharrayMemo] 的条目上限——见该字段。
const int _dasharrayMemoLimit = 256;

/// Parses a `stroke-dasharray` attribute value into its dash lengths, or an
/// empty list for `none`/blank. Results are memoized — see [_dasharrayMemo].
///
/// 把 `stroke-dasharray` 属性值解析为各段长度；`none`/空值返回空列表。结果会被
/// 记忆——见 [_dasharrayMemo]。
List<double> _parseDasharray(String raw) {
  final memoized = _dasharrayMemo[raw];
  if (memoized != null) return memoized;
  final parsed = _parseDasharrayUncached(raw);
  if (_dasharrayMemo.length >= _dasharrayMemoLimit) _dasharrayMemo.clear();
  _dasharrayMemo[raw] = parsed;
  return parsed;
}

/// The uncached parse behind [_parseDasharray].
///
/// Splits on runs of whitespace/commas with a hand-rolled scan instead of
/// `String.split(RegExp(...))`: the regex form allocates a match iterator, an
/// intermediate `List<String>`, and three lazy-iterable wrappers for a value
/// that is usually one or two numbers long.
///
/// [_parseDasharray] 背后的无缓存解析。
///
/// 用手写扫描按空白/逗号连续段切分，而不是 `String.split(RegExp(...))`：正则写法
/// 要为一个通常只有一两个数字的值分配匹配迭代器、中间 `List<String>` 和三层惰性
/// 可迭代包装。
List<double> _parseDasharrayUncached(String raw) {
  final v = raw.trim();
  if (v.isEmpty || v == 'none') return const [];
  final values = <double>[];
  var start = -1;
  for (var i = 0; i <= v.length; i++) {
    final isSeparator =
        i == v.length ||
        switch (v.codeUnitAt(i)) {
          0x20 || 0x09 || 0x0A || 0x0D || 0x0C || 0x2C => true,
          _ => false,
        };
    if (isSeparator) {
      if (start >= 0) {
        values.add(double.tryParse(v.substring(start, i)) ?? 0);
        start = -1;
      }
    } else if (start < 0) {
      start = i;
    }
  }
  return values.isEmpty ? const [] : List<double>.of(values, growable: false);
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
// Digits are read straight out of [v] with `codeUnitAt` instead of being cut
// out with `substring`/`operator []` and handed to `int.parse`. This runs once
// per coloured attribute per node per frame on the animation path, and the
// string-slicing form allocated on every call: one substring for `#RRGGBB`,
// and seven strings for `#RGB` (a substring, then a one-character string plus
// a doubled string per channel). Malformed digits now yield null instead of
// throwing a `FormatException`, which matches what this function already does
// for a wrong-length value.
//
// 各位十六进制数字直接用 `codeUnitAt` 从 [v] 里读，而不是先用
// `substring`/`operator []` 切出来再交给 `int.parse`。动画路径上，本函数每帧、
// 每个节点、每个颜色属性都要跑一次，而切字符串的写法每次调用都要分配：
// `#RRGGBB` 一个 substring，`#RGB` 则是七个字符串（一个 substring，外加每个通道
// 一个单字符串和一个翻倍串）。非法数字现在返回 null 而不是抛
// `FormatException`——这与本函数对长度不合法的值本就采取的做法一致。
Color? parseSvgHexColor(String v) {
  if (v.isEmpty || v.codeUnitAt(0) != 0x23) return null;
  switch (v.length) {
    case 4: // #RGB
      final r = _hexDigit(v, 1);
      final g = _hexDigit(v, 2);
      final b = _hexDigit(v, 3);
      if (r < 0 || g < 0 || b < 0) return null;
      // Each nibble is duplicated into a full byte: 0xF -> 0xFF.
      // 每个半字节复制成一个完整字节：0xF -> 0xFF。
      return Color(
        0xFF000000 | (r * 0x11) << 16 | (g * 0x11) << 8 | (b * 0x11),
      );
    case 7: // #RRGGBB
      final rgb = _hexByte(v, 1, 3);
      return rgb < 0 ? null : Color(0xFF000000 | rgb);
    case 9: // #RRGGBBAA
      final rgb = _hexByte(v, 1, 3);
      final a = _hexByte(v, 7, 1);
      if (rgb < 0 || a < 0) return null;
      return Color((a << 24) | rgb);
    default:
      return null;
  }
}

/// The hex value of the digit at [index] in [v], or -1 when it isn't one.
///
/// [v] 中 [index] 处十六进制数字的值；不是十六进制数字时返回 -1。
int _hexDigit(String v, int index) {
  final c = v.codeUnitAt(index);
  if (c >= 0x30 && c <= 0x39) return c - 0x30; // 0-9
  if (c >= 0x61 && c <= 0x66) return c - 0x57; // a-f
  if (c >= 0x41 && c <= 0x46) return c - 0x37; // A-F
  return -1;
}

/// [byteCount] hex byte pairs of [v] starting at [start], packed big-endian
/// into one int, or -1 when any digit is invalid.
///
/// 从 [start] 开始读 [v] 的 [byteCount] 组十六进制字节对，按大端打包成一个整数；
/// 任一数字非法时返回 -1。
int _hexByte(String v, int start, int byteCount) {
  var value = 0;
  final end = start + byteCount * 2;
  for (var i = start; i < end; i++) {
    final digit = _hexDigit(v, i);
    if (digit < 0) return -1;
    value = (value << 4) | digit;
  }
  return value;
}
