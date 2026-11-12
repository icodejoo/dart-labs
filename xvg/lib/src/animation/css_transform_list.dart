import 'dart:math' as math;

import 'css_chars.dart';
import 'css_values.dart';

/// 变换操作的种类。
enum CssTransformKind {
  /// 平移，参数为横纵位移。
  translate,

  /// 缩放，参数为横纵倍率。
  scale,

  /// 旋转，参数为角度。
  rotate,

  /// 沿横轴倾斜，参数为角度。
  skewX,

  /// 沿纵轴倾斜，参数为角度。
  skewY,

  /// 任意矩阵，参数为六个分量。
  matrix,
}

/// 一个已归一化的变换操作。
class CssTransformOp {
  /// 创建变换操作。
  const CssTransformOp(this.kind, this.args);

  /// 操作种类。
  final CssTransformKind kind;

  /// 参数，长度与单位由 [kind] 决定。
  ///
  /// 平移为像素 `[x, y]`；缩放为 `[x, y]`；旋转与倾斜为单个角度（单位度）；
  /// 矩阵按 SVG 顺序为 `[a, b, c, d, e, f]`。
  final List<double> args;

  /// 比较种类与全部参数。
  @override
  bool operator ==(Object other) {
    if (other is! CssTransformOp ||
        kind != other.kind ||
        args.length != other.args.length) {
      return false;
    }
    for (var i = 0; i < args.length; i++) {
      if (args[i] != other.args[i]) return false;
    }
    return true;
  }

  /// 根据种类与全部参数生成散列。
  @override
  int get hashCode => Object.hash(kind, Object.hashAll(args));

  /// 返回便于诊断的操作文本。
  @override
  String toString() => '${kind.name}(${args.join(', ')})';
}

/// 左括号字符编码。
const _leftParen = 40;

/// 解析 `transform` 属性值为有序的操作列表。
///
/// 参数 [value] 是完整的属性值。支持 `translate`、`translateX/Y`、`scale`、
/// `scaleX/Y`、`rotate`、`rotateZ`、`skew`、`skewX/Y`、`matrix`，函数名不区分
/// 大小写；长度只接受像素或零，角度接受 `deg`、`rad`、`grad`、`turn` 或零。
/// 返回操作列表，`none` 为空列表；百分比、其他单位、三维函数、`var()`、
/// `calc()` 及任何非法写法都使整个值作废并返回空值。
///
/// ```dart
/// final ops = parseCssTransformList('translate(10px, 5px) rotate(.25turn)');
/// // [translate(10.0, 5.0), rotate(90.0)]
/// ```
List<CssTransformOp>? parseCssTransformList(String value) {
  final text = value.trim();
  if (text.isEmpty) return null;
  final ops = <CssTransformOp>[];
  if (text.toLowerCase() == 'none') return ops;
  var i = 0;
  while (i < text.length) {
    final start = i;
    while (i < text.length && isCssNameChar(text.codeUnitAt(i))) {
      i++;
    }
    if (i == start || i >= text.length || text.codeUnitAt(i) != _leftParen) {
      return null;
    }
    final close = text.indexOf(')', i + 1);
    if (close < 0) return null;
    final body = text.substring(i + 1, close);
    // 嵌套括号意味着 calc() 或 var()，不支持。
    if (body.contains('(')) return null;
    final op = _parseFunction(text.substring(start, i).toLowerCase(), body);
    if (op == null) return null;
    ops.add(op);
    i = close + 1;
    while (i < text.length && isCssSpace(text.codeUnitAt(i))) {
      i++;
    }
  }
  return ops;
}

