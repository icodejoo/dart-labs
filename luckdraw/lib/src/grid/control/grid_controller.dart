import 'dart:async';

import '../../core/control/controller.dart';
import '../../core/motion/phase.dart';
import '../../core/motion/result.dart';
import '../../core/picker/prize_picker.dart';
import '../layout/grid_layout.dart';
import '../model/grid_config.dart';
import '../model/grid_parts.dart';
import '../motion/grid_motion.dart';

/// 九宫格控制器；例如 `controller.play(); controller.stop(3);`。
class GridController extends LuckyController<GridConfig, GridLayout, GridFrame,
    LuckyResult<GridPrize>> {
  /// 创建独立状态机；可注入选奖策略和随机源。
  GridController({super.picker, super.random}) : super(motion: GridMotion());

  /// 类型化状态机。
  GridMotion get _gridMotion => motion as GridMotion;

  /// 待机尚未开局，其取消结果只用于完成内部等待，不交给 onEnd。
  bool _silenceIdleCancellation = false;

  /// 待机取消不报告结束；正常抽奖取消仍报告作废结果。
  @override
  bool get shouldReportCancelled => !_silenceIdleCancellation;

  /// 作废当前局；待机取消不触发 onEnd，减速中返回 false。
  @override
  bool cancel() => _withCancellationPolicy(super.cancel);

  /// 回到原点；仅真正开局后的取消才触发 onEnd。
  @override
  void reset() => _withCancellationPolicy(super.reset);

  /// 在同步取消命令期间保留起始阶段，完成后立即恢复报告策略。
  T _withCancellationPolicy<T>(T Function() operation) {
    _silenceIdleCancellation = phase.value == LuckyPhase.idleSpinning;
    try {
      return operation();
    } finally {
      _silenceIdleCancellation = false;
    }
  }

  /// 停在 [index]；省略时选奖，负值或选奖为空时作废，返回命令是否接受。
  bool stop([int? index]) => _stopAtSelected(index);

  /// 停在 [index] 并附加完整圈数；圈数为负时按零处理。
  bool stopAt(int index, {int extraLaps = 0}) =>
      commitCommand(_gridMotion.requestStop(index, extraLaps: extraLaps));

  /// 选奖只在接受停止命令的阶段发生。
  bool _stopAtSelected(int? index) {
    if (phase.value != LuckyPhase.accelerating &&
        phase.value != LuckyPhase.cruising) {
      return false;
    }
    final config = _gridMotion.config;
    final selected = index ??
        picker.pick(PrizePickContext(
            weights: [for (final prize in config.prizes) prize.weight],
            disabled: [for (final prize in config.prizes) prize.disabled],
            random: random));
    return commitCommand(_gridMotion.requestStop(selected));
  }

  /// 开始后解析目标，至少等待 [minSpinDuration] 有效时间，再减速到目标。
  ///
  /// 返回本局结果；解析为空时作废，抛错时 Future 保留原错误。
  Future<LuckyResult<GridPrize>> playUntil(
          FutureOr<int?> Function() resolveIndex,
          {Duration minSpinDuration = Duration.zero}) =>
      runPlayUntil(resolveIndex, minSpinDuration,
          (index) => index == null ? cancel() : stop(index));

  /// 创建没有中奖下标和奖品的取消结果。
  @override
  LuckyResult<GridPrize> createCancelledResult() =>
      const LuckyResult.cancelled();
}
