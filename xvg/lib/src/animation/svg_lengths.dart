import 'dart:math' as math;

import 'number_syntax.dart';

/// Initial SVG font size in user units. / SVG 初始字号（用户单位）。
const svgInitialFontSize = 16.0;

/// The CSS default object size. / CSS 默认对象尺寸。
const svgDefaultWidth = 300.0, svgDefaultHeight = 150.0;

/// SVG's supported length grammar. / 支持的 SVG 长度语法。
final _lengthPattern = RegExp(
  '^($numberSyntax)(px|pt|pc|mm|cm|in|em|ex|%)?\$',
  caseSensitive: false,
);

/// Resolves a length against its percentage and font bases. / 按百分比基准与字号换算 SVG 长度。
double? resolveSvgLength(
  String? raw, {
  double? percentageBase,
  double fontSize = svgInitialFontSize,
}) {
  if (raw == null) return null;
  final number = double.tryParse(raw);
  if (number != null) return number.isFinite ? number : null;
  final match = _lengthPattern.firstMatch(raw.trim());
  if (match == null) return null;
  final factor = switch (match[2]?.toLowerCase()) {
    'pt' => 96 / 72,
    'pc' => 16.0,
    'mm' => 96 / 25.4,
    'cm' => 96 / 2.54,
    'in' => 96.0,
    'em' => fontSize,
    'ex' => fontSize / 2,
    '%' => percentageBase == null ? null : percentageBase / 100,
    _ => 1.0,
  };
  if (factor == null) return null;
  final value = double.parse(match[1]!) * factor;
  return value.isFinite ? value : null;
}

/// Normalized diagonal for nondirectional percentages. / 非定向百分比所用的归一化对角线。
double svgNormalizedDiagonal(double width, double height) =>
    math.sqrt((width * width + height * height) / 2);

/// A viewBox requires four comma/whitespace-separated numbers. / viewBox 需要四个以逗号或空白分隔的数。
final _viewBoxPattern = RegExp(
  '^\\s*($numberSyntax)'
  '${List.filled(3, '(?:\\s*,\\s*|\\s+)($numberSyntax)').join()}'
  r'\s*$',
);

/// Reads a finite, positive-size viewBox. / 读取有限且宽高为正的 viewBox。
List<double>? parseSvgViewBox(String? raw) {
  final match = _viewBoxPattern.firstMatch(raw ?? '');
  if (match == null) return null;
  final values = [for (var i = 1; i <= 4; i++) double.parse(match[i]!)];
  return values.every((value) => value.isFinite) &&
          values[2] > 0 &&
          values[3] > 0
      ? List.unmodifiable(values)
      : null;
}

/// Alignment grammar with optional SVG 1.1 defer. / 兼容 SVG 1.1 可选 defer 的对齐语法。
final _aspectRatioPattern = RegExp(
  r'^(?:defer\s+)?(none|x(Min|Mid|Max)Y(Min|Mid|Max))(?:\s+(meet|slice))?$',
);

/// Maps a viewBox into a viewport per SVG 2 §8.2. / 按 SVG 2 §8.2 将 viewBox 映射到视口。
List<double>? svgViewportTransform(
  List<double>? viewBox,
  double width,
  double height,
  String? aspectRatio,
) {
  if (viewBox == null) return null;
  final match = _aspectRatioPattern.firstMatch(aspectRatio?.trim() ?? '');
  var sx = width / viewBox[2];
  var sy = height / viewBox[3];
  var ax = .5;
  var ay = .5;
  if (match?[1] == 'none') {
    ax = ay = 0;
  } else {
    sx = sy = match?[4] == 'slice' ? math.max(sx, sy) : math.min(sx, sy);
    const alignmentFactors = {'Min': 0.0, 'Mid': .5, 'Max': 1.0};
    ax = alignmentFactors[match?[2]] ?? .5;
    ay = alignmentFactors[match?[3]] ?? .5;
  }
  final tx = -viewBox[0] * sx + (width - viewBox[2] * sx) * ax;
  final ty = -viewBox[1] * sy + (height - viewBox[3] * sy) * ay;
  if (sx == 1 && sy == 1 && tx == 0 && ty == 0) return null;
  return List.unmodifiable([sx, 0.0, 0.0, sy, tx, ty]);
}
