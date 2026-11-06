// Pure SVG path commands; deliberately independent of dart:ui.
// 纯 SVG 路径指令；不依赖 dart:ui。
import 'dart:typed_data';

/// Absolute line command. / 绝对直线命令。
const _lineCommand = 'L';

/// Absolute cubic command. / 绝对三次曲线命令。
const _cubicCommand = 'C';

/// Smooth cubic command. / 平滑三次曲线命令。
const _smoothCubicCommand = 'S';

/// Absolute quadratic command. / 绝对二次曲线命令。
const _quadCommand = 'Q';

/// Smooth quadratic command. / 平滑二次曲线命令。
const _smoothQuadCommand = 'T';

/// Absolute arc command. / 绝对圆弧命令。
const _arcCommand = 'A';

/// Close command. / 闭合命令。
const _closeCommand = 'Z';

/// Decimal separator. / 小数点。
const _decimalPoint = '.';

/// Positive numeric sign. / 数值正号。
const _positiveSign = '+';

/// Negative numeric sign. / 数值负号。
const _negativeSign = '-';

/// True compact arc flag. / 紧凑圆弧真标志。
const _oneFlag = '1';

/// Scale for reflected controls. / 控制点反射的倍数。
const _reflectionScale = 2;

/// Worst-case numeric expansion for H/V/T. / H/V/T 的最大数字参数扩展倍数。
const _maxCoordinateExpansion = 2;

/// Internal byte codes for absolute commands. / 绝对指令的内部字节编码。
abstract final class PathVerb {
  /// M: x y. / 移动至。
  static const int move = 0;

  /// L: x y. / 直线至。
  static const int line = 1;

  /// C: x1 y1 x2 y2 x y. / 三次贝塞尔至。
  static const int cubic = 2;

  /// Q: x1 y1 x y. / 二次贝塞尔至。
  static const int quad = 3;

  /// A: rx ry rotation largeArc sweep x y. / 端点参数化圆弧。
  static const int arc = 4;

  /// Z: no coordinates. / 闭合，无坐标。
  static const int close = 5;
}

/// Pure, read-only absolute commands, preserving double precision and signed zero.
/// H/V become L, S becomes C, T becomes Q; A stays an endpoint arc, never cubics.
/// Coordinates are concatenated in verb order using [PathVerb]'s layouts;
/// arc flags retain their numeric values (nonzero means true when drawing).
///
/// 只读的纯数据绝对指令，保留双精度和负零。H/V 展开为 L，S/T 展开为 C/Q；
/// A 保留端点圆弧，不转三次曲线。坐标按 [PathVerb] 布局依序拼接，圆弧标志
/// 保留原始数值，绘制时非零为真。不包含隐式原点或闭合后的额外 M。
final class PathData {
  /// Takes ownership of parser buffers. / 接管解析器缓冲区。
  PathData._(Uint8List verbs, Float64List coords)
    : verbs = verbs.asUnmodifiableView(),
      coords = coords.asUnmodifiableView();

  /// One [PathVerb] byte per completed command. / 每条完整指令一个编码字节。
  final Uint8List verbs;

  /// Flat verb arguments; M/L=2, C=6, Q=4, A=7, Z=0 doubles.
  /// 扁平参数表；M/L 为 2、C 为 6、Q 为 4、A 为 7、Z 为 0 个双精度数。
  final Float64List coords;
}

/// Parses without UI objects, retaining only complete commands before an error.
/// Empty input or a leading bare number yields no commands. A leading non-M
/// command is retained; Z resets the parser point to the last explicit M.
/// Token tolerance and floating-point operation order match the legacy parser.
///
/// 无 UI 对象的解析，仅保留出错前的完整指令。空输入或开头裸数字返回空指令；
/// 首条非 M 指令照常保留，Z 将解析器当前点重置至最近的显式 M。
/// 词法容错及浮点运算顺序与旧解析器相同。
PathData parseSvgPathCommands(String d) {
  final tokens = tokenizeSvgPathData(d);
  // At most one verb per token; H/V/T can double the numeric argument count.
  // 每个 token 至多对应一个 verb；H/V/T 展开至多使数字参数数目翻倍。
  final verbs = Uint8List(tokens.length);
  final coords = Float64List(tokens.length * _maxCoordinateExpansion);
  final (verbCount, coordCount) = _appendSvgPathCommands(tokens, verbs, coords);
  return PathData._(verbs.sublist(0, verbCount), coords.sublist(0, coordCount));
}

