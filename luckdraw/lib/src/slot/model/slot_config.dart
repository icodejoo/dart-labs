import 'package:flutter/foundation.dart';

import '../../core/foundation/box_block.dart';
import 'payline.dart';
import 'slot_parts.dart';

/// 从各列目标奖品下标及配置返回中奖下标，或 null 表示未中奖。
typedef SlotWinPredicate = int? Function(List<int> indices, SlotConfig config);

/// 各列下标相同、有效且存在于各自 order 时返回该下标。
int? upstreamSlotWinPredicate(List<int> indices, SlotConfig config) {
  if (indices.isEmpty || indices.length != config.reels.length) return null;
  final first = indices.first;
  if (first < 0 || first >= config.prizes.length) return null;
  for (var r = 0; r < indices.length; r++) {
    if (indices[r] != first ||
        !(config.reels[r].order?.contains(first) ?? true)) {
      return null;
    }
  }
  return first;
}

/// 不可变老虎机配置；列表由调用方保持不可变。
@immutable
final class SlotConfig {
  /// 创建配置；例如 `SlotConfig(prizes: prizes, reels: reels)`。
  const SlotConfig(
      {this.blocks = const [],
      this.prizes = const [],
      this.reels = const [],
      this.options = const SlotOptions(),
      this.style = const SlotStyle(),
      this.winPredicate = upstreamSlotWinPredicate,
      this.paylines = const [],
      this.paylinePredicate = allEqualPaylinePredicate});

  /// 从外到内的装饰块。
  final List<LuckyBoxBlock> blocks;

  /// 奖品表。
  final List<SlotPrize> prizes;

  /// 各列配置。
  final List<SlotReel> reels;

  /// 行为参数。
  final SlotOptions options;

  /// 默认样式。
  final SlotStyle style;

  /// 结束时的中奖判定。
  final SlotWinPredicate winPredicate;

  /// 赔付线定义；逻辑由拉霸机任务补齐。
  final List<SlotPayline> paylines;

  /// 赔付线中奖判定。
  final SlotPaylinePredicate paylinePredicate;

  /// 返回仅替换非 null 参数的副本；例如 `value.copyWith()` 保留全部配置。
  SlotConfig copyWith(
          {List<LuckyBoxBlock>? blocks,
          List<SlotPrize>? prizes,
          List<SlotReel>? reels,
          SlotOptions? options,
          SlotStyle? style,
          SlotWinPredicate? winPredicate,
          List<SlotPayline>? paylines,
          SlotPaylinePredicate? paylinePredicate}) =>
      SlotConfig(
          blocks: blocks ?? this.blocks,
          prizes: prizes ?? this.prizes,
          reels: reels ?? this.reels,
          options: options ?? this.options,
          style: style ?? this.style,
          winPredicate: winPredicate ?? this.winPredicate,
          paylines: paylines ?? this.paylines,
          paylinePredicate: paylinePredicate ?? this.paylinePredicate);

  /// 按字段值比较配置，列表按内容比较。
  @override
  bool operator ==(Object other) =>
      other is SlotConfig &&
      listEquals(blocks, other.blocks) &&
      listEquals(prizes, other.prizes) &&
      listEquals(reels, other.reels) &&
      options == other.options &&
      style == other.style &&
      winPredicate == other.winPredicate &&
      listEquals(paylines, other.paylines) &&
      paylinePredicate == other.paylinePredicate;

  /// 与字段值相等性一致的哈希值。
  @override
  int get hashCode => Object.hash(
      Object.hashAll(blocks),
      Object.hashAll(prizes),
      Object.hashAll(reels),
      options,
      style,
      winPredicate,
      Object.hashAll(paylines),
      paylinePredicate);
}
