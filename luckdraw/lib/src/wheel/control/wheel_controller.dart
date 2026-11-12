import 'dart:async';
import 'dart:math' as math;

import '../../core/control/motion_controller.dart';
import '../../core/motion/result.dart';
import '../../core/picker/prize_picker.dart';
import '../layout/wheel_layout.dart';
import '../model/wheel_config.dart';
import '../model/wheel_parts.dart';
import '../motion/wheel_motion.dart';

/// 转盘命令入口，可通过 attachHeadless 注入时钟。
class WheelController extends LuckyMotionController<WheelConfig, WheelLayout,
    WheelFrame, LuckyResult<WheelPrize>, WheelMotion> {
  /// 创建控制器；选奖与停止偏移共用同一 [random] 和 [picker]。
  WheelController(
      {PrizePicker picker = const WeightedPrizePicker(), math.Random? random})
      : this._(picker, random ?? math.Random());

  /// 把同一个策略和随机源交给动画状态机。
  WheelController._(PrizePicker picker, math.Random random)
      : super(
            motion: WheelMotion(random: random, picker: picker),
            picker: picker,
            random: random);

  /// 类型化状态机。
  WheelMotion get _wheelMotion => typedMotion;

  /// 停在 [index]；null 使用 picker，负数作废，大下标按奖品数取余。
  ///
  /// 返回是否接受；只在加速或匀速阶段有效，例如 `controller.stop(3)`。
  bool stop([int? index]) => commitCommand(_wheelMotion.requestStop(index));

  /// 停在 [index]，减速额外增加 [extraRevolutions] 圈；圈数应非负。
  ///
  /// 初始减速速度会随圈数增加，建议同时加大减速时长；返回命令是否接受。
  bool stopAt(int index, {int extraRevolutions = 0}) => commitCommand(
      _wheelMotion.requestStop(index, extraRevolutions: extraRevolutions));

  /// 开始并等待至少 [minSpinDuration] 有效时间后按异步结果停止。
  ///
  /// [resolveIndex] 返回 null 时作废；抛错先作废再传播错误。
  /// 返回正常或作废结果，例如 `await controller.playUntil(() async => 2)`。
  Future<LuckyResult<WheelPrize>> playUntil(
          FutureOr<int?> Function() resolveIndex,
          {Duration minSpinDuration = Duration.zero}) =>
      runPlayUntil(resolveIndex, minSpinDuration, (index) => stop(index ?? -1));

  /// 当前累计旋转角，单位为度。
  double get rotateDeg => frame.rotateDeg;

  /// 供通用 reset、detach 和 dispose 完成未决调用。
  @override
  LuckyResult<WheelPrize> createCancelledResult() =>
      const LuckyResult.cancelled();
}
