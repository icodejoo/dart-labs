import 'dart:math' as math;
import 'dart:ui';

import '../foundation/constants.dart';

/// 返回 [rect] 的圆角矩形路径；半径限制在零与短边一半之间。
///
/// 非正宽高返回空路径；例如 `buildRoundRectPath(rect, 8)`。
Path buildRoundRectPath(Rect rect, double radius) {
  final path = Path();
  if (rect.width <= 0 || rect.height <= 0) return path;
  final r = math.max(0.0,
      math.min(radius, math.min(rect.width, rect.height) / kLuckyHalfDivisor));
  path.addRRect(RRect.fromRectAndRadius(rect, Radius.circular(r)));
  return path;
}
