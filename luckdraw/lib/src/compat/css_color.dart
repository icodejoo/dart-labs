import 'package:flutter/painting.dart';

import '../core/foundation/constants.dart';

/// CSS 短十六进制颜色的位数。
const int _shortRgbDigits = 3;

/// CSS 短 RGBA 或完整通道数量。
const int _rgbaChannels = 4;

/// CSS 完整 RGB 的十六进制位数。
const int _rgbDigits = 6;

/// CSS 完整 RGBA 的十六进制位数。
const int _rgbaDigits = 8;

/// 十六进制解析进制。
const int _hexRadix = 16;

/// CSS 表示无背景的透明关键字，颜色解析时仍返回透明黑。
const String kCompatTransparentKeyword = 'transparent';

/// aqua 与 cyan 共享的颜色值。
const int _aquaArgb = 0xFF00FFFF;

/// fuchsia 与 magenta 共享的颜色值。
const int _fuchsiaArgb = 0xFFFF00FF;

/// gray 与 grey 共享的颜色值。
const int _grayArgb = 0xFF808080;

/// darkgray 与 darkgrey 共享的颜色值。
const int _darkGrayArgb = 0xFFA9A9A9;

/// darkslategray 与 darkslategrey 共享的颜色值。
const int _darkSlateGrayArgb = 0xFF2F4F4F;

/// dimgray 与 dimgrey 共享的颜色值。
const int _dimGrayArgb = 0xFF696969;

/// lightgray 与 lightgrey 共享的颜色值。
const int _lightGrayArgb = 0xFFD3D3D3;

/// lightslategray 与 lightslategrey 共享的颜色值。
const int _lightSlateGrayArgb = 0xFF778899;

/// slategray 与 slategrey 共享的颜色值。
const int _slateGrayArgb = 0xFF708090;

