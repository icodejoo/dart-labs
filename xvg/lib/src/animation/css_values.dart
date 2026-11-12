import 'css_animation_values.dart';
import 'css_chars.dart';

/// 带单位的数值，无单位时 [unit] 为空串。
typedef CssDimension = ({double value, String unit});

/// 数值加可选单位（字母或百分号）的词法，指数写法优先于单位。
final _dimensionPattern = RegExp(
  r'^([+-]?(?:\d+(?:\.\d+)?|\.\d+)(?:[eE][+-]?\d+)?)([a-zA-Z]+|%)?$',
);

/// 解析一个带可选单位的数值。
///
/// 参数 [token] 是单个词元，数字支持 `.5`、`+3`、`1e2`，不接受 `1.` 与内部空白。
/// 返回数值与小写单位；语法不符或数值溢出为非有限时返回空值。
///
/// ```dart
/// final d = parseCssDimension('-1.5PX'); // (value: -1.5, unit: 'px')
/// ```
CssDimension? parseCssDimension(String token) {
  final match = _dimensionPattern.firstMatch(token.trim());
  if (match == null) return null;
  final number = double.tryParse(match[1]!);
  if (number == null || !number.isFinite) return null;
  return (value: number, unit: (match[2] ?? '').toLowerCase());
}

/// 解析不带单位的纯数值。
///
/// 参数 [token] 是单个词元。
/// 返回数值；带单位或语法不符时返回空值。
///
/// ```dart
/// final n = parseCssNumber('+.5'); // 0.5
/// ```
double? parseCssNumber(String token) {
  final d = parseCssDimension(token);
  return d != null && d.unit.isEmpty ? d.value : null;
}

/// 解析像素长度，无单位的数视为像素。
///
/// 参数 [value] 是完整的长度值。
/// 返回像素数；其他单位、百分比或非法写法返回空值。
///
/// ```dart
/// final a = parseCssLengthPx('-1.5px'); // -1.5
/// final b = parseCssLengthPx('50%'); // null
/// ```
double? parseCssLengthPx(String value) {
  final d = parseCssDimension(value);
  return d != null && (d.unit.isEmpty || d.unit == 'px') ? d.value : null;
}

/// 解析百分数。
///
/// 参数 [value] 是完整的百分数值。
/// 返回换算后的比例，允许大于一或小于零；不是百分数时返回空值。
///
/// ```dart
/// final p = parseCssPercent('12.5%'); // 0.125
/// ```
double? parseCssPercent(String value) {
  final d = parseCssDimension(value);
  return d != null && d.unit == '%' ? d.value / 100 : null;
}

/// 字符编码。
const _hash = 35,
    _rightParen = 41,
    _comma = 44,
    _backslash = 92,
    _singleQuote = 39,
    _doubleQuote = 34,
    _lf = 10,
    _cr = 13,
    _ff = 12;

/// 颜色分量上限。
const _maxChannel = 255;

/// 解析十六进制与 `rgb()`/`rgba()` 颜色，具名颜色不在此处理。
///
/// 参数 [value] 是完整的颜色值，函数名与 `transparent` 不区分大小写。
/// 返回 `0xAARRGGBB`；具名颜色、`currentcolor`、`hsl()` 及非法写法返回空值。
///
/// ```dart
/// final a = parseCssColor('#f80'); // 0xFFFF8800
/// final b = parseCssColor('rgb(0 128 255 / 50%)'); // 0x800080FF
/// ```
int? parseCssColor(String value) {
  final text = value.trim();
  if (text.isEmpty) return null;
  if (text.codeUnitAt(0) == _hash) return _hexColor(text);
  if (text.toLowerCase() == 'transparent') return 0;
  final open = text.indexOf('(');
  if (open < 0 || text.codeUnitAt(text.length - 1) != _rightParen) return null;
  final name = text.substring(0, open).toLowerCase();
  if (name != 'rgb' && name != 'rgba') return null;
  return _rgbColor(text.substring(open + 1, text.length - 1));
}

/// 解析以井号开头的三、四、六、八位十六进制颜色。
int? _hexColor(String text) {
  final digits = text.length - 1;
  if (digits != 3 && digits != 4 && digits != 6 && digits != 8) return null;
  final short = digits <= 4;
  var bits = 0;
  for (var i = 1; i <= digits; i++) {
    final h = cssHexValue(text.codeUnitAt(i));
    if (h < 0) return null;
    bits = short ? (bits << 8) | (h * 17) : (bits << 4) | h;
  }
  // bits 为 RRGGBB 或 RRGGBBAA。
  return digits == 4 || digits == 8
      ? ((bits & _maxChannel) << 24) | (bits >> 8)
      : 0xFF000000 | bits;
}

