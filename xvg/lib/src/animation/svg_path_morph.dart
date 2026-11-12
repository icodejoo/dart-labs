// 路径变形（`<animate attributeName="d">`）：把各关键帧的 `d` 规范化为绝对
// 坐标的数值结构，判断是否形状兼容，并按插值位置直接产出 ui.Path。
// 原创实现；思路参考 F 的 path_interpolation_morpher.dart，未搬运代码。

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'smil_animation.dart';
import 'svg_path_data.dart';

/// 规范化后的单条路径：指令码序列与扁平参数表。
class _NormalizedPath {
  _NormalizedPath(this.ops, this.coords);

  /// 指令码序列（`kMorph*`）。
  final List<int> ops;

  /// 按 [ops] 顺序排布的参数。
  final List<double> coords;
}

/// 圆弧 `A` 的 large 标志位在其 7 个参数中的下标。
const int _arcLargeFlag = 3;

/// 圆弧 `A` 的 sweep 标志位在其 7 个参数中的下标。
const int _arcSweepFlag = 4;

/// 把一条 `d` 规范化为绝对 M/L/C/Q/A/Z；`H`/`V` 转 `L`，`S` 转 `C`，`T` 转 `Q`，
/// 相对坐标转绝对。语法残缺（参数不足、未知命令、不以命令开头）时返回 null。
_NormalizedPath? _normalizePath(String d) {
  final tokens = tokenizeSvgPathData(d);
  final ops = <int>[];
  final coords = <double>[];
  var i = 0;
  // 当前点、子路径起点、上一条曲线的控制点，以及本条命令的相对偏移。
  var cx = 0.0, cy = 0.0, startX = 0.0, startY = 0.0;
  var ctrlX = 0.0, ctrlY = 0.0;
  var ox = 0.0, oy = 0.0;
  var prev = '';
  String? command;

  /// 接下来是否有 [n] 个连续数值。
  bool hasNumbers(int n) {
    if (i + n > tokens.length) return false;
    for (var k = 0; k < n; k++) {
      if (tokens[i + k] is! double) return false;
    }
    return true;
  }

  double next() => tokens[i++] as double;
  double px() => next() + ox;
  double py() => next() + oy;
  void emit(int op, List<double> args) {
    ops.add(op);
    coords.addAll(args);
  }

  while (i < tokens.length) {
    final token = tokens[i];
    if (token is String) {
      command = token;
      i++;
    } else if (command == null) {
      return null;
    }
    final rel = command == command.toLowerCase();
    final cmd = command.toUpperCase();
    ox = rel ? cx : 0.0;
    oy = rel ? cy : 0.0;
    // 本条命令的终点；默认原地不动，`H`/`V` 只改一个轴。
    var x = cx, y = cy;

    switch (cmd) {
      case 'M':
        if (!hasNumbers(2)) return null;
        x = px();
        y = py();
        emit(kMorphMove, [x, y]);
        startX = x;
        startY = y;
        command = rel ? 'l' : 'L'; // 后续坐标对是隐式 L
      case 'L':
        if (!hasNumbers(2)) return null;
        x = px();
        y = py();
        emit(kMorphLine, [x, y]);
      case 'H':
        if (!hasNumbers(1)) return null;
        x = px();
        emit(kMorphLine, [x, cy]);
      case 'V':
        if (!hasNumbers(1)) return null;
        y = py();
        emit(kMorphLine, [cx, y]);
      case 'C':
        if (!hasNumbers(6)) return null;
        final x1 = px(), y1 = py(), x2 = px(), y2 = py();
        x = px();
        y = py();
        emit(kMorphCubic, [x1, y1, x2, y2, x, y]);
        ctrlX = x2;
        ctrlY = y2;
      case 'S':
        if (!hasNumbers(4)) return null;
        final x2 = px(), y2 = py();
        x = px();
        y = py();
        final reflect = prev == 'C' || prev == 'S';
        emit(kMorphCubic, [
          reflect ? 2 * cx - ctrlX : cx,
          reflect ? 2 * cy - ctrlY : cy,
          x2,
          y2,
          x,
          y,
        ]);
        ctrlX = x2;
        ctrlY = y2;
      case 'Q':
        if (!hasNumbers(4)) return null;
        final x1 = px(), y1 = py();
        x = px();
        y = py();
        emit(kMorphQuad, [x1, y1, x, y]);
        ctrlX = x1;
        ctrlY = y1;
      case 'T':
        if (!hasNumbers(2)) return null;
        x = px();
        y = py();
        final reflect = prev == 'Q' || prev == 'T';
        ctrlX = reflect ? 2 * cx - ctrlX : cx;
        ctrlY = reflect ? 2 * cy - ctrlY : cy;
        emit(kMorphQuad, [ctrlX, ctrlY, x, y]);
      case 'A':
        if (!hasNumbers(7)) return null;
        // 半径、旋转角和两个标志位不随相对坐标偏移。
        final rx = next(), ry = next(), rot = next();
        final large = next(), sweep = next();
        x = px();
        y = py();
        emit(kMorphArc, [rx, ry, rot, large, sweep, x, y]);
      case 'Z':
        emit(kMorphClose, const []);
        x = startX;
        y = startY;
        command = null; // Z 后不能再跟裸数字
      default:
        return null;
    }
    cx = x;
    cy = y;
    prev = cmd;
  }
  return ops.isEmpty ? null : _NormalizedPath(ops, coords);
}

