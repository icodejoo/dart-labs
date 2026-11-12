import 'dart:async';

import '../../core/control/motion_controller.dart';
import '../../core/motion/phase.dart';
import '../../core/picker/pick_index.dart';
import '../layout/slot_layout.dart';
import '../model/slot_config.dart';
import '../model/slot_result.dart';
import '../motion/slot_motion.dart';

/// 类型化控制器；调用方拥有时须 dispose，可 attachHeadless 注入手动时钟。
class SlotController extends LuckyMotionController<SlotConfig, SlotLayout,
    SlotFrame, SlotResult, SlotMotion> {
  /// 创建独立状态；例如 `SlotController(random: Random(1))`。
  SlotController({super.picker, super.random}) : super(motion: SlotMotion());

  /// 当前老虎机状态机。
  SlotMotion get _slot => typedMotion;

  /// 应用配置，自动识别列顺序等结构变化。
  @override
  void configure(SlotConfig config, SlotLayout? layout,
          {bool structural = false}) =>
      super.configure(config, layout,
          structural: structural || slotStructureChanged(_slot.config, config));

  /// 全部列停到奖品 [index]；null 选奖一次复用到各列，任意负数作废。
  bool stop([int? index]) {
    if (!phase.value.canStop) {
      return false;
    }
    final config = _slot.config;
    final picked = index ??
        pickIndex(picker, random, config.prizes,
            weight: (p) => p.weight, disabled: (p) => p.disabled);
    return commitCommand(_slot.requestStop(
        picked == null ? null : List<int>.filled(config.reels.length, picked)));
  }

  /// 每列停到各自奖品下标；长度不等于列数抛 ArgumentError，状态不变。
  bool stopEach(List<int> indices) => commitCommand(_slot.requestStop(indices));

  /// 开始并等待异步各列目标；null 作废，最短转动时间按有效时间计算。
  Future<SlotResult> playUntil(FutureOr<List<int>?> Function() resolveIndices,
          {Duration minSpinDuration = Duration.zero}) =>
      runPlayUntil(resolveIndices, minSpinDuration,
          (indices) => indices == null ? cancel() : stopEach(indices));

  /// 上游老虎机取消不调用 onEnd。
  @override
  bool get shouldReportCancelled => false;

  /// 为未决异步调用提供作废结果。
  @override
  SlotResult createCancelledResult() => const SlotResult.cancelled();
}
