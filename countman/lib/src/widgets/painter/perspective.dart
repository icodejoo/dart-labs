import 'package:flutter/widgets.dart';

/// Applies a perspective `rotateX` transform around [center] for the
/// duration of [draw], then restores the canvas.
///
/// Shared by [FlipCardPainter] (rotating half-cards and whole cards) and
/// [CounterPainter] (rotating a single digit glyph) — same technique
/// Flutter's `Transform` widget uses internally (a 4x4 matrix with a
/// perspective entry), just applied directly to [Canvas] so many rotating
/// cells cost one [CustomPainter] repaint, not one compositor layer each.
void applyRotateX(Canvas canvas, Offset center, double angle, double perspective, void Function() draw) {
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.transform((Matrix4.identity()
        ..setEntry(3, 2, perspective)
        ..rotateX(angle))
      .storage);
  canvas.translate(-center.dx, -center.dy);
  draw();
  canvas.restore();
}
