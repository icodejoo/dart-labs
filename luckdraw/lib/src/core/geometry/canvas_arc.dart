import 'dart:math' as math;

import '../foundation/constants.dart';

/// 完整圆周的弧度数。
const double _fullTurn = kLuckyHalfDivisor * math.pi;

/// 返回 Canvas 顺时针圆弧从 [start] 到 [end] 的实际扫角，单位为弧度。
///
/// 正向差值达到一周时返回一周，负差值按余数绕回；例如 `(0, -pi)` 返回 pi。
double canvasArcSweep(double start, double end) {
  var d = end - start;
  if (d >= _fullTurn) return _fullTurn;
  d = d.remainder(_fullTurn);
  if (d < 0) d += _fullTurn;
  return d;
}