/// CSS 命名色表（148 项）；transparent 另行处理，表只由 compat 引用。
const Map<String, int> kCompatCssNamedColors = {
  'aliceblue': 0xFFF0F8FF,
  'antiquewhite': 0xFFFAEBD7,
  'aqua': _aquaArgb,
  'aquamarine': 0xFF7FFFD4,
  'azure': 0xFFF0FFFF,
  'beige': 0xFFF5F5DC,
  'bisque': 0xFFFFE4C4,
  'black': 0xFF000000,
  'blanchedalmond': 0xFFFFEBCD,
  'blue': 0xFF0000FF,
  'blueviolet': 0xFF8A2BE2,
  'brown': 0xFFA52A2A,
  'burlywood': 0xFFDEB887,
  'cadetblue': 0xFF5F9EA0,
  'chartreuse': 0xFF7FFF00,
  'chocolate': 0xFFD2691E,
  'coral': 0xFFFF7F50,
  'cornflowerblue': 0xFF6495ED,
  'cornsilk': 0xFFFFF8DC,
  'crimson': 0xFFDC143C,
  'cyan': _aquaArgb,
  'darkblue': 0xFF00008B,
  'darkcyan': 0xFF008B8B,
  'darkgoldenrod': 0xFFB8860B,
  'darkgray': _darkGrayArgb,
  'darkgreen': 0xFF006400,
  'darkgrey': _darkGrayArgb,
  'darkkhaki': 0xFFBDB76B,
  'darkmagenta': 0xFF8B008B,
  'darkolivegreen': 0xFF556B2F,
  'darkorange': 0xFFFF8C00,
  'darkorchid': 0xFF9932CC,
  'darkred': 0xFF8B0000,
  'darksalmon': 0xFFE9967A,
  'darkseagreen': 0xFF8FBC8F,
  'darkslateblue': 0xFF483D8B,
  'darkslategray': _darkSlateGrayArgb,
  'darkslategrey': _darkSlateGrayArgb,
  'darkturquoise': 0xFF00CED1,
  'darkviolet': 0xFF9400D3,
  'deeppink': 0xFFFF1493,
  'deepskyblue': 0xFF00BFFF,
  'dimgray': _dimGrayArgb,
  'dimgrey': _dimGrayArgb,
  'dodgerblue': 0xFF1E90FF,
  'firebrick': 0xFFB22222,
  'floralwhite': 0xFFFFFAF0,
  'forestgreen': 0xFF228B22,
  'fuchsia': _fuchsiaArgb,
  'gainsboro': 0xFFDCDCDC,
  'ghostwhite': 0xFFF8F8FF,
  'gold': 0xFFFFD700,
  'goldenrod': 0xFFDAA520,
  'gray': _grayArgb,
  'green': 0xFF008000,
  'greenyellow': 0xFFADFF2F,
  'grey': _grayArgb,
  'honeydew': 0xFFF0FFF0,
  'hotpink': 0xFFFF69B4,
  'indianred': 0xFFCD5C5C,
  'indigo': 0xFF4B0082,
  'ivory': 0xFFFFFFF0,
  'khaki': 0xFFF0E68C,
  'lavender': 0xFFE6E6FA,
  'lavenderblush': 0xFFFFF0F5,
  'lawngreen': 0xFF7CFC00,
  'lemonchiffon': 0xFFFFFACD,
  'lightblue': 0xFFADD8E6,
  'lightcoral': 0xFFF08080,
  'lightcyan': 0xFFE0FFFF,
  'lightgoldenrodyellow': 0xFFFAFAD2,
  'lightgray': _lightGrayArgb,
  'lightgreen': 0xFF90EE90,
  'lightgrey': _lightGrayArgb,
  'lightpink': 0xFFFFB6C1,
  'lightsalmon': 0xFFFFA07A,
  'lightseagreen': 0xFF20B2AA,
  'lightskyblue': 0xFF87CEFA,
  'lightslategray': _lightSlateGrayArgb,
  'lightslategrey': _lightSlateGrayArgb,
  'lightsteelblue': 0xFFB0C4DE,
  'lightyellow': 0xFFFFFFE0,
  'lime': 0xFF00FF00,
  'limegreen': 0xFF32CD32,
  'linen': 0xFFFAF0E6,
  'magenta': _fuchsiaArgb,
  'maroon': 0xFF800000,
  'mediumaquamarine': 0xFF66CDAA,
  'mediumblue': 0xFF0000CD,
  'mediumorchid': 0xFFBA55D3,
  'mediumpurple': 0xFF9370DB,
  'mediumseagreen': 0xFF3CB371,
  'mediumslateblue': 0xFF7B68EE,
  'mediumspringgreen': 0xFF00FA9A,
  'mediumturquoise': 0xFF48D1CC,
  'mediumvioletred': 0xFFC71585,
  'midnightblue': 0xFF191970,
  'mintcream': 0xFFF5FFFA,
  'mistyrose': 0xFFFFE4E1,
  'moccasin': 0xFFFFE4B5,
  'navajowhite': 0xFFFFDEAD,
  'navy': 0xFF000080,
  'oldlace': 0xFFFDF5E6,
  'olive': 0xFF808000,
  'olivedrab': 0xFF6B8E23,
  'orange': 0xFFFFA500,
  'orangered': 0xFFFF4500,
  'orchid': 0xFFDA70D6,
  'palegoldenrod': 0xFFEEE8AA,
  'palegreen': 0xFF98FB98,
  'paleturquoise': 0xFFAFEEEE,
  'palevioletred': 0xFFDB7093,
  'papayawhip': 0xFFFFEFD5,
  'peachpuff': 0xFFFFDAB9,
  'peru': 0xFFCD853F,
  'pink': 0xFFFFC0CB,
  'plum': 0xFFDDA0DD,
  'powderblue': 0xFFB0E0E6,
  'purple': 0xFF800080,
  'rebeccapurple': 0xFF663399,
  'red': 0xFFFF0000,
  'rosybrown': 0xFFBC8F8F,
  'royalblue': 0xFF4169E1,
  'saddlebrown': 0xFF8B4513,
  'salmon': 0xFFFA8072,
  'sandybrown': 0xFFF4A460,
  'seagreen': 0xFF2E8B57,
  'seashell': 0xFFFFF5EE,
  'sienna': 0xFFA0522D,
  'silver': 0xFFC0C0C0,
  'skyblue': 0xFF87CEEB,
  'slateblue': 0xFF6A5ACD,
  'slategray': _slateGrayArgb,
  'slategrey': _slateGrayArgb,
  'snow': 0xFFFFFAFA,
  'springgreen': 0xFF00FF7F,
  'steelblue': 0xFF4682B4,
  'tan': 0xFFD2B48C,
  'teal': 0xFF008080,
  'thistle': 0xFFD8BFD8,
  'tomato': 0xFFFF6347,
  'turquoise': 0xFF40E0D0,
  'violet': 0xFFEE82EE,
  'wheat': 0xFFF5DEB3,
  'white': 0xFFFFFFFF,
  'whitesmoke': 0xFFF5F5F5,
  'yellow': 0xFFFFFF00,
  'yellowgreen': 0xFF9ACD32,
};

