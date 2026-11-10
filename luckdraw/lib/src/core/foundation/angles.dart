import 'dart:math' as math;

import 'constants.dart';

/// 把角度 [deg] 转为弧度，保留符号且不归一化。
///
/// 例如 `luckyDegToRad(180)` 返回 π；运算顺序与上游 getAngle 一致。
double luckyDegToRad(double deg) => math.pi / kLuckyHalfTurnDeg * deg;
