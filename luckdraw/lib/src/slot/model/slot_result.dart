import 'package:flutter/foundation.dart';

import '../../core/motion/result.dart';
import 'slot_parts.dart';

/// 一局各列目标和中奖奖品；indices 为奖品下标而非条带位置。
@immutable
final class SlotResult extends LuckyResult<SlotPrize> {
  /// 创建正常结果；未中奖时 index 和 prize 为空。
  const SlotResult(
      {required this.indices,
      super.index,
      super.prize,
      super.cancelled,
      this.winningPaylines = const []});

  /// 创建作废结果；老虎机不向 onEnd 报告作废。
  const SlotResult.cancelled()
      : indices = const [],
        winningPaylines = const [],
        super.cancelled();

  /// 各列的目标奖品下标。
  final List<int> indices;

  /// 中奖赔付线下标。
  final List<int> winningPaylines;
}
