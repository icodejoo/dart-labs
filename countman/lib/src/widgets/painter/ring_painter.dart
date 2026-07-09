import 'dart:math' as math;
import 'package:flutter/widgets.dart';

/// Draws a circular arc over a full-circle track — the shared rendering
/// core for `CountdownRing` (arc depletes as remaining time shrinks) and
/// `CounterRing` (arc fills as the value approaches its target). Both
/// widgets only differ in how they compute [progress]; the arc math itself
/// is identical, so it lives here once instead of twice.
///
/// Every drawing step is a separate overridable method so a subclass can
/// customize one piece (e.g. a dashed track, an offset center) without
/// reimplementing [paint] from scratch. For the common cases —
/// [gradient]/[trackGradient] shaders, a custom [startAngle], [strokeCap],
/// a thinner track ([trackStrokeWidth]), or [padding] — pass the constructor
/// arguments instead of subclassing:
///
/// ```dart
/// RingPainter(
///   progress: 0.6, color: Colors.blue, trackColor: Colors.grey,
///   strokeWidth: 8, clockwise: true,
///   gradient: SweepGradient(colors: [Colors.blue, Colors.purple]),
///   strokeCap: StrokeCap.butt,
/// )
/// ```
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

  /// The drawing rect after applying [padding].
  Rect rectFor(Size size) => padding.deflateRect(Offset.zero & size);

  /// Center of the ring within [size]. Override to offset it.
  Offset centerFor(Size size) => rectFor(size).center;

  /// Radius of the ring within [size]. Override for a custom radius rule.
  /// Clamped to `>= 0` so an over-large stroke can't produce a negative
  /// radius (which draws a degenerate arc).
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

  /// Draws the background track circle. Override to customize or skip it.
  void paintTrack(Canvas canvas, Offset center, double radius, Paint paint) {
    paint.strokeWidth = trackStrokeWidth ?? strokeWidth;
    if (trackGradient != null) {
      paint.shader = trackGradient!
          .createShader(Rect.fromCircle(center: center, radius: radius));
    } else {
      paint.shader = null;
      paint.color = trackColor;
    }
    canvas.drawCircle(center, radius, paint);
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
      2 * math.pi * progress * (clockwise ? 1 : -1),
      false,
      paint,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = centerFor(size);
    final radius = radiusFor(size);
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
      old.padding != padding;
}
