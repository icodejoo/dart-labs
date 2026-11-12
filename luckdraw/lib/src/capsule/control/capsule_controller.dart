import 'dart:async';

import '../../core/control/motion_controller.dart';
import '../../core/motion/result.dart';
import '../../core/picker/pick_index.dart';
import '../../core/picker/prize_picker.dart';
import '../layout/capsule_layout.dart';
import '../model/capsule_config.dart';
import '../model/capsule_parts.dart';
import '../motion/capsule_motion.dart';

/// 扭蛋机命令入口；奖品下标与配置 prizes 对应。
class CapsuleController extends LuckyMotionController<CapsuleConfig,
    CapsuleLayout, CapsuleFrame, LuckyResult<CapsulePrize>, CapsuleMotion> {
  /// 创建控制器；可注入选奖策略与可复现随机源。
  CapsuleController({super.picker = const WeightedPrizePicker(), super.random})
      : super(motion: CapsuleMotion());

  /// 停止本局；空下标使用 picker，负值作废，超界正值按奖品数取余。
  ///
  /// 仅加速与匀速接受；例如 `controller.stop(1)`。
  bool stop([int? index]) {
    final capsuleMotion = typedMotion;
    if (!capsuleMotion.acceptsStop) return false;
    final config = capsuleMotion.config;
    final target = index ??
        pickIndex(picker, random, config.prizes,
            weight: (p) => p.weight, disabled: (p) => p.disabled);
    return commitCommand(capsuleMotion.requestStop(target));
  }

  /// 服务端指定奖品下标；语义与 stop(index) 一致。
  bool stopAt(int index) => stop(index);

  /// 开始并等待异步奖品下标，至少搅拌 [minSpinDuration]；空结果作废。
  ///
  /// 返回正常或作废结果；resolveIndex 抛错时作废并传播错误。
  Future<LuckyResult<CapsulePrize>> playUntil(
          FutureOr<int?> Function() resolveIndex,
          {Duration minSpinDuration = Duration.zero}) =>
      runPlayUntil(resolveIndex, minSpinDuration,
          (target) => target == null ? cancel() : stop(target));

  /// 创建无奖品的作废结果。
  @override
  LuckyResult<CapsulePrize> createCancelledResult() =>
      const LuckyResult.cancelled();
}