/// Normalizes tokens with legacy arithmetic and truncation. / 按旧运算与截断规则规范化。
(int, int) _appendSvgPathCommands(
  List<Object> tokens,
  Uint8List verbs,
  Float64List coords,
) {
  var verbCount = 0, coordCount = 0;
  var i = 0;

  double cx = 0, cy = 0; // current point / 当前点
  double startX = 0, startY = 0; // subpath start / 子路径起点
  double? lastCtrlX,
      lastCtrlY; // last cubic/quad control point, for S/T reflection
  String? lastCommand;

  /// Reads one number or aborts the current command. / 读取数值，否则中止当前命令。
  double num() {
    if (i >= tokens.length || tokens[i] is! double) {
      throw const _PathDataError();
    }
    return tokens[i++] as double;
  }

  /// Whether another numeric group follows. / 后面是否还有数值组。
  bool hasMore() => i < tokens.length && tokens[i] is double;

  String? command;
  try {
    while (i < tokens.length) {
      if (tokens[i] is String) {
        command = tokens[i++] as String;
      }
      if (command == null) break;
      final isRelative = command == command.toLowerCase();
      final cmd = command.toUpperCase();

      switch (cmd) {
        case 'M':
          {
            var x = num(), y = num();
            if (isRelative) {
              x += cx;
              y += cy;
            }
            verbs[verbCount++] = PathVerb.move;
            coords[coordCount++] = x;
            coords[coordCount++] = y;
            cx = startX = x;
            cy = startY = y;
            // Subsequent coordinate pairs without a new command letter are
            // implicit `L` commands (SVG grammar).
            command = isRelative ? 'l' : _lineCommand;
          }
        case _lineCommand:
          {
            var x = num(), y = num();
            if (isRelative) {
              x += cx;
              y += cy;
            }
            verbs[verbCount++] = PathVerb.line;
            coords[coordCount++] = x;
            coords[coordCount++] = y;
            cx = x;
            cy = y;
          }
        case 'H':
          {
            var x = num();
            if (isRelative) x += cx;
            verbs[verbCount++] = PathVerb.line;
            coords[coordCount++] = x;
            coords[coordCount++] = cy;
            cx = x;
          }
        case 'V':
          {
            var y = num();
            if (isRelative) y += cy;
            verbs[verbCount++] = PathVerb.line;
            coords[coordCount++] = cx;
            coords[coordCount++] = y;
            cy = y;
          }
        case _cubicCommand:
          {
            var x1 = num(),
                y1 = num(),
                x2 = num(),
                y2 = num(),
                x = num(),
                y = num();
            if (isRelative) {
              x1 += cx;
              y1 += cy;
              x2 += cx;
              y2 += cy;
              x += cx;
              y += cy;
            }
            verbs[verbCount++] = PathVerb.cubic;
            coords[coordCount++] = x1;
            coords[coordCount++] = y1;
            coords[coordCount++] = x2;
            coords[coordCount++] = y2;
            coords[coordCount++] = x;
            coords[coordCount++] = y;
            lastCtrlX = x2;
            lastCtrlY = y2;
            cx = x;
            cy = y;
          }
        case _smoothCubicCommand:
          {
            var x2 = num(), y2 = num(), x = num(), y = num();
            if (isRelative) {
              x2 += cx;
              y2 += cy;
              x += cx;
              y += cy;
            }
            final reflected =
                (lastCommand == _cubicCommand ||
                    lastCommand == _smoothCubicCommand)
                ? (
                    _reflectionScale * cx - lastCtrlX!,
                    _reflectionScale * cy - lastCtrlY!,
                  )
                : (cx, cy);
            verbs[verbCount++] = PathVerb.cubic;
            coords[coordCount++] = reflected.$1;
            coords[coordCount++] = reflected.$2;
            coords[coordCount++] = x2;
            coords[coordCount++] = y2;
            coords[coordCount++] = x;
            coords[coordCount++] = y;
            lastCtrlX = x2;
            lastCtrlY = y2;
            cx = x;
            cy = y;
          }
        case _quadCommand:
          {
            var x1 = num(), y1 = num(), x = num(), y = num();
            if (isRelative) {
              x1 += cx;
              y1 += cy;
              x += cx;
              y += cy;
            }
            verbs[verbCount++] = PathVerb.quad;
            coords[coordCount++] = x1;
            coords[coordCount++] = y1;
            coords[coordCount++] = x;
            coords[coordCount++] = y;
            lastCtrlX = x1;
            lastCtrlY = y1;
            cx = x;
            cy = y;
          }
        case _smoothQuadCommand:
          {
            var x = num(), y = num();
            if (isRelative) {
              x += cx;
              y += cy;
            }
            final reflected =
                (lastCommand == _quadCommand ||
                    lastCommand == _smoothQuadCommand)
                ? (
                    _reflectionScale * cx - lastCtrlX!,
                    _reflectionScale * cy - lastCtrlY!,
                  )
                : (cx, cy);
            verbs[verbCount++] = PathVerb.quad;
            coords[coordCount++] = reflected.$1;
            coords[coordCount++] = reflected.$2;
            coords[coordCount++] = x;
            coords[coordCount++] = y;
            lastCtrlX = reflected.$1;
            lastCtrlY = reflected.$2;
            cx = x;
            cy = y;
          }
        case _arcCommand:
          {
            final rx = num(), ry = num(), rot = num();
            final largeArc = num();
            final sweep = num();
            var x = num(), y = num();
            if (isRelative) {
              x += cx;
              y += cy;
            }
            verbs[verbCount++] = PathVerb.arc;
            coords[coordCount++] = rx;
            coords[coordCount++] = ry;
            coords[coordCount++] = rot;
            coords[coordCount++] = largeArc;
            coords[coordCount++] = sweep;
            coords[coordCount++] = x;
            coords[coordCount++] = y;
            cx = x;
            cy = y;
          }
        case _closeCommand:
          {
            verbs[verbCount++] = PathVerb.close;
            cx = startX;
            cy = startY;
          }
        default:
          // Unsupported command letter: stop parsing rather than looping
          // forever, but keep whatever was already built.
          return (verbCount, coordCount);
      }
      lastCommand = cmd;
      // Repeated coordinate groups without a new letter reuse the same command
      // (except M/Z, handled above / after close).
      if (cmd != _closeCommand && hasMore()) {
        // command stays the same; loop continues without consuming a letter.
      } else if (cmd == _closeCommand) {
        command = null;
      } else {
        command = null;
      }
    }
  } on _PathDataError {
    // Keep only completed commands. / 仅保留完整指令。
  }
  return (verbCount, coordCount);
}

