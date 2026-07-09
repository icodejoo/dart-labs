import 'package:flutter/widgets.dart';

/// Draws a filled rounded-rect bar over a track — the shared rendering core
/// for `CountdownBar` (bar shrinks as remaining time depletes) and
/// `CounterBar` (bar grows as the value approaches its target). Both
/// widgets only differ in how they compute [progress]; the fill math itself
/// is identical, so it lives here once instead of twice — same split as
/// [RingPainter] for the circular variants.
///
/// Each drawing step is a separate overridable method, same pattern as
/// [RingPainter] — override just the piece you need:
///
/// ```dart
/// class StripedBarPainter extends BarPainter {
///   const StripedBarPainter({required super.progress, ...});
///   @override
///   void paintFill(Canvas canvas, RRect track, Size size) {
///     super.paintFill(canvas, track, size); // base fill
///     // ...draw stripes on top...
///   }
/// }
/// ```
class BarPainter extends CustomPainter {
  const BarPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    this.borderRadius = const Radius.circular(4),
  });

  /// 0.0–1.0 fraction of the bar to fill, from the left.
  final double progress;
  final Color color;
  final Color trackColor;
  final Radius borderRadius;

  /// The track's rounded-rect shape within [size]. Override for a custom
  /// shape (e.g. square corners only on one end).
  RRect trackRRect(Size size) => RRect.fromRectAndRadius(Offset.zero & size, borderRadius);

  /// Draws the background track. Override to customize or skip it.
  void paintTrack(Canvas canvas, RRect track) {
    canvas.drawRRect(track, Paint()..color = trackColor);
  }

  /// Draws the filled portion, clipped to [track]'s shape. Override to
  /// customize (gradient fill, striped pattern, a trailing "thumb", etc).
  void paintFill(Canvas canvas, RRect track, Size size) {
    final p = progress.clamp(0.0, 1.0);
    if (p <= 0) return;
    canvas.save();
    canvas.clipRRect(track);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width * p, size.height), Paint()..color = color);
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
      old.borderRadius != borderRadius;
}
