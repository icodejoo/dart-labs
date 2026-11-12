// Frozen from 26ea43d7; keep independent of production parsing.
// 冻结自 26ea43d7；不依赖生产解析器，用作逐位对照。
import 'dart:ui' as ui;

/// Builds the pre-refactor path. / 构建重构前的路径。
ui.Path legacyParseSvgPathData(String d) {
  final path = ui.Path();
  try {
    _appendSvgPathData(_legacyTokenizeSvgPathData(d), path);
  } on _PathDataError {
    // 残缺或畸形的路径数据：保留出错之前已构建的部分（SVG 规范的错误处理）。
  }
  return path;
}

/// Appends legacy tokens, stopping at incomplete arguments.
/// 把已词法化的 [tokens] 逐段追加到 [path]；参数缺失或类型不符（该是数字的位置
/// 出现命令字母）时抛出 [_PathDataError]，由 [legacyParseSvgPathData] 接住，
/// 而不是让整帧绘制崩溃。
void _appendSvgPathData(List<Object> tokens, ui.Path path) {
  var i = 0;

  double cx = 0, cy = 0; // current point / 当前点
  double startX = 0, startY = 0; // subpath start / 子路径起点
  double? lastCtrlX,
      lastCtrlY; // last cubic/quad control point, for S/T reflection
  String? lastCommand;

  /// Reads one legacy number. / 读取一个旧解析器数值。
  double num() {
    if (i >= tokens.length || tokens[i] is! double) {
      throw const _PathDataError();
    }
    return tokens[i++] as double;
  }

  /// Detects a repeated numeric group. / 判断隐式重复数值组。
  bool hasMore() => i < tokens.length && tokens[i] is double;

  String? command;
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
          path.moveTo(x, y);
          cx = startX = x;
          cy = startY = y;
          // Subsequent coordinate pairs without a new command letter are
          // implicit `L` commands (SVG grammar).
          command = isRelative ? 'l' : 'L';
        }
      case 'L':
        {
          var x = num(), y = num();
          if (isRelative) {
            x += cx;
            y += cy;
          }
          path.lineTo(x, y);
          cx = x;
          cy = y;
        }
      case 'H':
        {
          var x = num();
          if (isRelative) x += cx;
          path.lineTo(x, cy);
          cx = x;
        }
      case 'V':
        {
          var y = num();
          if (isRelative) y += cy;
          path.lineTo(cx, y);
          cy = y;
        }
      case 'C':
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
          path.cubicTo(x1, y1, x2, y2, x, y);
          lastCtrlX = x2;
          lastCtrlY = y2;
          cx = x;
          cy = y;
        }
      case 'S':
        {
          var x2 = num(), y2 = num(), x = num(), y = num();
          if (isRelative) {
            x2 += cx;
            y2 += cy;
            x += cx;
            y += cy;
          }
          final reflected = (lastCommand == 'C' || lastCommand == 'S')
              ? (2 * cx - lastCtrlX!, 2 * cy - lastCtrlY!)
              : (cx, cy);
          path.cubicTo(reflected.$1, reflected.$2, x2, y2, x, y);
          lastCtrlX = x2;
          lastCtrlY = y2;
          cx = x;
          cy = y;
        }
      case 'Q':
        {
          var x1 = num(), y1 = num(), x = num(), y = num();
          if (isRelative) {
            x1 += cx;
            y1 += cy;
            x += cx;
            y += cy;
          }
          path.quadraticBezierTo(x1, y1, x, y);
          lastCtrlX = x1;
          lastCtrlY = y1;
          cx = x;
          cy = y;
        }
      case 'T':
        {
          var x = num(), y = num();
          if (isRelative) {
            x += cx;
            y += cy;
          }
          final reflected = (lastCommand == 'Q' || lastCommand == 'T')
              ? (2 * cx - lastCtrlX!, 2 * cy - lastCtrlY!)
              : (cx, cy);
          path.quadraticBezierTo(reflected.$1, reflected.$2, x, y);
          lastCtrlX = reflected.$1;
          lastCtrlY = reflected.$2;
          cx = x;
          cy = y;
        }
      case 'A':
        {
          final rx = num(), ry = num(), rot = num();
          final largeArc = num() != 0;
          final sweep = num() != 0;
          var x = num(), y = num();
          if (isRelative) {
            x += cx;
            y += cy;
          }
          path.arcToPoint(
            ui.Offset(x, y),
            radius: ui.Radius.elliptical(rx, ry),
            rotation: rot,
            largeArc: largeArc,
            clockwise: sweep,
          );
          cx = x;
          cy = y;
        }
      case 'Z':
        {
          path.close();
          cx = startX;
          cy = startY;
        }
      default:
        // Unsupported command letter: stop parsing rather than looping
        // forever, but keep whatever was already built.
        return;
    }
    lastCommand = cmd;
    // Repeated coordinate groups without a new letter reuse the same command
    // (except M/Z, handled above / after close).
    if (cmd != 'Z' && hasMore()) {
      // command stays the same; loop continues without consuming a letter.
    } else if (cmd == 'Z') {
      command = null;
    } else {
      command = null;
    }
  }
}

/// Internal legacy truncation signal. / 路径数据参数缺失或类型不符时的内部信号，只在本文件内抛出与接住。
class _PathDataError implements Exception {
  /// Creates the signal. / 创建信号。
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
List<Object> _legacyTokenizeSvgPathData(String d) {
  final tokens = <Object>[];
  final length = d.length;
  var i = 0;
  // 当前命令字母，以及它已读入的参数个数（圆弧按 7 个一组取模判断标志位）。
  var command = '';
  var argIndex = 0;

  /// Recognizes command letters. / 识别命令字母。
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
    if ((command == 'A' || command == 'a') && (c == '0' || c == '1')) {
      final slot = argIndex % _arcArgCount;
      if (slot == _arcLargeFlagSlot || slot == _arcSweepFlagSlot) {
        tokens.add(c == '1' ? 1.0 : 0.0);
        argIndex++;
        i++;
        continue;
      }
    }
    // 数值：可选符号、整数部分、至多一个小数点、可选指数。"1.5.5" 这类紧贴
    // 的两个数由"至多一个小数点"自然切开（得到 1.5 与 .5）。
    final start = i;
    if (c == '+' || c == '-') i++;
    var sawDot = false;
    while (i < length && (_isDigit(d[i]) || (d[i] == '.' && !sawDot))) {
      if (d[i] == '.') sawDot = true;
      i++;
    }
    if (i < length && (d[i] == 'e' || d[i] == 'E')) {
      i++;
      if (i < length && (d[i] == '+' || d[i] == '-')) i++;
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