/// 解析函数括号内的逗号语法或空格斜杠语法。
int? _rgbColor(String body) {
  final comma = body.contains(',');
  List<String> channels;
  String? alpha;
  if (comma) {
    channels = [for (final part in body.split(',')) part.trim()];
    if (channels.length == 4) alpha = channels.removeLast();
  } else {
    final slash = body.indexOf('/');
    if (slash >= 0) alpha = body.substring(slash + 1).trim();
    channels = splitCssTokens(slash >= 0 ? body.substring(0, slash) : body);
  }
  if (channels.length != 3) return null;
  var percents = 0, rgb = 0;
  for (final channel in channels) {
    final byte = _component(channel, 1);
    if (byte == null) return null;
    if (channel.endsWith('%')) percents++;
    rgb = (rgb << 8) | byte;
  }
  // 逗号语法不允许数值与百分数混用。
  if (comma && percents != 0 && percents != 3) return null;
  final a = alpha == null ? _maxChannel : _component(alpha, _maxChannel);
  return a == null ? null : (a << 24) | rgb;
}

/// 把数值或百分数换算成钳制后的字节，[scale] 是数值写法对应的倍率。
int? _component(String token, int scale) {
  final d = parseCssDimension(token);
  if (d == null) return null;
  final raw = switch (d.unit) {
    '' => d.value * scale,
    '%' => d.value * _maxChannel / 100,
    _ => null,
  };
  return raw?.clamp(0, _maxChannel).round();
}

/// 路径函数名加左括号。
const _pathOpen = 'path(';

/// 解析 `path()` 函数并返回解码后的路径数据。
///
/// 参数 [value] 是完整的函数值，函数名不区分大小写；可带 `evenodd` 或
/// `nonzero` 首参，但填充规则不在返回值中体现。
/// 返回路径字符串；引号不成对、路径为空、`none` 或其他写法返回空值。
///
/// ```dart
/// final d = parseCssPathFunction('path(evenodd, "M0,0 L10,10")');
/// ```
String? parseCssPathFunction(String value) {
  final text = value.trim();
  final end = text.length - 1;
  if (end < _pathOpen.length ||
      text.codeUnitAt(end) != _rightParen ||
      text.substring(0, _pathOpen.length).toLowerCase() != _pathOpen) {
    return null;
  }
  var i = _skipSpace(text, _pathOpen.length, end);
  if (i < end && !_isQuote(text.codeUnitAt(i))) {
    final start = i;
    while (i < end && isCssNameChar(text.codeUnitAt(i))) {
      i++;
    }
    final rule = text.substring(start, i).toLowerCase();
    if (rule != 'evenodd' && rule != 'nonzero') return null;
    i = _skipSpace(text, i, end);
    if (i >= end || text.codeUnitAt(i) != _comma) return null;
    i = _skipSpace(text, i + 1, end);
  }
  if (i >= end || !_isQuote(text.codeUnitAt(i))) return null;
  final string = _readString(text, i, end);
  if (string == null || _skipSpace(text, string.next, end) != end) return null;
  return string.text.trim().isEmpty ? null : string.text;
}

/// 判断是否为引号字符。
bool _isQuote(int c) => c == _singleQuote || c == _doubleQuote;

/// 从 [start] 起跳过空白，最多到 [end]，返回第一个非空白位置。
int _skipSpace(String s, int start, int end) {
  while (start < end && isCssSpace(s.codeUnitAt(start))) {
    start++;
  }
  return start;
}

/// 从 [start] 处的引号起解码 CSS 字符串，扫描范围止于 [end]。
///
/// 返回解码文本及闭合引号之后的位置；未闭合或含裸换行时返回空值。
({String text, int next})? _readString(String s, int start, int end) {
  final quote = s.codeUnitAt(start);
  final out = StringBuffer();
  var i = start + 1;
  while (i < end) {
    final c = s.codeUnitAt(i++);
    if (c == quote) return (text: out.toString(), next: i);
    if (c == _lf || c == _cr || c == _ff) return null;
    if (c != _backslash) {
      out.writeCharCode(c);
      continue;
    }
    if (i >= end) return null;
    final next = s.codeUnitAt(i);
    if (cssHexValue(next) >= 0) {
      var code = 0, digits = 0;
      while (i < end && digits < 6 && cssHexValue(s.codeUnitAt(i)) >= 0) {
        code = code * 16 + cssHexValue(s.codeUnitAt(i++));
        digits++;
      }
      // 十六进制转义后可带一个空白，回车换行算一个。
      if (i < end && isCssSpace(s.codeUnitAt(i))) {
        if (s.codeUnitAt(i++) == _cr && i < end && s.codeUnitAt(i) == _lf) i++;
      }
      final invalid = code == 0 || code > 0x10ffff;
      out.writeCharCode(
        invalid || (code >= 0xd800 && code <= 0xdfff) ? 0xfffd : code,
      );
    } else if (next == _lf || next == _cr || next == _ff) {
      // 反斜杠加换行是续行，不产生字符。
      i++;
      if (next == _cr && i < end && s.codeUnitAt(i) == _lf) i++;
    } else {
      out.writeCharCode(next);
      i++;
    }
  }
  return null;
}
