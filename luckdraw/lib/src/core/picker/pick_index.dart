import 'dart:math' as math;

import 'prize_picker.dart';

/// 用 [picker] 从 [items] 中选出下标；权重与禁用状态由访问器按元素读取。
///
/// 返回 null 表示策略要求作废。例如
/// `pickIndex(picker, random, prizes, weight: (p) => p.weight, disabled: (p) => p.disabled)`。
int? pickIndex<T>(PrizePicker picker, math.Random random, Iterable<T> items,
        {required double? Function(T item) weight,
        required bool Function(T item) disabled}) =>
    picker.pick(PrizePickContext(
        weights: [for (final item in items) weight(item)],
        disabled: [for (final item in items) disabled(item)],
        random: random));