/// 把各关键帧 [frames] 规范化，并在「指令序列完全一致」时返回 [PathMorphData]；
/// 任一帧残缺、不足两帧、或结构不一致（含圆弧标志位不同）时返回 null，调用方
/// 应退化为离散。
///
/// 指令序列一致时各帧参数个数必然相等（每个指令码的参数个数固定）。
///
/// 示例：
/// ```dart
/// buildPathMorphData(['M5 5L19 19', 'M5 5l14 0']); // 兼容：都是 M L
/// buildPathMorphData(['M0 0L1 1', 'M0 0L1 1L2 2']); // null：长度不同
/// ```
PathMorphData? buildPathMorphData(List<String> frames) {
  if (frames.length < 2) return null;
  final normalized = <_NormalizedPath>[];
  for (final frame in frames) {
    final path = _normalizePath(frame);
    if (path == null) return null;
    normalized.add(path);
  }
  final first = normalized.first;
  for (var f = 1; f < normalized.length; f++) {
    final ops = normalized[f].ops;
    if (ops.length != first.ops.length) return null;
    for (var k = 0; k < ops.length; k++) {
      if (ops[k] != first.ops[k]) return null;
    }
  }
  // 圆弧的 large/sweep 是布尔标志，无法插值，必须各帧一致。
  var offset = 0;
  for (final op in first.ops) {
    if (op == kMorphArc) {
      final large = first.coords[offset + _arcLargeFlag];
      final sweep = first.coords[offset + _arcSweepFlag];
      for (var f = 1; f < normalized.length; f++) {
        final coords = normalized[f].coords;
        if (coords[offset + _arcLargeFlag] != large ||
            coords[offset + _arcSweepFlag] != sweep) {
          return null;
        }
      }
    }
    offset += kMorphArity[op];
  }
  return PathMorphData(
    ops: List<int>.unmodifiable(first.ops),
    frames: [for (final path in normalized) Float64List.fromList(path.coords)],
  );
}

/// 按插值位置 [position]（见 [SmilPathAnimation.sample]）直接生成 ui.Path：
/// 边读相邻两帧参数边线性插值，不分配中间缓冲。
///
/// [position] 超出 `[0, frames.length - 1]` 时钳制。
ui.Path buildMorphedPath(PathMorphData data, double position) {
  final last = data.frames.length - 1;
  final index = position.floor().clamp(0, last - 1);
  final t = (position - index).clamp(0.0, 1.0);
  final a = data.frames[index];
  final b = data.frames[index + 1];
  double at(int k) => a[k] + (b[k] - a[k]) * t;

  final path = ui.Path();
  var k = 0;
  for (final op in data.ops) {
    switch (op) {
      case kMorphMove:
        path.moveTo(at(k), at(k + 1));
      case kMorphLine:
        path.lineTo(at(k), at(k + 1));
      case kMorphCubic:
        path.cubicTo(
          at(k),
          at(k + 1),
          at(k + 2),
          at(k + 3),
          at(k + 4),
          at(k + 5),
        );
      case kMorphQuad:
        path.quadraticBezierTo(at(k), at(k + 1), at(k + 2), at(k + 3));
      case kMorphArc:
        path.arcToPoint(
          ui.Offset(at(k + 5), at(k + 6)),
          radius: ui.Radius.elliptical(at(k), at(k + 1)),
          rotation: at(k + 2),
          largeArc: a[k + _arcLargeFlag] != 0,
          clockwise: a[k + _arcSweepFlag] != 0,
        );
      case kMorphClose:
        path.close();
    }
    k += kMorphArity[op];
  }
  return path;
}
