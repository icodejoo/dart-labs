import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// 记录实际弧段和画笔身份；只用于观测，不参与耗时测量。
class PaintProbe implements Canvas {
  final paints = <Paint>{};
  final arcs = <({double start, double sweep, Color color})>[];
  int paragraphs = 0;

  /// 保存弧段数值，避免后续画笔复用覆盖观测值。
  @override
  void drawArc(Rect rect, double startAngle, double sweepAngle, bool useCenter,
      Paint paint) {
    paints.add(paint);
    arcs.add((start: startAngle, sweep: sweepAngle, color: paint.color));
  }

  /// 记录轨道使用的画笔。
  @override
  void drawCircle(Offset c, double radius, Paint paint) => paints.add(paint);

  /// 记录刻度使用的画笔。
  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => paints.add(paint);

  /// 标签每次绘制对应一个临时 TextPainter。
  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) => paragraphs++;

  /// 忽略与弧段、画笔和标签数量无关的画布操作。
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
