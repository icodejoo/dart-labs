import '../core/foundation/shadow.dart';
import 'css_color.dart';
import 'json_reader.dart';

/// 上游阴影固定为偏移 x、偏移 y、blur 和颜色四段。
const int _shadowParts = 4;

/// 解析第一组 x y blur color 阴影，数字可带 px；无效输入返回 null 并警告。
///
/// 颜色内的逗号和空白不会拆段；blurSpace 固定为 device。
/// 例如 '1px 2px 4px rgba(0,0,0,.5)'。
LuckyShadow? parseCssShadow(Object? value, void Function(String message) warn) {
  if (value == null || value == '') return null;
  if (value is! String) {
    warn('阴影必须是字符串');
    return null;
  }
  final groups = splitCompatCommas(value);
  if (groups == null) {
    warn('阴影括号不匹配');
    return null;
  }
  final parts = RegExp(r'(?:rgba?|hsla?)\([^)]*\)|\S+')
      .allMatches(groups.first)
      .map((match) => match[0]!)
      .toList();
  if (parts.length != _shadowParts) {
    warn('阴影必须包含 x y blur color 四段');
    return null;
  }
  final numbers = parts
      .take(_shadowParts - 1)
      .map((token) => double.tryParse(token.replaceFirst(RegExp(r'px$'), '')))
      .toList();
  if (numbers.any((number) => number == null || !number.isFinite) ||
      numbers[2]! < 0) {
    warn('阴影偏移与模糊半径必须是有限数，模糊半径不能为负');
    return null;
  }
  final color = parseCssColor(parts.last, warn);
  if (color == null) return null;
  return LuckyShadow(
      offsetX: numbers[0]!,
      offsetY: numbers[1]!,
      blur: numbers[2]!,
      color: color,
      blurSpace: LuckyShadowBlurSpace.device);
}
