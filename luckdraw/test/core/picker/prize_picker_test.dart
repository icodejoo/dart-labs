import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/luckdraw.dart';

/// 记录调用次数的确定性随机源，测试无需提前引入 T0.6 的 testing API。
final class _Random implements math.Random {
  /// 使用指定序列。
  _Random(this.values);

  /// 循环返回的值。
  final List<double> values;

  /// 消耗的随机次数。
  int calls = 0;

  /// 读取下一个值。
  @override
  double nextDouble() => values[(calls++).remainder(values.length)];

  /// 当前算法不使用布尔随机。
  @override
  bool nextBool() => throw UnsupportedError('只应使用 nextDouble');

  /// 当前算法不使用整数随机。
  @override
  int nextInt(int max) => throw UnsupportedError('只应使用 nextDouble');
}

/// 构造完整上下文，未给出的禁用标记均为 false。
PrizePickContext _context(List<double?> weights, math.Random random,
        {List<bool>? disabled}) =>
    PrizePickContext(
        weights: weights,
        disabled: disabled ?? List.filled(weights.length, false),
        random: random);

/// 验证随机消耗、累计边界与保底计数。
void main() {
  group('WeightedPrizePicker', () {
    test('matches upstream computeRange on a recorded random sequence', () {
      final random = _Random([0, 0.1, 0.100000001, 0.3, 0.300000001, 0.999]);
      final context = _context([1, 2, 7], random);
      const picker = WeightedPrizePicker();
      expect([for (var i = 0; i < 6; i++) picker.pick(context)],
          [0, 0, 1, 1, 2, 2]);
      expect(random.calls, 6);
    });
    test('zero negative and null weights are never picked', () {
      final context = _context([0, -1, null, double.nan, 2], _Random([0, 0.9]));
      expect(const WeightedPrizePicker().pick(context), 4);
      expect(const WeightedPrizePicker().pick(context), 4);
    });
    test('returns null when all weights are absent (upstream -1 cancels)', () {
      final random = _Random([0.5]);
      expect(const WeightedPrizePicker().pick(_context([null, 0, -1], random)),
          isNull);
      expect(const WeightedPrizePicker().pick(_context([], random)), isNull);
      expect(random.calls, 2);
    });
    test('disabled prizes are excluded when honorDisabled is true (IMP-13)',
        () {
      final context = _context([100, 1], _Random([0]), disabled: [true, false]);
      final picker = WeightedPrizePicker(honorDisabled: context.disabled.first);
      expect(picker.pick(context), 1);
      expect(const WeightedPrizePicker(honorDisabled: false).pick(context), 0);
      expect(
          const WeightedPrizePicker()
              .pick(_context([1], _Random([0.5]), disabled: [true])),
          isNull);
    });
    test('uses the injected Random for reproducible picks', () {
      final first = _context([1, 3, 5], math.Random(42));
      final second = _context([1, 3, 5], math.Random(42));
      const picker = WeightedPrizePicker();
      expect([for (var i = 0; i < 100; i++) picker.pick(first)],
          [for (var i = 0; i < 100; i++) picker.pick(second)]);
    });
  });
  group('GuaranteedPrizePicker', () {
    test('forces the guaranteed index after the configured number of misses',
        () {
      final random = _Random([0.9]);
      final context = _context([1, 9], random);
      final picker = GuaranteedPrizePicker(
          inner: const WeightedPrizePicker(),
          guaranteedIndex: 0,
          afterMisses: 2);
      expect(picker.inner, isA<WeightedPrizePicker>());
      expect(picker.pick(context), 1);
      expect(picker.misses, 1);
      expect(picker.pick(context), 1);
      expect(picker.misses, 2);
      expect(picker.pick(context), 0);
      expect(picker.misses, 0);
      expect(random.calls, 2);
      final immediate = GuaranteedPrizePicker(
          inner: const WeightedPrizePicker(),
          guaranteedIndex: 0,
          afterMisses: 0);
      expect(immediate.pick(context), 0);
      expect(random.calls, 2);
    });
    test('resets the miss counter after a hit', () {
      final context = _context([1, 9], _Random([0.9, 0.0, 0.9]));
      final picker = GuaranteedPrizePicker(
          inner: const WeightedPrizePicker(),
          guaranteedIndex: 0,
          afterMisses: 3);
      expect(picker.pick(context), 1);
      expect(picker.pick(context), 0);
      expect(picker.misses, 0);
      expect(picker.pick(context), 1);
      expect(picker.misses, 1);
      picker.resetMisses();
      expect(picker.misses, 0);
      expect(picker.pick(_context([], _Random([0.0]))), isNull);
      expect(picker.misses, 1);
    });
  });
}
