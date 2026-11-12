import 'dart:math' as math;
import 'dart:ui';

import '../foundation/angles.dart';
import '../foundation/constants.dart';
import 'canvas_arc.dart';

/// 返回外弧与内侧顶点围成的扇形路径。
///
/// [start]/[end] 使用弧度，[gutter] 使用逻辑像素；[outerRadius] 非正返回空路径。
/// 例如 `buildFanPath(outerRadius: 100, start: 0, end: 1, gutter: 0)`。
Path buildFanPath(
    {required double outerRadius,
    required double start,
    required double end,
    required double gutter}) {
  final path = Path();
  if (!(outerRadius > 0)) return path;
  // 上游 math.ts:43-60；保留间距换算与顶点公式的运算顺序。
  final maxGutter =
      luckyDegToRad(kLuckyQuarterTurnDeg / math.pi / outerRadius * gutter);
  final maxStart = start + maxGutter;
  final maxEnd = end - maxGutter;
  path.addArc(Rect.fromCircle(center: Offset.zero, radius: outerRadius),
      maxStart, canvasArcSweep(maxStart, maxEnd));
  final apexR = gutter /
      kLuckyHalfDivisor /
      math.sin((start - end) / kLuckyHalfDivisor).abs();
  final mid = (start + end) / kLuckyHalfDivisor;
  path.lineTo(math.cos(mid) * apexR, math.sin(mid) * apexR);
  path.close();
  return path;
}
