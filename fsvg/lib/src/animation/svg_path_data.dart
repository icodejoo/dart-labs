// A compact SVG path-data ("d" attribute) parser producing a dart:ui Path,
// plus a stroke-dash helper used to render `stroke-dasharray`/
// `stroke-dashoffset` (Canvas has no native dashed stroke). Both are
// original implementations of well-known, publicly documented algorithms
// (the SVG path grammar; the "walk path metrics, alternate on/off segments"
// dashing technique) — not copied from any vendored source.
//
// 紧凑的 SVG 路径数据（"d" 属性）解析器，产出 dart:ui Path；另附一个
// stroke-dash 辅助函数，用于渲染 `stroke-dasharray`/`stroke-dashoffset`
// （Canvas 原生不支持虚线描边）。两者都是对公开、广为人知算法的原创实现
// （SVG 路径语法；"遍历路径长度、交替绘制开/关段"的虚线技术），并非抄自任何
// vendor 源码。

import 'dart:ui' as ui;

/// Parses an SVG `d` attribute into a [ui.Path].
///
/// Supports the common absolute/relative commands: `M`/`m`, `L`/`l`,
/// `H`/`h`, `V`/`v`, `C`/`c`, `S`/`s`, `Q`/`q`, `T`/`t`, `A`/`a`, `Z`/`z`.
///
/// **Not supported**: malformed/partial arcs beyond the standard endpoint
/// parameterization are approximated via Flutter's [ui.Path.arcToPoint];
/// there is no attempt to match a reference SVG rasterizer bit-for-bit.
///
/// 把 SVG `d` 属性解析为 [ui.Path]。
///
/// 支持常见的绝对/相对命令：`M`/`m`、`L`/`l`、`H`/`h`、`V`/`v`、`C`/`c`、
/// `S`/`s`、`Q`/`q`、`T`/`t`、`A`/`a`、`Z`/`z`。
///
/// **不支持**：超出标准端点参数化范围的畸形/残缺圆弧，一律用 Flutter 的
/// [ui.Path.arcToPoint] 近似处理；不追求与参考 SVG 光栅器逐像素一致。
ui.Path parseSvgPathData(String d) {
  final tokens = _tokenize(d);
  final path = ui.Path();
  var i = 0;

  double cx = 0, cy = 0; // current point / 当前点
  double startX = 0, startY = 0; // subpath start / 子路径起点
  double? lastCtrlX, lastCtrlY; // last cubic/quad control point, for S/T reflection
  String? lastCommand;

  double num() => tokens[i++] as double;
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
          var x1 = num(), y1 = num(), x2 = num(), y2 = num(), x = num(), y = num();
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
        return path;
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
  return path;
}

/// Splits path data into an alternating stream of command-letter [String]s
/// and numeric [double]s.
///
/// 把路径数据拆分为命令字母 [String] 与数值 [double] 交替出现的流。
List<Object> _tokenize(String d) {
  final tokens = <Object>[];
  final length = d.length;
  var i = 0;
  bool isCommandLetter(String c) => 'MmLlHhVvCcSsQqTtAaZz'.contains(c);

  while (i < length) {
    final c = d[i];
    if (c.trim().isEmpty || c == ',') {
      i++;
      continue;
    }
    if (isCommandLetter(c)) {
      tokens.add(c);
      i++;
      continue;
    }
    // Parse a number: optional sign, digits, optional decimal, optional
    // exponent. SVG also allows numbers glued together like "1.5.5" (two
    // numbers ".5" ".5") but that's rare in generated icon data; not handled.
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
      // Unrecognized character; skip it to avoid an infinite loop.
      i++;
      continue;
    }
    tokens.add(double.parse(d.substring(start, i)));
  }
  return tokens;
}

bool _isDigit(String c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;

/// Parses a `points="x1,y1 x2,y2 ..."` attribute (shared by `<polyline>` and
/// `<polygon>`) into a flat coordinate list. Malformed/odd-length input
/// simply drops the trailing unpaired number rather than throwing — matching
/// this engine's general "skip rather than crash" tolerance for bad markup.
///
/// 解析 `<polyline>`/`<polygon>` 共用的 `points="x1,y1 x2,y2 ..."` 属性为
/// 扁平坐标列表。畸形/奇数长度的输入会直接丢弃末尾未配对的数字而非抛出异常，
/// 与本引擎"跳过而非崩溃"的一贯容错风格一致。
List<ui.Offset> parseSvgPoints(String raw) {
  final numbers = raw
      .trim()
      .split(RegExp(r'[\s,]+'))
      .where((s) => s.isNotEmpty)
      .map(double.tryParse)
      .where((v) => v != null)
      .cast<double>()
      .toList();
  final points = <ui.Offset>[];
  for (var i = 0; i + 1 < numbers.length; i += 2) {
    points.add(ui.Offset(numbers[i], numbers[i + 1]));
  }
  return points;
}

/// Builds a dashed version of [source] per SVG's `stroke-dasharray`/
/// `stroke-dashoffset` semantics: walks each contour's arc length and
/// alternates emitting "on"/"off" segments of the (possibly offset) dash
/// pattern.
///
/// [dashArray] must be non-empty; an odd-length array is treated like SVG
/// does — the pattern is conceptually doubled (`[a, b, c]` behaves like
/// `[a, b, c, a, b, c]`).
///
/// 按 SVG `stroke-dasharray`/`stroke-dashoffset` 语义，为 [source] 生成虚线
/// 路径：遍历每个轮廓的弧长，交替输出（可能带偏移的）虚线图案中"开/关"两段。
///
/// [dashArray] 不能为空；奇数长度按 SVG 规则处理——图案在概念上翻倍
/// （`[a, b, c]` 等价于 `[a, b, c, a, b, c]`）。
ui.Path dashPath(ui.Path source, {required List<double> dashArray, double dashOffset = 0}) {
  final pattern = dashArray.length.isOdd ? [...dashArray, ...dashArray] : dashArray;
  final cycle = pattern.fold<double>(0, (sum, v) => sum + v);
  if (cycle <= 0) return source;

  final result = ui.Path();
  for (final metric in source.computeMetrics()) {
    // Normalize the offset into [0, cycle) then walk backwards from zero so
    // a positive dashOffset pushes the pattern's start forward past the
    // path start, matching SVG's "dashoffset hides more of the start" look.
    var distance = -(dashOffset % cycle);
    var patternIndex = 0;
    var drawing = true;
    // If the normalized offset landed us mid-segment, walk the pattern
    // forward until `distance` catches up to a segment boundary at/after it,
    // keeping the on/off phase consistent.
    while (distance + pattern[patternIndex % pattern.length] <= 0) {
      distance += pattern[patternIndex % pattern.length];
      patternIndex++;
      drawing = !drawing;
    }
    while (distance < metric.length) {
      final segmentLength = pattern[patternIndex % pattern.length];
      final segmentEnd = distance + segmentLength;
      if (drawing && segmentEnd > 0) {
        final clampedStart = distance < 0 ? 0.0 : distance;
        final clampedEnd = segmentEnd > metric.length ? metric.length : segmentEnd;
        if (clampedEnd > clampedStart) {
          result.addPath(metric.extractPath(clampedStart, clampedEnd), ui.Offset.zero);
        }
      }
      distance = segmentEnd;
      patternIndex++;
      drawing = !drawing;
    }
  }
  return result;
}
