import 'dart:math' as math;

import 'package:countman/countman.dart';
import 'package:flutter/widgets.dart';

/// 保留原内圈算法，供合并候选进行独立的耗时和视觉对照。
class InnerReference extends CustomPainter {
  /// 指定时间、配色和是否启用待验证的分钟段合并。
  const InnerReference({
    this.totalMs = 3600000,
    this.remainingMs = 3600000,
    this.merged = false,
    this.clockwise = true,
    this.glow = false,
    this.colors = const DialColors(),
    this.redAt = 3,
    this.yellowAt = 10,
  });

  final int totalMs;
  final int remainingMs;
  final bool merged;
  final bool clockwise;
  final bool glow;
  final DialColors colors;
  final int redAt;
  final int yellowAt;

  /// 逐笔复现生产内圈，仅在候选分支合并连续的普通色分钟段。
  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final sc = size.shortestSide / 100;
    final radius = 27.5 * sc;
    final strokeWidth = 2.8 * sc;
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = const Color(0x38968C94)
        ..isAntiAlias = true,
    );
    if (totalMs <= 0) return;
    final quantized =
        remainingMs <= 0 ? 0 : ((remainingMs + 999) ~/ 1000) * 1000;
    final rem =
        math.max(0.0, math.min(quantized.toDouble(), totalMs.toDouble()));

    /// 将剩余时间映射到与生产实现相同的角度。
    double angleAt(double ms) =>
        -math.pi / 2 - (clockwise ? 1 : -1) * (ms / totalMs) * 2 * math.pi;

    /// 保留原来的圆头、微小弧过滤和绘制顺序。
    void drawSeg(double t0, double t1, Color color) {
      final hi = math.min(t1, rem);
      if (hi <= t0) return;
      final a0 = angleAt(t0);
      final sweep = angleAt(hi) - a0;
      if (sweep.abs() < 1e-6) return;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = color
        ..isAntiAlias = true;
      if (glow) {
        paint.maskFilter = const MaskFilter.blur(BlurStyle.outer, 2);
      }
      canvas.drawArc(Rect.fromCircle(center: centre, radius: radius), a0, sweep,
          false, paint);
    }

    if (merged) {
      drawSeg(60000, totalMs.toDouble(), colors.normal);
    } else {
      final n = math.max(1, (totalMs / 60000).ceil());
      for (var j = 1; j < n; j++) {
        drawSeg(j * 60000.0, math.min((j + 1) * 60000.0, totalMs.toDouble()),
            colors.normal);
      }
    }
    drawSeg(yellowAt * 1000.0, 60000, colors.green);
    drawSeg(redAt * 1000.0, yellowAt * 1000.0, colors.yellow);
    drawSeg(0, redAt * 1000.0, colors.red);
  }

  /// 本夹具配置固定，不参与框架驱动的动画。
  @override
  bool shouldRepaint(InnerReference oldDelegate) => false;
}
