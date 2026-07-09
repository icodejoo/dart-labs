import 'package:flutter/widgets.dart';

/// Draws a filled rounded-rect bar over a track — the shared rendering core
/// for `CountdownBar` (bar shrinks as remaining time depletes) and
/// `CounterBar` (bar grows as the value approaches its target). Both
/// widgets only differ in how they compute [progress]; the fill math itself
/// is identical, so it lives here once instead of twice — same split as
/// [RingPainter] for the circular variants.
///
/// Each drawing step is a separate overridable method, same pattern as
/// [RingPainter]. For the common cases — a [gradient]/[trackGradient] fill,
/// filling from the end ([fillFromStart] = false), a thinner track
/// ([trackHeight]), or per-corner rounding ([borderRadiusGeometry]) — pass the
/// constructor arguments instead of subclassing.
class BarPainter extends CustomPainter {
  const BarPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    this.borderRadius = const Radius.circular(4),
    this.borderRadiusGeometry,
    this.gradient,
    this.trackGradient,
    this.fillFromStart = true,
    this.trackHeight,
  });

  /// 0.0–1.0 fraction of the bar to fill.
  final double progress;
  final Color color;
  final Color trackColor;

  /// Uniform corner radius. Ignored when [borderRadiusGeometry] is set.
  final Radius borderRadius;

  /// Optional per-corner radius, overriding the uniform [borderRadius].
  final BorderRadius? borderRadiusGeometry;

  /// Optional gradient painted over the fill, overriding [color].
  final Gradient? gradient;

  /// Optional gradient painted over the track, overriding [trackColor].
  final Gradient? trackGradient;

  /// When true (default) the fill grows from the left/start edge; when false
  /// it grows from the right/end edge.
  final bool fillFromStart;

  /// Track/fill height, vertically centered within the paint size. Defaults to
  /// the full paint height when null.
  final double? trackHeight;

  /// Vertical band the bar occupies within [size], honoring [trackHeight].
  Rect bandFor(Size size) {
    final h = trackHeight ?? size.height;
    final top = (size.height - h) / 2;
    return Rect.fromLTWH(0, top, size.width, h);
  }

  /// The track's rounded-rect shape within [size]. Override for a custom shape.
  RRect trackRRect(Size size) {
    final band = bandFor(size);
    return borderRadiusGeometry != null
        ? borderRadiusGeometry!.toRRect(band)
        : RRect.fromRectAndRadius(band, borderRadius);
  }

  /// Draws the background track. Override to customize or skip it.
  void paintTrack(Canvas canvas, RRect track) {
    final paint = Paint();
    if (trackGradient != null) {
      paint.shader = trackGradient!.createShader(track.outerRect);
    } else {
      paint.color = trackColor;
    }
    canvas.drawRRect(track, paint);
  }

  /// Draws the filled portion, clipped to [track]'s shape. Override to
  /// customize (striped pattern, a trailing "thumb", etc).
  void paintFill(Canvas canvas, RRect track, Size size) {
    final p = progress.clamp(0.0, 1.0);
    if (p <= 0) return;
    final band = bandFor(size);
    final w = band.width * p;
    final fillRect = fillFromStart
        ? Rect.fromLTWH(band.left, band.top, w, band.height)
        : Rect.fromLTWH(band.right - w, band.top, w, band.height);
    final paint = Paint();
    if (gradient != null) {
      paint.shader = gradient!.createShader(band);
    } else {
      paint.color = color;
    }
    canvas.save();
    canvas.clipRRect(track);
    canvas.drawRect(fillRect, paint);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final track = trackRRect(size);
    paintTrack(canvas, track);
    paintFill(canvas, track, size);
  }

  @override
  bool shouldRepaint(BarPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.borderRadius != borderRadius ||
      old.borderRadiusGeometry != borderRadiusGeometry ||
      old.gradient != gradient ||
      old.trackGradient != trackGradient ||
      old.fillFromStart != fillFromStart ||
      old.trackHeight != trackHeight;
}
