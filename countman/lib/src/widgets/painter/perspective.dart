import 'package:flutter/foundation.dart' show internal;
import 'package:flutter/widgets.dart';

/// 单线程绘制复用矩阵；Canvas.transform 立即拷贝 storage，嵌套旋转也安全。
final _rotationMatrix = Matrix4.identity();

/// 直接应用绕中心的透视旋转，由调用者保存和恢复画布。
@internal
void transformRotateX(Canvas canvas, Offset center, double angle, double perspective) {
  canvas.translate(center.dx, center.dy);
  _rotationMatrix
    ..setIdentity()
    ..setEntry(3, 2, perspective)
    ..rotateX(angle);
  canvas.transform(_rotationMatrix.storage);
  canvas.translate(-center.dx, -center.dy);
}

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
  transformRotateX(canvas, center, angle, perspective);
  draw();
  canvas.restore();
}
