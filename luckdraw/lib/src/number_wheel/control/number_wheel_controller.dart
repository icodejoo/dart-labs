import 'dart:async';

import '../../core/control/motion_controller.dart';
import '../../core/motion/phase.dart';
import '../../core/motion/result.dart';
import '../../core/picker/pick_index.dart';
import '../layout/number_wheel_layout.dart';
import '../model/number_wheel_config.dart';
import '../motion/number_wheel_motion.dart';

/// 数字转盘控制器；外部创建时由调用者负责 dispose。
class NumberWheelController extends LuckyMotionController<
    NumberWheelConfig,
    NumberWheelLayout,
    NumberWheelFrame,
    LuckyResult<NumberWheelPocket>,
    NumberWheelMotion> {
  /// 创建控制器，可注入选奖策略与随机源。
  NumberWheelController({super.picker, super.random})
      : super(motion: NumberWheelMotion());

  /// 类型化运动状态机。
  NumberWheelMotion get _motion => typedMotion;

  /// 最近一次正常结果号码；尚无结果或取消时为空。
  int? get lastNumber => lastResult?.prize?.number;

  /// 按下标停止；null 使用 picker，负数取消，越界按号码数取余。
  /// 例如 `controller.stop(3)`；加速与匀速之外返回 false。
  bool stop([int? index]) {
    if (!phase.value.canStop) {
      return false;
    }
    final pockets = _motion.config.pockets;
    final target = index ??
        pickIndex(picker, random, pockets,
            weight: (p) => p.weight, disabled: (p) => p.disabled);
    return commitCommand(_motion.stop(target ?? -1));
  }

  /// 按号码停止；未知号码抛出 ArgumentError，重复号码使用第一个格子。
  bool stopNumber(int number) {
    final index = _motion.config.pockets.indexWhere((p) => p.number == number);
    if (index < 0) throw ArgumentError.value(number, 'number', '号码不存在');
    return stop(index);
  }

  /// 开始并异步等待号码；null 作废本局，最短时长按有效时间计算。
  Future<LuckyResult<NumberWheelPocket>> playUntil(
          FutureOr<int?> Function() resolveNumber,
          {Duration minSpinDuration = Duration.zero}) =>
      runPlayUntil(resolveNumber, minSpinDuration,
          (number) => number == null ? cancel() : stopNumber(number));

  /// 创建空奖品的作废结果。
  @override
  LuckyResult<NumberWheelPocket> createCancelledResult() =>
      const LuckyResult.cancelled();
}
