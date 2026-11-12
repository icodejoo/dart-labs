import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../foundation/angles.dart';
import '../foundation/constants.dart';
import '../foundation/unit_range.dart';

/// T5.0 的确定性角速度分散系数。
const double _speedSeed = 0.6180339887;

/// T5.0 的确定性轨道分散系数。
const double _orbitSeed = 0.7548776662;

/// T5.0 的确定性相位分散系数。
const double _phaseSeed = 0.5698402910;

/// T5.0 的轨道起始比例。
const double _orbitBase = 0.25;

/// T5.0 的速度起始值及轨道变化范围。
const double _base = 0.6;

/// T5.0 的速度变化范围。
const double _speedRange = 0.8;

/// T5.0 的向上翻滚比例。
const double _lift = 0.15;

/// 在圆内从底部六边形密排 [count] 个圆，坐标以容器圆心为原点。
///
/// 放不下时等比压缩间距；非正数量返回空列表，物体大于容器时放在原点。
/// 例如 `packCirclesInCircle(count: 3, containerRadius: 50, bodyRadius: 5)`。
List<Offset> packCirclesInCircle(
    {required int count,
    required double containerRadius,
    required double bodyRadius}) {
  if (count <= 0) return const [];
  final limit = math.max(0.0, containerRadius - bodyRadius);
  if (limit == 0 || bodyRadius <= 0) return List.filled(count, Offset.zero);
  final points = <Offset>[];
  var spacing = bodyRadius * kLuckyHalfDivisor;
  while (points.length < count) {
    points.clear();
    final rowHeight = spacing * math.sqrt(3) / kLuckyHalfDivisor;
    var row = 0;
    for (var y = limit; y >= -limit && points.length < count; y -= rowHeight) {
      final halfWidth = math.sqrt(math.max(0, limit * limit - y * y));
      final shift = row.isOdd ? spacing / kLuckyHalfDivisor : 0.0;
      for (var column = ((-halfWidth - shift) / spacing).ceil();
          column * spacing + shift <= halfWidth && points.length < count;
          column++) {
        points.add(Offset(column * spacing + shift, y));
      }
      row++;
    }
    if (points.length < count) {
      // 底部单点网格装不下时先尝试圆环和居中六角网格，再压缩间距。
      if (count > 1 && limit * math.sin(math.pi / count) >= bodyRadius) {
        return List.unmodifiable(List.generate(count, (i) {
          final angle = kLuckyHalfDivisor * math.pi * i / count;
          return Offset(limit * math.sin(angle), limit * math.cos(angle));
        }));
      }
      points.clear();
      final rows = (limit / rowHeight).floor();
      for (var row = rows; row >= -rows && points.length < count; row--) {
        final y = row * rowHeight;
        final halfWidth = math.sqrt(math.max(0, limit * limit - y * y));
        final shift = row.isOdd ? spacing / kLuckyHalfDivisor : 0.0;
        for (var col = ((-halfWidth - shift) / spacing).ceil();
            col * spacing + shift <= halfWidth && points.length < count;
            col++) {
          points.add(Offset(col * spacing + shift, y));
        }
      }
    }
    spacing *= _speedRange;
  }
  return List.unmodifiable(points);
}

/// 将静止位置和搅拌角转换为位置、自转角，输出缓冲区始终复用。
final class LuckySwirlMixer {
  /// 创建运动学实例；[rest] 坐标须在容器内，半径须有限且非负。
  LuckySwirlMixer(
      {required List<Offset> rest,
      required double containerRadius,
      required double bodyRadius})
      : _rest = List.unmodifiable(rest),
        _radius = containerRadius,
        _limit = math.max(0, containerRadius - bodyRadius),
        x = Float64List(rest.length),
        y = Float64List(rest.length),
        angle = Float64List(rest.length) {
    update(0, 0);
  }

  /// 静止坐标副本。
  final List<Offset> _rest;

  /// 容器半径。
  final double _radius;

  /// 物体圆心最大距离。
  final double _limit;

  /// 横坐标缓冲区，长度等于静止位置数。
  final Float64List x;

  /// 纵坐标缓冲区，长度等于静止位置数。
  final Float64List y;

  /// 自转角缓冲区，单位为弧度。
  final Float64List angle;

  /// 更新累计角 [swirlDeg] 和钳制到零至一的强度 [mix]。
  /// [excluded] 为 true 的位置保持原值，列表存在时须与物体数等长。
  void update(double swirlDeg, double mix, {List<bool>? excluded}) {
    final strength = luckyUnit(mix);
    for (var j = 0; j < _rest.length; j++) {
      if (excluded != null && excluded[j]) continue;
      final seed = j + 1;
      final w = _base + _speedRange * (_speedSeed * seed % 1);
      final orbit = (_orbitBase + _base * (_orbitSeed * seed % 1)) * _limit;
      final theta = luckyDegToRad(
          kLuckyFullTurnDeg * (_phaseSeed * seed % 1) + swirlDeg * w);
      var px = _rest[j].dx + (orbit * math.cos(theta) - _rest[j].dx) * strength;
      var py = _rest[j].dy +
          (orbit * math.sin(theta) -
                  _lift *
                      _radius *
                      math.sin(kLuckyHalfDivisor * theta).abs() *
                      strength -
                  _rest[j].dy) *
              strength;
      final distance = math.sqrt(px * px + py * py);
      if (distance > _limit) {
        px *= _limit / distance;
        py *= _limit / distance;
      }
      x[j] = px;
      y[j] = py;
      angle[j] = luckyDegToRad(swirlDeg * w * kLuckyHalfDivisor * strength);
    }
  }
}
