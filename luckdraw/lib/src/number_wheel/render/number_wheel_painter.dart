import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../core/foundation/angles.dart';
import '../../core/foundation/constants.dart';
import '../../core/geometry/canvas_arc.dart';
import '../../core/motion/phase.dart';
import '../../core/render/cached_picture.dart';
import '../../core/render/layer.dart';
import '../../core/render/paint_helpers.dart';
import '../../core/render/perf_trace.dart';
import '../../core/render/picture_cache.dart';
import '../../core/render/renderer.dart';
import '../layout/number_wheel_layout.dart';
import '../model/number_wheel_config.dart';
import '../motion/number_wheel_motion.dart';

/// 外轨缓存编号。
const int _trackId = 0;

/// 圆盘缓存编号。
const int _discId = 1;

/// 小球缓存编号。
const int _ballId = 2;

/// 用户静态层编号起点。
const int _layerBase = 100;

/// 刻度线占标签环宽的比例，给数字留出空间。
const double _tickFraction = 0.15;

/// 数字转盘画笔；缓存归 surface 所有，帧内只进行变换与回放。
final class NumberWheelPainter extends CustomPainter {
  /// 预录制缺失的段；调用者在布局或图片版本改变时失效 [cache]。
  NumberWheelPainter(this.data, this.cache)
      : super(
            repaint: Listenable.merge(
                [data.frameListenable, data.imagesListenable])) {
    luckyTraceStart('luckdraw.number_wheel.record');
    try {
      _track = cache.picture(_trackId, _recordTrack);
      _disc = LuckyCachedPicture(cache, _discId, Offset.zero & data.layout.size,
          data.devicePixelRatio, _recordDisc, data.performance);
      _ball = cache.picture(_ballId, _recordBall);
      _context = LuckyLayerContext<NumberWheelLayout, NumberWheelFrame>()
        ..size = data.layout.size
        ..layout = data.layout
        ..frame = data.frame
        ..devicePixelRatio = data.devicePixelRatio;
      for (var i = 0; i < data.layers.length; i++) {
        final layer = data.layers[i];
        _layerPictures.add(layer.isStatic
            ? cache.picture(
                _layerBase + i, (canvas) => layer.paint(canvas, _context))
            : null);
      }
    } finally {
      luckyTraceEnd();
    }
  }

  /// 当前低频输入。
  final LuckySurfaceData<NumberWheelConfig, NumberWheelLayout, NumberWheelFrame>
      data;

  /// 跨重建持有的缓存。
  final LuckyPictureCache cache;

  /// 外轨显示列表。
  late final ui.Picture _track;

  /// 整盘显示列表。
  late final LuckyCachedPicture _disc;

  /// 小球显示列表。
  late final ui.Picture _ball;

  /// 复用层上下文。
  late final LuckyLayerContext<NumberWheelLayout, NumberWheelFrame> _context;

  /// 静态层的显示列表，动态层为空。
  final List<ui.Picture?> _layerPictures = [];

  /// 录制固定外轨。
  void _recordTrack(Canvas canvas) {
    final l = data.layout;
    final bounds = Rect.fromCircle(center: l.center, radius: l.radius);
    paintLuckyOval(canvas, bounds, data.config.style.trackFill);
  }

