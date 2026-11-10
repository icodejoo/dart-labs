import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../foundation/border.dart';
import '../foundation/constants.dart';
import '../foundation/fill.dart';
import '../foundation/shadow.dart';
import '../text/text_line.dart';
import '../text/text_measurer.dart';
import 'perf_trace.dart';

/// 录制阶段先绘制偏移阴影，再绘制 [fill]；[dpr] 用于设备空间模糊。
void paintLuckyFill(Canvas canvas, Path path, LuckyFill fill, Rect bounds,
    {LuckyShadow? shadow, double dpr = 1}) {
  if (shadow != null) {
    final sigma = shadow.sigma(dpr);
    final paint = Paint()..color = shadow.colorOver(fill);
    if (sigma > 0) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);
    }
    canvas.drawPath(path.shift(Offset(shadow.offsetX, shadow.offsetY)), paint);
  }
  final paint = Paint();
  fill.applyTo(paint, bounds);
  canvas.drawPath(path, paint);
}

/// 录制阶段绘制圆角边框；非正宽度时不绘制。
void strokeLuckyBorder(
    Canvas canvas, Rect rect, double radius, LuckyBorder border) {
  if (border.width <= 0) return;
  canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = border.width
        ..color = border.color);
}

/// 录制阶段绘制图片；通过画笔 alpha 表达透明度，不创建 saveLayer。
void drawLuckyImage(Canvas canvas, ui.Image image, Rect dst,
    {double? borderRadius,
    double opacity = 1,
    FilterQuality filterQuality = FilterQuality.low}) {
  final paint = Paint()
    ..filterQuality = filterQuality
    ..color = kLuckyDefaultFontColor
        .withAlpha((kLuckyMaxAlpha8 * opacity.clamp(0, 1)).round());
  final clipped = borderRadius != null && borderRadius > 0;
  if (clipped) {
    canvas.save();
    canvas
        .clipRRect(RRect.fromRectAndRadius(dst, Radius.circular(borderRadius)));
  }
  canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dst,
      paint);
  if (clipped) {
    canvas.restore();
  }
}

/// 录制阶段按字母基线绘制各行，并释放所有临时 TextPainter。
///
/// [textScale] 应传入 LuckySurfaceData.textScale，与布局测量使用同一缩放。
/// [baselineCache] 保留供既有调用兼容；基线始终取实际绘制段落的字体度量。
void paintLuckyTextLines(
    Canvas canvas, List<LuckyTextLine> lines, LuckyTextMeasurer? baselineCache,
    {TextDirection textDirection = TextDirection.ltr,
    TextScaler textScale = TextScaler.noScaling}) {
  for (final line in lines) {
    final painter = TextPainter(
        text: TextSpan(
            text: normalizeLuckyCanvasText(line.text), style: line.style),
        textDirection: textDirection,
        textScaler: textScale);
    try {
      luckyTraceStart(kLuckyTextPainterLayoutTrace, layouts: 1);
      try {
        painter.layout();
      } finally {
        luckyTraceEnd();
      }
      final baseline =
          painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      painter.paint(canvas, Offset(line.x, line.baselineY - baseline));
    } finally {
      painter.dispose();
    }
  }
}
