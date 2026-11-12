import 'dart:async';

import '../../core/control/motion_controller.dart';
import '../../core/motion/phase.dart';
import '../../core/motion/result.dart';
import '../../core/picker/pick_index.dart';
import '../layout/grid_layout.dart';
import '../model/grid_config.dart';
import '../model/grid_parts.dart';
import '../motion/grid_motion.dart';

/// 九宫格控制器；例如 `controller.play(); controller.stop(3);`。
class GridController extends LuckyMotionController<GridConfig, GridLayout,
    GridFrame, LuckyResult<GridPrize>, GridMotion> {
  /// 创建独立状态机；可注入选奖策略和随机源。
  GridController({super.picker, super.random}) : super(motion: GridMotion());

  /// 类型化状态机。
  GridMotion get _gridMotion => typedMotion;

  /// 待机取消不触发 onEnd；正常抽奖取消仍报告作废结果。
  @override
  bool get reportsIdleCancellation => false;

  /// 停在 [index]；省略时选奖，负值或选奖为空时作废，返回命令是否接受。
  bool stop([int? index]) => _stopAtSelected(index);

  /// 停在 [index] 并附加完整圈数；圈数为负时按零处理。
  bool stopAt(int index, {int extraLaps = 0}) =>
      commitCommand(_gridMotion.requestStop(index, extraLaps: extraLaps));

  /// 选奖只在接受停止命令的阶段发生。
  bool _stopAtSelected(int? index) {
    if (!phase.value.canStop) {
      return false;
    }
    final config = _gridMotion.config;
    final selected = index ??
        pickIndex(picker, random, config.prizes,
            weight: (p) => p.weight, disabled: (p) => p.disabled);
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