  /// 录制圆盘和全部刻度，标签按布局间隔抽稀。
  void _recordDisc(Canvas canvas) {
    final l = data.layout, c = data.config;
    final o = c.options;
    canvas.save();
    canvas.translate(l.center.dx, l.center.dy);
    final bounds = Rect.fromCircle(
        center: Offset.zero, radius: l.radius * o.trackInnerFactor);
    paintLuckyOval(canvas, bounds, c.style.background);
    final outerRect = Rect.fromCircle(
        center: Offset.zero, radius: l.radius * o.pocketOuterFactor);
    final innerRect = Rect.fromCircle(
        center: Offset.zero, radius: l.radius * o.pocketInnerFactor);
    final labels = LuckyTextPass(
        textDirection: data.textDirection, textScale: data.textScale);
    try {
      for (var i = 0; i < c.pockets.length; i++) {
        final mid = luckyDegToRad(i * kLuckyFullTurnDeg / c.pockets.length +
            o.offsetDegree +
            kLuckyPointerDeg);
        final half = math.pi / c.pockets.length;
        final sweep = canvasArcSweep(mid - half, mid + half);
        // 环形扇面：外弧顺时针、内弧逆时针回到起点，无需布尔运算。
        final ring = Path()
          ..arcTo(outerRect, mid - half, sweep, true)
          ..arcTo(innerRect, mid + half, -sweep, false)
          ..close();
        paintLuckyFill(
            canvas,
            ring,
            c.pockets[i].fill ??
                kNumberWheelDefaultPalette[
                    i % kNumberWheelDefaultPalette.length],
            bounds);
        canvas.save();
        canvas.rotate(mid);
        canvas.drawLine(
            Offset(
                l.radius *
                    (o.labelOuterFactor -
                        (o.labelOuterFactor - o.labelInnerFactor) *
                            _tickFraction),
                0),
            Offset(l.radius * o.labelOuterFactor, 0),
            luckyScratchPaint(color: c.style.textColor));
        if (i % l.labelEvery == 0) {
          final text = labels.layout(TextSpan(
              text: c.pockets[i].label ?? c.pockets[i].number.toString(),
              style: TextStyle(
                  color: c.style.textColor,
                  fontSize: c.style.fontSize,
                  fontFamily: c.style.fontFamily)));
          text.paint(
              canvas,
              Offset(l.labelRadius - text.width / kLuckyHalfDivisor,
                  -text.height / kLuckyHalfDivisor));
        }
        canvas.restore();
      }
    } finally {
      labels.dispose();
    }
    final hub = Rect.fromCircle(center: Offset.zero, radius: l.hubRadius);
    paintLuckyOval(canvas, hub, c.style.hubFill);
    canvas.restore();
  }

  /// 录制圆心在原点的小球。
  void _recordBall(Canvas canvas) {
    final rect =
        Rect.fromCircle(center: Offset.zero, radius: data.layout.ballSize);
    paintLuckyOval(canvas, rect, data.config.style.ballFill);
  }

  /// 回放指定位置的用户层。
  void _layers(Canvas canvas, LuckyLayerPosition position) =>
      luckyReplayLayers(canvas, data.layers, _layerPictures, position, _context,
          rotate: _rotate);

  /// 绕布局圆心旋转当前画布。
  void _rotate(Canvas canvas) {
    final center = data.layout.center;
    canvas.translate(center.dx, center.dy);
    canvas.rotate(luckyDegToRad(data.frame.discDeg));
    canvas.translate(-center.dx, -center.dy);
  }

  /// 每帧平衡变换、回放与钩子；不录制显示列表。
  @override
  void paint(Canvas canvas, Size size) {
    luckyTraceStart('luckdraw.number_wheel.paint');
    try {
      data.hooks.beforeDraw?.call(canvas, size);
      _layers(canvas, LuckyLayerPosition.background);
      canvas.drawPicture(_track);
      _layers(canvas, LuckyLayerPosition.belowItems);
      canvas.save();
      _rotate(canvas);
      _disc.paint(canvas, isMoving: data.frame.phase.isMoving);
      canvas.restore();
      final angle = luckyDegToRad(data.frame.ballDeg + kLuckyPointerDeg);
      canvas.save();
      canvas.translate(
          data.layout.center.dx + data.frame.ballRadius * math.cos(angle),
          data.layout.center.dy + data.frame.ballRadius * math.sin(angle));
      canvas.drawPicture(_ball);
      canvas.restore();
      _layers(canvas, LuckyLayerPosition.aboveItems);
      _layers(canvas, LuckyLayerPosition.foreground);
      data.hooks.afterDraw?.call(canvas, size);
    } finally {
      luckyTraceEnd();
    }
  }

  /// 输入版本变化时请求重绘。
  @override
  bool shouldRepaint(covariant NumberWheelPainter oldDelegate) =>
      data != oldDelegate.data;
}
