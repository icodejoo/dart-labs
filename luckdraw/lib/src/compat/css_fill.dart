import '../core/foundation/constants.dart';
import '../core/foundation/fill.dart';
import 'css_color.dart';
import 'json_reader.dart';

/// 有效线性渐变至少需要两个色标。
const int _minimumStops = 2;

/// CSS 与上游支持的线性渐变前缀。
const String _gradientPrefix = 'linear-gradient(';

/// 上游角度方向的单位后缀。
const String _degreeUnit = 'deg';

/// 解析背景为纯色或上游几何的线性渐变；非法值返回 null 并警告。
///
/// transparent（忽略大小写及首尾空白）表示无背景；rgba(0,0,0,0) 仍有背景。
/// 例如 linear-gradient(to right, red, blue) 返回 LuckyLegacyLinearFill。
LuckyFill? parseCssFill(Object? value, void Function(String message) warn) {
  if (value == null) return null;
  if (value is! String) {
    warn('背景必须是字符串');
    return null;
  }
  final text = value.trim().toLowerCase();
  if (text == kCompatTransparentKeyword) return null;
  if (!text.startsWith(_gradientPrefix)) {
    final color = parseCssColor(text, warn);
    return color == null ? null : LuckyFill.color(color);
  }
  if (!text.endsWith(')')) {
    warn('渐变缺少结束括号');
    return null;
  }
  final parts = splitCompatCommas(
      text.substring(_gradientPrefix.length, text.length - 1));
  if (parts == null || parts.length < _minimumStops + 1) {
    warn('渐变需要方向和至少两个色标');
    return null;
  }
  final source = parts.removeAt(0);
  final LuckyLegacyGradientDirection direction;
  if (source.contains(_degreeUnit)) {
    final angle = double.tryParse(
        source.substring(0, source.length - _degreeUnit.length));
    if (angle == null || !angle.isFinite) {
      warn('无效的渐变角度：$source');
      return null;
    }
    direction = LuckyLegacyGradientDirection.angle(angle);
  } else {
    // 上游 math.ts:114-119 按 top、bottom、left、right 的顺序匹配。
    final keyword = LuckyGradientKeyword.values.firstWhere(
        (keyword) =>
            keyword != LuckyGradientKeyword.none &&
            source.contains(keyword.name),
        orElse: () => LuckyGradientKeyword.none);
    direction = LuckyLegacyGradientDirection.keyword(keyword);
  }
  final stops = <LuckyColorStop>[];
  for (final token in parts) {
    var colorText = token;
    double? position;
    final prefix = RegExp(r'^(\S+)\s+(.+)$').firstMatch(token);
    if (prefix != null && _position(prefix[1]!) != null) {
      position = _position(prefix[1]!);
      colorText = prefix[2]!;
    } else {
      final suffix = RegExp(r'^(.+)\s+(\S+)$').firstMatch(token);
      if (suffix != null && _position(suffix[2]!) != null) {
        position = _position(suffix[2]!);
        colorText = suffix[1]!;
      }
    }
    final color = parseCssColor(colorText, warn);
    if (color == null) return null;
    if (position != null && (position < 0 || position > 1)) {
      warn('色标位置必须在 0 到 1 之间：$token');
      return null;
    }
    stops.add(LuckyColorStop(color, position));
  }
  // IMP-09：省略位置时按 CSS 在相邻显式色标之间均分。
  final offsets = stops.map((stop) => stop.offset).toList();
  offsets[0] ??= 0;
  offsets[offsets.length - 1] ??= 1;
  var anchor = 0;
  for (var index = 1; index < offsets.length; index++) {
    if (offsets[index] == null) continue;
    final end = offsets[index]!;
    final start = offsets[anchor]!;
    if (end < start) {
      warn('色标位置必须按升序排列');
      return null;
    }
    for (var missing = anchor + 1; missing < index; missing++) {
      offsets[missing] =
          start + (end - start) * (missing - anchor) / (index - anchor);
    }
    anchor = index;
  }
  return LuckyFill.legacyLinear(
      direction,
      List.unmodifiable([
        for (var index = 0; index < stops.length; index++)
          LuckyColorStop(stops[index].color, offsets[index]),
      ]));
}

/// 读取有限数值或百分比位置；颜色 token 返回 null。
double? _position(String value) {
  final percent = value.endsWith('%');
  final number =
      double.tryParse(percent ? value.substring(0, value.length - 1) : value);
  if (number == null || !number.isFinite) return null;
  return percent ? number / kLuckyPercentScale : number;
}
