import 'dart:math' as math;
import 'package:flutter/widgets.dart';

/// Draws a circular arc over a full-circle track — the shared rendering
/// core for `CountdownRing` (arc depletes as remaining time shrinks) and
/// `CounterRing` (arc fills as the value approaches its target). Both
/// widgets only differ in how they compute [progress]; the arc math itself
/// is identical, so it lives here once instead of twice.
///
/// Every drawing step is a separate overridable method so a subclass can
/// customize one piece (e.g. a gradient arc, an offset center, a dashed
/// track) without reimplementing [paint] from scratch:
///
/// ```dart
/// class GradientRingPainter extends RingPainter {
///   const GradientRingPainter({required super.progress, ...});
///   @override
///   void paintArc(Canvas canvas, Offset center, double radius, Paint paint) {
///     paint.shader = SweepGradient(colors: [Colors.blue, Colors.purple])
///         .createShader(Rect.fromCircle(center: center, radius: radius));
///     super.paintArc(canvas, center, radius, paint);
///   }
/// }
/// ```
class RingPainter extends CustomPainter {
  const RingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
    required this.clockwise,
  });

  /// 0.0–1.0 fraction of the arc to draw.
  final double progress;
  final Color color;
  final Color trackColor;
  final double strokeWidth;
  final bool clockwise;

  /// Center of the ring within [size]. Override to offset it.
  Offset centerFor(Size size) => size.center(Offset.zero);

  /// Radius of the ring within [size]. Override for a custom radius rule.
  /// Clamped to `>= 0` so an over-large [strokeWidth] can't produce a negative
  /// radius (which draws a degenerate arc).
  double radiusFor(Size size) {
    final r = (size.shortestSide - strokeWidth) / 2;
    return r < 0 ? 0 : r;
  }

  /// Builds the [Paint] shared by [paintTrack] and [paintArc]. Override to
  /// customize cap/join/shader — [paintArc]/[paintTrack] still overwrite
  /// `color` before each stroke, so a shader set here is the easiest hook.
  Paint buildStrokePaint() => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = strokeWidth
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;

  /// Draws the background track circle. Override to customize or skip it.
  void paintTrack(Canvas canvas, Offset center, double radius, Paint paint) {
    paint.color = trackColor;
    canvas.drawCircle(center, radius, paint);
  }

  /// Draws the progress arc. Override to customize (multi-segment, gradient,
  /// a leading "thumb" dot, etc).
  void paintArc(Canvas canvas, Offset center, double radius, Paint paint) {
    if (progress <= 0) return;
    paint.color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, // start at 12 o'clock
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
      old.strokeWidth != strokeWidth;
}
