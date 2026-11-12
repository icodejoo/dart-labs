import 'package:flutter/foundation.dart';

import '../../core/foundation/constants.dart';
import '../model/wheel_config.dart';

/// 非法权重错误对应的配置字段名。
const String _sectorWeightField = 'sectorWeight';

/// 由配置计算的扇区角度，供布局和停止求解共用。
@immutable
final class WheelSectorAngles {
  /// 保存预计算的角度。
  const WheelSectorAngles._(
      this.count, this.uniform, this.prizeDeg, this._starts, this._sweeps);

  /// 创建角度表；相同权重使用等分公式，非有限或非正权重抛 ArgumentError。
  factory WheelSectorAngles.fromConfig(WheelConfig config) {
    final weights = config.prizes.map((p) => p.sectorWeight).toList();
    if (weights.any((w) => !w.isFinite || w <= 0)) {
      throw ArgumentError.value(weights, _sectorWeightField, '必须为有限正数');
    }
    final count = weights.length;
    final uniform = count == 0 || weights.every((w) => w == weights.first);
    final prizeDeg = count == 0 ? 0.0 : kLuckyFullTurnDeg / count;
    final starts = <double>[];
    final sweeps = <double>[];
    if (!uniform) {
      final sum = weights.fold(0.0, (a, b) => a + b);
      if (!sum.isFinite) {
        throw ArgumentError.value(sum, _sectorWeightField, '总和必须有限');
      }
      var start = 0.0;
      for (final weight in weights) {
        final sweep = (weight / sum) * kLuckyFullTurnDeg;
        starts.add(start);
        sweeps.add(sweep);
        start += sweep;
      }
    }
    return WheelSectorAngles._(count, uniform, prizeDeg,
        List.unmodifiable(starts), List.unmodifiable(sweeps));
  }

  /// 扇区数。
  final int count;

  /// 是否等分。
  final bool uniform;

  /// 等分角宽；无奖品时为零。
  final double prizeDeg;

  /// 不等分起始角。
  final List<double> _starts;

  /// 不等分角宽。
  final List<double> _sweeps;

  /// 返回第 [i] 个扇区的起始角，单位为度。
  double startDeg(int i) => uniform ? i * prizeDeg : _starts[i];

  /// 返回第 [i] 个扇区的角宽，单位为度。
  double sweepDeg(int i) => uniform ? prizeDeg : _sweeps[i];

  /// 反算指针下的奖品；无奖品或非有限角度返回 −1。
  int sectorAtPointer(double rotateDeg, double offsetDegree) {
    if (count == 0 || !rotateDeg.isFinite || !offsetDegree.isFinite) return -1;
    var a = (-(rotateDeg + offsetDegree)).remainder(kLuckyFullTurnDeg);
    if (a < 0) a += kLuckyFullTurnDeg;
    for (var i = 0; i < count; i++) {
      if (startDeg(i) <= a && a < startDeg(i) + sweepDeg(i)) return i;
    }
    // 累加误差可能使最后一个区间终点略小于 360。
    return count - 1;
  }
}
