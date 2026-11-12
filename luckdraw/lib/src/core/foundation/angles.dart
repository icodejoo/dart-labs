import 'dart:math' as math;

import 'constants.dart';

/// 把角度 [deg] 转为弧度，保留符号且不归一化。
///
/// 例如 `luckyDegToRad(180)` 返回 π；运算顺序与上游 getAngle 一致。
double luckyDegToRad(double deg) => math.pi / kLuckyHalfTurnDeg * deg;

/// 把 [value] 绕回 `[0, period)`：先取余，负余数再加一个 [period]。
///
/// 例如 `luckyWrap(-90, 360)` 返回 270。
double luckyWrap(double value, double period) {
  final r = value.remainder(period);
  return r < 0 ? r + period : r;
}

/// 把弧度 [rad] 转为角度，保留符号且不归一化。
///
/// 例如 `luckyRadToDeg(math.pi)` 返回 180。
double luckyRadToDeg(double rad) => rad * kLuckyHalfTurnDeg / math.pi;
