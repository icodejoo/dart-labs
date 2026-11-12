import '../core/foundation/constants.dart';
import '../core/foundation/length.dart';
import 'compat_options.dart';

/// 解析上游长度为 px 或 percent；失败返回 null 并调用 [warn]。
///
/// [options] 提供 rem、vw 和自定义单位基准。例如 '50%' 返回 LuckyPercent(50)。
LuckyLength? parseCssLength(Object? value, LuckyCanvasCompatOptions options,
    void Function(String message) warn) {
  double? number;
  var unit = '';
  if (value is num) {
    number = value.toDouble();
  } else if (value is String) {
    // 上游 lucky.ts:324-338；不 trim，保留内部与外部空格的无效输入语义。
    final match = RegExp(r'^([-]*[0-9.]*)([a-z%]*)$').firstMatch(value);
    if (match != null) {
      final digits = match[1]!;
      number = digits.isEmpty ? 0 : double.tryParse(digits);
      unit = match[2]!;
    }
  }
  if (number == null || !number.isFinite) {
    warn('无法解析长度：$value');
    return null;
  }
  if (unit == '%') return LuckyLength.percent(number);
  final double pixels;
  switch (unit) {
    case '':
    case 'px':
      pixels = number;
    case 'rem':
      pixels = number * options.remBase;
    case 'vw':
      final width = options.viewportWidth;
      if (width == null) {
        warn('vw 缺少 viewportWidth，保留原始数字');
        pixels = number;
      } else {
        pixels = number / kLuckyPercentScale * width;
      }
    default:
      pixels = options.handleCssUnit?.call(number, unit) ?? number;
  }
  if (!pixels.isFinite) {
    warn('长度换算结果不是有限数：$value');
    return null;
  }
  return LuckyLength.px(pixels);
}

/// 将无基准长度折算为逻辑像素；例如 50% 返回 0.5，上游分母默认 1。
double resolveBaseless(LuckyLength length) => length is LuckyPercent
    ? length.value / kLuckyPercentScale
    : (length as LuckyPx).value;
