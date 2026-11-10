import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/control/controller.dart';
import '../../core/motion/clock.dart';
import '../../core/motion/phase.dart';
import '../../core/picker/prize_picker.dart';
import '../layout/slot_layout.dart';
import '../model/slot_config.dart';
import '../model/slot_result.dart';
import '../motion/slot_motion.dart';

/// 比较几何结构；减速中的这类变更应排队到结算后。
bool slotStructureChanged(SlotConfig a, SlotConfig b) =>
    a.prizes.length != b.prizes.length ||
    a.reels.length != b.reels.length ||
    a.options.mode != b.options.mode ||
    a.options.rowSpacing != b.options.rowSpacing ||
    a.options.colSpacing != b.options.colSpacing ||
    a.options.cellAspectRatio != b.options.cellAspectRatio ||
    !listEquals(
        a.reels.map((r) => r.order).toList().map((v) => v?.join(',')).toList(),
        b.reels.map((r) => r.order?.join(',')).toList());

/// 类型化控制器；调用方拥有时须 dispose，可 attachHeadless 注入手动时钟。
class SlotController
    extends LuckyController<SlotConfig, SlotLayout, SlotFrame, SlotResult> {
  /// 创建独立状态；例如 `SlotController(random: Random(1))`。
  SlotController({super.picker, super.random}) : super(motion: SlotMotion());

  /// 当前老虎机状态机。
  SlotMotion get _slot => motion as SlotMotion;

  /// 挂接多列事件代理；宿主与时钟所有权不变。
  @override
  void attach(LuckyControllerHost<SlotResult> host) =>
      super.attach(_SlotHost(host, _slot));

  /// 应用配置，自动识别列顺序等结构变化。
  @override
  void configure(SlotConfig config, SlotLayout? layout,
          {bool structural = false}) =>
      super.configure(config, layout,
          structural: structural || slotStructureChanged(_slot.config, config));

  /// 全部列停到奖品 [index]；null 选奖一次复用到各列，任意负数作废。
  bool stop([int? index]) {
    if (phase.value != LuckyPhase.accelerating &&
        phase.value != LuckyPhase.cruising) {
      return false;
    }
    final config = _slot.config;
    final picked = index ??
        picker.pick(PrizePickContext(
            weights: [for (final p in config.prizes) p.weight],
            disabled: [for (final p in config.prizes) p.disabled],
            random: random));
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

/// 在单事件核心协议上派发本帧全部列的跨格事件。
final class _SlotHost implements LuckyControllerHost<SlotResult> {
  /// 包装原宿主和当前状态机。
  _SlotHost(this.host, this.motion);

  /// 原宿主。
  final LuckyControllerHost<SlotResult> host;

  /// 多列状态机。
  final SlotMotion motion;

  /// 原宿主的时钟。
  @override
  LuckyClock get clock => host.clock;

  /// 转交阶段。
  @override
  void handlePhaseChanged(LuckyPhase phase) => host.handlePhaseChanged(phase);

  /// 转交结果。
  @override
  void handleResult(SlotResult result) => host.handleResult(result);

  /// 派发全部列事件。
  @override
  void handleItemPassed(int reel, int index) =>
      motion.dispatchPassed(host.handleItemPassed);

  /// 转交开始事件。
  @override
  void handleStarted() => host.handleStarted();
}