/// Signals missing or nonnumeric arguments. / 标记缺失或非数字参数。
class _PathDataError implements Exception {
  /// Creates the internal signal. / 创建内部信号。
  const _PathDataError();
}

/// Splits path data into an alternating stream of command-letter [String]s
/// and numeric [double]s.
///
/// 把路径数据拆分为命令字母 [String] 与数值 [double] 交替出现的流；
/// 路径变形的规范化也复用它。
///
/// 圆弧 `A`/`a` 每 7 个参数一组，其中第 4、5 个是 large-arc / sweep 标志位：
/// 规范要求它们只能是单个 `0` 或 `1`，且可以不加分隔符紧贴下一个数
/// （压缩器常见写法，如 `A10 10 0 0110 10` 即标志位 0、1，终点 x 为 10）。
/// 畸形记号（孤立的符号、残缺的指数等）被丢弃，不抛异常。
List<Object> tokenizeSvgPathData(String d) {
  final tokens = <Object>[];
  final length = d.length;
  var i = 0;
  // 当前命令字母，以及它已读入的参数个数（圆弧按 7 个一组取模判断标志位）。
  var command = '';
  var argIndex = 0;

  /// Recognizes supported command letters. / 识别支持的命令字母。
  bool isCommandLetter(String c) => 'MmLlHhVvCcSsQqTtAaZz'.contains(c);

  while (i < length) {
    final c = d[i];
    if (c.trim().isEmpty || c == ',') {
      i++;
      continue;
    }
    if (isCommandLetter(c)) {
      tokens.add(c);
      command = c;
      argIndex = 0;
      i++;
      continue;
    }
    if ((command == _arcCommand || command == 'a') &&
        (c == '0' || c == _oneFlag)) {
      final slot = argIndex % _arcArgCount;
      if (slot == _arcLargeFlagSlot || slot == _arcSweepFlagSlot) {
        tokens.add(c == _oneFlag ? 1.0 : 0.0);
        argIndex++;
        i++;
        continue;
      }
    }
    // 数值：可选符号、整数部分、至多一个小数点、可选指数。"1.5.5" 这类紧贴
    // 的两个数由"至多一个小数点"自然切开（得到 1.5 与 .5）。
    final start = i;
    if (c == _positiveSign || c == _negativeSign) i++;
    var sawDot = false;
    while (i < length &&
        (_isDigit(d[i]) || (d[i] == _decimalPoint && !sawDot))) {
      if (d[i] == _decimalPoint) sawDot = true;
      i++;
    }
    if (i < length && (d[i] == 'e' || d[i] == 'E')) {
      i++;
      if (i < length && (d[i] == _positiveSign || d[i] == _negativeSign)) i++;
      while (i < length && _isDigit(d[i])) {
        i++;
      }
    }
    if (i == start) {
      // 无法识别的字符：跳过它，避免死循环。
      i++;
      continue;
    }
    // 孤立的符号、残缺的指数（如 `-`、`1e`）解析不出数值：丢弃该记号，不抛异常。
    final value = double.tryParse(d.substring(start, i));
    if (value == null) continue;
    tokens.add(value);
    argIndex++;
  }
  return tokens;
}

/// Arc argument count. / 圆弧 `A`/`a` 一组参数的个数：rx ry 旋转角 large sweep x y。
const int _arcArgCount = 7;

/// Large-arc flag index. / large-arc 标志位在一组圆弧参数中的下标。
const int _arcLargeFlagSlot = 3;

/// Sweep flag index. / sweep 标志位在一组圆弧参数中的下标。
const int _arcSweepFlagSlot = 4;

/// Tests an ASCII digit. / 判断 ASCII 数字。
bool _isDigit(String c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;
