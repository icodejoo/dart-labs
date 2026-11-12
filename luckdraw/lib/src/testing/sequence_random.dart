import 'dart:math' as math;

/// 重放确定性小数序列；例如 `SequenceRandom([0.1, 0.7])`。
final class SequenceRandom implements math.Random {
  /// 创建序列；每个值必须在 [0, 1) 内，耗尽抛出 StateError。
  SequenceRandom(List<double> values) : _values = List.unmodifiable(values) {
    if (_values.any((value) => !value.isFinite || value < 0 || value >= 1)) {
      throw ArgumentError.value(values, 'values', '必须在 [0, 1) 内');
    }
  }

  /// 待回放的不可变小数。
  final List<double> _values;

  /// 下次读取位置。
  int _index = 0;

  /// 返回下一个小数，耗尽时抛错。
  @override
  double nextDouble() {
    if (_index >= _values.length) throw StateError('随机序列已耗尽');
    return _values[_index++];
  }

  /// 消耗一个小数，返回 [0, max) 的整数；max 必须为正。
  @override
  int nextInt(int max) {
    if (max <= 0) throw ArgumentError.value(max, 'max', '必须为正');
    return (nextDouble() * max).floor();
  }

  /// 消耗一个小数，小于一半时返回 true。
  @override
  bool nextBool() => nextDouble() < 0.5;
}