/// 按函数名解析一个函数，[body] 是括号内的文本。
CssTransformOp? _parseFunction(String name, String body) {
  final raw = body.split(',');
  List<double>? v;
  switch (name) {
    case 'translate':
      v = _values(raw, 1, 2, _length);
      return v == null
          ? null
          : CssTransformOp(CssTransformKind.translate, [
              v[0],
              v.length > 1 ? v[1] : 0,
            ]);
    case 'translatex':
      v = _values(raw, 1, 1, _length);
      return v == null
          ? null
          : CssTransformOp(CssTransformKind.translate, [v[0], 0]);
    case 'translatey':
      v = _values(raw, 1, 1, _length);
      return v == null
          ? null
          : CssTransformOp(CssTransformKind.translate, [0, v[0]]);
    case 'scale':
      v = _values(raw, 1, 2, parseCssNumber);
      return v == null
          ? null
          : CssTransformOp(CssTransformKind.scale, [
              v[0],
              v.length > 1 ? v[1] : v[0],
            ]);
    case 'scalex':
      v = _values(raw, 1, 1, parseCssNumber);
      return v == null
          ? null
          : CssTransformOp(CssTransformKind.scale, [v[0], 1]);
    case 'scaley':
      v = _values(raw, 1, 1, parseCssNumber);
      return v == null
          ? null
          : CssTransformOp(CssTransformKind.scale, [1, v[0]]);
    case 'rotate':
    case 'rotatez':
      v = _values(raw, 1, 1, parseCssAngleDegrees);
      return v == null ? null : CssTransformOp(CssTransformKind.rotate, v);
    case 'skewx':
      v = _values(raw, 1, 1, parseCssAngleDegrees);
      return v == null ? null : CssTransformOp(CssTransformKind.skewX, v);
    case 'skewy':
      v = _values(raw, 1, 1, parseCssAngleDegrees);
      return v == null ? null : CssTransformOp(CssTransformKind.skewY, v);
    case 'skew':
      v = _values(raw, 1, 2, parseCssAngleDegrees);
      return v == null
          ? null
          : CssTransformOp(CssTransformKind.matrix, [
              1,
              _tan(v.length > 1 ? v[1] : 0),
              _tan(v[0]),
              1,
              0,
              0,
            ]);
    case 'matrix':
      v = _values(raw, 6, 6, parseCssNumber);
      return v == null ? null : CssTransformOp(CssTransformKind.matrix, v);
  }
  return null;
}

/// 逐个解析逗号分隔的参数，个数须在 [min] 到 [max] 之间，任一参数非法即返回空值。
List<double>? _values(
  List<String> raw,
  int min,
  int max,
  double? Function(String) parse,
) {
  if (raw.length < min || raw.length > max) return null;
  final out = <double>[];
  for (final item in raw) {
    final number = parse(item);
    if (number == null) return null;
    out.add(number);
  }
  return out;
}

/// 解析平移用的长度：像素，或恰好为零的无单位数。
double? _length(String token) {
  final d = parseCssDimension(token);
  if (d == null) return null;
  return d.unit == 'px' || (d.unit.isEmpty && d.value == 0) ? d.value : null;
}

/// 解析角度并换算为度：无单位只接受零，非有限数返回空。
///
/// ```dart
/// parseCssAngleDegrees('0.25turn'); // 90.0
/// ```
double? parseCssAngleDegrees(String token) {
  final d = parseCssDimension(token);
  if (d == null) return null;
  final degrees = switch (d.unit) {
    '' => d.value == 0 ? 0.0 : null,
    'deg' => d.value,
    'rad' => d.value * 180 / math.pi,
    'grad' => d.value * 360 / 400,
    'turn' => d.value * 360,
    _ => null,
  };
  return degrees != null && degrees.isFinite ? degrees : null;
}

/// 角度（度）的正切。
double _tan(double degrees) => math.tan(degrees * math.pi / 180);

/// 把有序的变换操作按 CSS 规则连乘，先写的在左。
///
/// 参数 [ops] 的参数个数须符合各自 [CssTransformOp.args] 的约定；
/// 极端大的参数相乘后结果可能不是有限数。
/// 返回 SVG 顺序的 `[a, b, c, d, e, f]`，空列表得到单位矩阵。
///
/// ```dart
/// final m = cssTransformMatrix(parseCssTransformList('translate(5px, 6px)')!);
/// // [1, 0, 0, 1, 5, 6]
/// ```
List<double> cssTransformMatrix(List<CssTransformOp> ops) {
  var a = 1.0, b = 0.0, c = 0.0, d = 1.0, e = 0.0, f = 0.0;
  for (final op in ops) {
    final m = _opMatrix(op);
    final na = a * m[0] + c * m[1];
    final nb = b * m[0] + d * m[1];
    final nc = a * m[2] + c * m[3];
    final nd = b * m[2] + d * m[3];
    final ne = a * m[4] + c * m[5] + e;
    final nf = b * m[4] + d * m[5] + f;
    a = na;
    b = nb;
    c = nc;
    d = nd;
    e = ne;
    f = nf;
  }
  return [a, b, c, d, e, f];
}

/// 把单个操作展开为 SVG 顺序的六分量矩阵。
List<double> _opMatrix(CssTransformOp op) {
  final v = op.args;
  switch (op.kind) {
    case CssTransformKind.translate:
      return [1, 0, 0, 1, v[0], v[1]];
    case CssTransformKind.scale:
      return [v[0], 0, 0, v[1], 0, 0];
    case CssTransformKind.rotate:
      final r = v[0] * math.pi / 180;
      final cos = math.cos(r), sin = math.sin(r);
      return [cos, sin, -sin, cos, 0, 0];
    case CssTransformKind.skewX:
      return [1, 0, _tan(v[0]), 1, 0, 0];
    case CssTransformKind.skewY:
      return [1, _tan(v[0]), 0, 1, 0, 0];
    case CssTransformKind.matrix:
      return v;
  }
}
