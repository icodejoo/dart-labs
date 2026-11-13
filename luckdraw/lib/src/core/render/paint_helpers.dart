import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../foundation/border.dart';
import '../foundation/constants.dart';
import '../foundation/fill.dart';
import '../foundation/shadow.dart';
import '../foundation/unit_range.dart';
import '../text/text_line.dart';
import '../text/text_measurer.dart';
import 'perf_trace.dart';

/// 首次绘制时创建并复用的圆形路径；每次使用前重置，不在顶层初始化。
Path? _ovalScratch;

/// 录制阶段以 [bounds] 的内切椭圆为形状绘制 [fill]，等价于对椭圆路径调用 [paintLuckyFill]。
///
/// 例如 `paintLuckyOval(canvas, Rect.fromCircle(center: Offset.zero, radius: 50), fill)`。
void paintLuckyOval(Canvas canvas, Rect bounds, LuckyFill fill,
    {LuckyShadow? shadow, double dpr = 1}) {
  final path = _ovalScratch ??= Path();
  path.reset();
  path.addOval(bounds);
  paintLuckyFill(canvas, path, fill, bounds, shadow: shadow, dpr: dpr);
}

/// 首次绘制时创建并复用的共享画笔；每次使用前整体复位，不在顶层初始化。
Paint? _scratchPaint;

/// 返回复位后的共享画笔，仅供录制期单次绘制即用即弃，不可跨绘制调用持有。
///
/// 颜色、描边宽度、样式与滤镜质量按参数设置，着色器与模糊遮罩清空；
/// 例如 `canvas.drawRect(rect, luckyScratchPaint(color: Colors.red))`。
Paint luckyScratchPaint(
    {Color color = kLuckyDefaultFontColor,
    PaintingStyle style = PaintingStyle.fill,
    double strokeWidth = 0,
    FilterQuality filterQuality = FilterQuality.none}) {
  final paint = _scratchPaint ??= Paint();
  paint.color = color;
  paint.style = style;
  paint.strokeWidth = strokeWidth;
  paint.filterQuality = filterQuality;
  paint.shader = null;
  paint.maskFilter = null;
  return paint;
}

/// 录制阶段先绘制偏移阴影，再绘制 [fill]；[dpr] 用于设备空间模糊。
void paintLuckyFill(Canvas canvas, Path path, LuckyFill fill, Rect bounds,
    {LuckyShadow? shadow, double dpr = 1}) {
  final paint = luckyScratchPaint();
  if (shadow != null) {
    final sigma = shadow.sigma(dpr);
    paint.color = shadow.colorOver(fill);
    if (sigma > 0) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);
    }
    canvas.drawPath(path.shift(Offset(shadow.offsetX, shadow.offsetY)), paint);
    luckyScratchPaint();
  }
  fill.applyTo(paint, bounds);
  canvas.drawPath(path, paint);
}

/// 录制阶段复用一个 TextPainter 逐段排版，结束后须 [dispose]。
///
/// 每次 [layout] 仍记录一次排版追踪事件；例如逐行绘制标签时共用同一个对象。
final class LuckyTextPass {
  /// 以统一的文字方向与缩放创建。
  LuckyTextPass(
      {TextDirection textDirection = TextDirection.ltr,
      TextScaler textScale = TextScaler.noScaling})
      : _painter =
            TextPainter(textDirection: textDirection, textScaler: textScale);

  /// 复用的段落绘制器。
  final TextPainter _painter;

  /// 排版 [span] 并返回已就绪的绘制器，返回值只在下次 [layout] 前有效。
  TextPainter layout(TextSpan span) {
    _painter.text = span;
    luckyTraceStart(kLuckyTextPainterLayoutTrace, layouts: 1);
    try {
      _painter.layout();
    } finally {
      luckyTraceEnd();
    }
    return _painter;
  }

  /// 释放原生段落资源。
  void dispose() => _painter.dispose();
}

/// 录制阶段绘制圆角边框；非正宽度时不绘制。
void strokeLuckyBorder(
    Canvas canvas, Rect rect, double radius, LuckyBorder border) {
  if (border.width <= 0) return;
  canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      luckyScratchPaint(
          style: PaintingStyle.stroke,
          strokeWidth: border.width,
          color: border.color));
}

/// 录制阶段绘制图片；通过画笔 alpha 表达透明度，不创建 saveLayer。
void drawLuckyImage(Canvas canvas, ui.Image image, Rect dst,
    {double? borderRadius,
    double opacity = 1,
    FilterQuality filterQuality = FilterQuality.low}) {
  final paint = luckyScratchPaint(
      filterQuality: filterQuality,
      color: kLuckyDefaultFontColor
          .withAlpha((kLuckyMaxAlpha8 * luckyUnit(opacity)).round()));
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
  if (lines.isEmpty) return;
  final pass =
      LuckyTextPass(textDirection: textDirection, textScale: textScale);
  try {
    for (final line in lines) {
      final painter = pass.layout(TextSpan(
          text: normalizeLuckyCanvasText(line.text), style: line.style));
      final baseline =
          painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      painter.paint(canvas, Offset(line.x, line.baselineY - baseline));
    }
  } finally {
    pass.dispose();
  }
}
