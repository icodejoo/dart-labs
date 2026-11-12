import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// 选奖上下文；权重与禁用列表须等长，调用期间不可修改。
///
/// 例如 `PrizePickContext(weights: [1], disabled: [false], random: random)`。
@immutable
final class PrizePickContext {
  /// 创建上下文，随机源由调用方注入。
  const PrizePickContext(
      {required this.weights, required this.disabled, required this.random});

  /// 奖品权重；null、NaN、非正值不可选。
  final List<double?> weights;

  /// 每个奖品的禁用标记。
  final List<bool> disabled;

  /// 可复现的随机源。
  final math.Random random;
}

/// 选奖策略，返回 null 表示作废本局。
abstract interface class PrizePicker {
  /// 从 [context] 返回零基奖品下标，或 null 表示取消。
  int? pick(PrizePickContext context);
}

/// 上游累计权重选奖；例如 `const WeightedPrizePicker()`。
final class WeightedPrizePicker implements PrizePicker {
  /// 创建；[honorDisabled] 默认排除被禁用奖品。
  const WeightedPrizePicker({this.honorDisabled = true});

  /// 是否排除禁用奖品。
  final bool honorDisabled;

  /// 返回累计权重命中的首个下标；总权重为零时仍消耗一次随机数。
  @override
  int? pick(PrizePickContext context) {
    // 上游 index.ts:132-147；累计与 <= 比较顺序不变。
    final n = context.weights.length;
    final ascending = List<double>.filled(n, double.nan);
    var sum = 0.0;
    for (var i = 0; i < n; i++) {
      final w = context.disabled[i] && honorDisabled
          ? double.nan
          : context.weights[i] ?? double.nan;
      if (w > 0) {
        sum = sum + w;
        ascending[i] = sum;
      }
    }
    final r = context.random.nextDouble() * sum;
    for (var i = 0; i < n; i++) {
      if (r <= ascending[i]) return i;
    }
    return null;
  }
}

/// 连续未命中达到阈值后强制命中指定奖品，强制时不消耗随机数。
///
/// `stop(index)` 的服务端选奖不经过 picker，不更新计数。
/// 例如 `GuaranteedPrizePicker(inner: const WeightedPrizePicker(), guaranteedIndex: 0, afterMisses: 5)`。
final class GuaranteedPrizePicker implements PrizePicker {
  /// 创建独立计数策略；[guaranteedIndex] 和 [afterMisses] 应为非负数。
  GuaranteedPrizePicker(
      {required this.inner,
      required this.guaranteedIndex,
      required this.afterMisses});

  /// 未触发保底时使用的策略。
  final PrizePicker inner;

  /// 强制命中的下标。
  final int guaranteedIndex;

  /// 允许连续未命中的次数。
  final int afterMisses;

  /// 当前连续未命中计数。
  int get misses => _misses;

  /// 实例内计数。
  int _misses = 0;

  /// 清除计数，例如新活动开始时调用。
  void resetMisses() => _misses = 0;

  /// 返回内部策略或强制结果，命中保底奖品后清零计数；null 也计为未命中。
  @override
  int? pick(PrizePickContext context) {
    final index =
        _misses >= afterMisses ? guaranteedIndex : inner.pick(context);
    if (index == guaranteedIndex) {
      _misses = 0;
    } else {
      _misses++;
    }
    return index;
  }
}