/// 解析 CSS 颜色；非法值返回 null 并调用 [warn]。
///
/// 支持十六进制、逗号式 rgb/rgba/hsl/hsla 与命名色；例如 '#f00' 返回红色。
/// transparent 返回透明黑；背景是否存在由 parseCssFill 决定。
Color? parseCssColor(String value, void Function(String message) warn) {
  final text = value.trim().toLowerCase();
  if (text == kCompatTransparentKeyword) return const Color(0x00000000);
  final named = kCompatCssNamedColors[text];
  if (named != null) return Color(named);
  if (RegExp(r'^#[0-9a-f]+$').hasMatch(text)) {
    var hex = text.substring(1);
    if (hex.length == _shortRgbDigits || hex.length == _rgbaChannels) {
      hex = hex.split('').map((digit) => '$digit$digit').join();
    }
    if (hex.length == _rgbDigits) {
      return Color(int.parse('ff$hex', radix: _hexRadix));
    }
    if (hex.length == _rgbaDigits) {
      return Color(int.parse(
          hex.substring(_rgbDigits) + hex.substring(0, _rgbDigits),
          radix: _hexRadix));
    }
  }
  final match = RegExp(r'^(rgb|rgba|hsl|hsla)\((.*)\)$').firstMatch(text);
  if (match != null) {
    final name = match[1]!;
    final parts = match[2]!.split(',').map((token) => token.trim()).toList();
    final count = name.endsWith('a') ? _rgbaChannels : _shortRgbDigits;
    if (parts.length == count) {
      final alpha = count == _rgbaChannels ? _component(parts.last, 1) : 1.0;
      if (alpha != null) {
        if (name.startsWith('rgb')) {
          final rgb = parts
              .take(_shortRgbDigits)
              .map((token) => _component(token, kLuckyMaxAlpha8.toDouble()))
              .toList();
          if (rgb.every((channel) => channel != null)) {
            return Color.fromARGB((alpha * kLuckyMaxAlpha8).round(),
                rgb[0]!.round(), rgb[1]!.round(), rgb[2]!.round());
          }
        } else {
          final hue =
              double.tryParse(parts[0].replaceFirst(RegExp(r'deg$'), ''));
          final saturation = _percentage(parts[1]);
          final lightness = _percentage(parts[2]);
          if (hue != null &&
              hue.isFinite &&
              saturation != null &&
              lightness != null) {
            return HSLColor.fromAHSL(
                    alpha, hue % kLuckyFullTurnDeg, saturation, lightness)
                .toColor();
          }
        }
      }
    }
  }
  warn('无法解析颜色：$value');
  return null;
}

/// 读取百分比通道；没有百分号时返回 null。
double? _percentage(String value) =>
    value.endsWith('%') ? _component(value, 1) : null;

/// 解析并钳制数值通道到零与 [maximum] 之间。
double? _component(String value, double maximum) {
  final percent = value.endsWith('%');
  final number =
      double.tryParse(percent ? value.substring(0, value.length - 1) : value);
  if (number == null || !number.isFinite) return null;
  return (percent ? number / kLuckyPercentScale * maximum : number)
      .clamp(0.0, maximum);
}
