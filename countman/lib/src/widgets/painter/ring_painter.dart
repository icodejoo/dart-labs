import 'dart:math' as math;
import 'package:flutter/widgets.dart';

/// Draws a circular arc over a track — the shared rendering core for
/// `CountdownRing` (arc depletes) and `CounterRing` (arc fills). Both widgets
/// only differ in how they compute [progress]; the arc math lives here once.
///
/// The track/arc span a configurable [sweepAngle] (default a full circle),
/// so partial-arc "gauge" styles (e.g. a 270° speedometer) work by passing
/// `sweepAngle: 270 * pi / 180`. An optional [backgroundColor] fills the disc
/// behind the ring, and [showTrack] can hide the track entirely.
///
/// Every drawing step is a separate overridable method so a subclass can
/// customize one piece without reimplementing [paint].
///
/// 绘制轨道上的圆弧——`CountdownRing`（弧递减）与 `CounterRing`（弧填充）的
/// 共享渲染核心。轨道/弧跨越可配置的 [sweepAngle]（默认整圆），因此传入
/// `sweepAngle: 270 * pi / 180` 即可实现部分弧的"仪表盘"样式。可选的
/// [backgroundColor] 在环形背后填充圆盘，[showTrack] 可完全隐藏轨道。
class RingPainter extends CustomPainter {
  const RingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
    required this.clockwise,
    this.startAngle = -math.pi / 2,
    this.strokeCap = StrokeCap.round,
    this.gradient,
    this.trackGradient,
    this.trackStrokeWidth,
    this.padding = EdgeInsets.zero,
    this.sweepAngle = 2 * math.pi,
    this.showTrack = true,
    this.backgroundColor,
  });

  /// 0.0–1.0 fraction of the arc to draw.
  final double progress;
  final Color color;
  final Color trackColor;
  final double strokeWidth;
  final bool clockwise;

  /// Angle (radians) the arc starts from. Default: `-pi/2` (12 o'clock).
  final double startAngle;

  /// Cap drawn at the arc ends. Default: [StrokeCap.round].
  final StrokeCap strokeCap;

  /// Optional gradient painted along the arc, overriding [color].
  final Gradient? gradient;

  /// Optional gradient painted on the track, overriding [trackColor].
  final Gradient? trackGradient;

  /// Track stroke width. Defaults to [strokeWidth] when null.
  final double? trackStrokeWidth;

  /// Inset applied before computing the ring's center and radius.
  final EdgeInsets padding;

  /// Total angular span (radians) of the track. Default: `2*pi` (full circle).
  /// Values below `2*pi` produce a partial-arc gauge; the progress arc fills
  /// [progress] of this span.
  ///
  /// 轨道的总角跨度（弧度）。默认 `2*pi`（整圆）。小于 `2*pi` 得到部分弧仪表盘；
  /// 进度弧填充此跨度的 [progress]。
  final double sweepAngle;

  /// When false, the background track is not drawn (only the progress arc).
  ///
  /// 为 false 时不绘制背景轨道（只画进度弧）。
  final bool showTrack;

  /// Optional solid fill of the disc behind the ring (radius up to the ring).
  ///
  /// 可选：环形背后圆盘的实心填充（半径至环形处）。
  final Color? backgroundColor;

  /// The drawing rect after applying [padding].
  Rect rectFor(Size size) => padding.deflateRect(Offset.zero & size);

  /// Center of the ring within [size]. Override to offset it.
  Offset centerFor(Size size) => rectFor(size).center;

  /// Radius of the ring within [size]. Override for a custom radius rule.
  double radiusFor(Size size) {
    final maxStroke = math.max(strokeWidth, trackStrokeWidth ?? strokeWidth);
    final r = (rectFor(size).shortestSide - maxStroke) / 2;
    return r < 0 ? 0 : r;
  }

  /// Builds the [Paint] shared by [paintTrack] and [paintArc].
  Paint buildStrokePaint() => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = strokeWidth
    ..strokeCap = strokeCap
    ..isAntiAlias = true;

  /// Fills the disc behind the ring with [backgroundColor], when set.
  ///
  /// 当设置了 [backgroundColor] 时，填充环形背后的圆盘。
  void paintBackground(Canvas canvas, Offset center, double radius) {
    if (backgroundColor == null) return;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.fill
        ..color = backgroundColor!
        ..isAntiAlias = true,
    );
  }

  /// Draws the background track arc. Override to customize or skip it.
  void paintTrack(Canvas canvas, Offset center, double radius, Paint paint) {
    if (!showTrack) return;
    paint.strokeWidth = trackStrokeWidth ?? strokeWidth;
    final rect = Rect.fromCircle(center: center, radius: radius);
    if (trackGradient != null) {
      paint.shader = trackGradient!.createShader(rect);
    } else {
      paint.shader = null;
      paint.color = trackColor;
    }
    canvas.drawArc(rect, startAngle, sweepAngle * (clockwise ? 1 : -1), false, paint);
  }

  /// Draws the progress arc. Override to customize (multi-segment, a leading
  /// "thumb" dot, etc).
  void paintArc(Canvas canvas, Offset center, double radius, Paint paint) {
    if (progress <= 0) return;
    paint.strokeWidth = strokeWidth;
    final rect = Rect.fromCircle(center: center, radius: radius);
    if (gradient != null) {
      paint.shader = gradient!.createShader(rect);
    } else {
      paint.shader = null;
      paint.color = color;
    }
    canvas.drawArc(
      rect,
      startAngle,
      sweepAngle * progress * (clockwise ? 1 : -1),
      false,
      paint,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = centerFor(size);
    final radius = radiusFor(size);
    paintBackground(canvas, center, radius);
    final paint = buildStrokePaint();
    paintTrack(canvas, center, radius, paint);
    paintArc(canvas, center, radius, paint);
  }

  @override
  bool shouldRepaint(RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.strokeWidth != strokeWidth ||
      old.clockwise != clockwise ||
      old.startAngle != startAngle ||
      old.strokeCap != strokeCap ||
      old.gradient != gradient ||
      old.trackGradient != trackGradient ||
      old.trackStrokeWidth != trackStrokeWidth ||
      old.padding != padding ||
      old.sweepAngle != sweepAngle ||
      old.showTrack != showTrack ||
      old.backgroundColor != backgroundColor;
}
