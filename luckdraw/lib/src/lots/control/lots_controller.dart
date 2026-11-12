import 'dart:async';

import '../../core/control/motion_controller.dart';
import '../../core/motion/phase.dart';
import '../../core/motion/result.dart';
import '../../core/picker/pick_index.dart';
import '../layout/lots_layout.dart';
import '../model/lots_config.dart';
import '../model/lots_parts.dart';
import '../motion/lots_motion.dart';

/// 抽签控制器；异步结果与统一阶段由 core 调度。
class LotsController extends LuckyMotionController<LotsConfig, LotsLayout,
    LotsFrame, LuckyResult<LotsStick>, LotsMotion> {
  /// 创建控制器，可注入选奖策略和随机源。
  LotsController({super.picker, super.random}) : super(motion: LotsMotion());

  /// 类型化状态机。
  LotsMotion get _motion => typedMotion;

  /// 请求按下标停止；null 使用 picker、负数取消、越界取余。
  /// 例如 `controller.stop(1)`，加速与匀速之外返回 false。
  bool stop([int? index]) {
    if (!phase.value.canStop) {
      return false;
    }
    final sticks = _motion.config.sticks;
    final target = index ??
        pickIndex(picker, random, sticks,
            weight: (s) => s.weight, disabled: (s) => s.disabled);
    return commitCommand(_motion.stop(target ?? -1));
  }

  /// 开始并等待异步下标；null 作废本局，最短时长按有效时间计算。
  Future<LuckyResult<LotsStick>> playUntil(
          FutureOr<int?> Function() resolveIndex,
          {Duration minSpinDuration = Duration.zero}) =>
      runPlayUntil(resolveIndex, minSpinDuration,
          (index) => index == null ? cancel() : stop(index));

  /// 空奖品的作废结果。
  @override
  LuckyResult<LotsStick> createCancelledResult() =>
      const LuckyResult.cancelled();
}
