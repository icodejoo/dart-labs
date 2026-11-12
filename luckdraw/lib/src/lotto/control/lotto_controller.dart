import 'dart:async';

import '../../core/control/motion_controller.dart';
import '../../core/motion/phase.dart';
import '../layout/lotto_layout.dart';
import '../model/lotto_config.dart';
import '../model/lotto_sampler.dart';
import '../motion/lotto_motion.dart';

/// 摇奖控制器；例如 `LottoController(random: Random(42))` 可复现选号。
class LottoController extends LuckyMotionController<LottoConfig, LottoLayout,
    LottoFrame, LottoResult, LottoMotion> {
  /// 创建控制器；不传随机源时使用独立 Random。
  LottoController({this.sampler = const UniformLottoSampler(), super.random})
      : super(motion: LottoMotion());

  /// 未指定号码时使用的无放回抽样策略。
  final LottoSampler sampler;

  /// 当前状态机的类型化视图。
  LottoMotion get _lotto => typedMotion;

  /// 应用或排队配置；减速中的结构变化由 core 延后应用。
  @override
  void configure(LottoConfig config, LottoLayout? layout,
      {bool structural = false}) {
    config.validate();
    super.configure(config, layout, structural: structural);
  }

  /// 抽样开奖；仅加速或匀速阶段接受，抽样为 null 时作废。
  bool stop() {
    if (!phase.value.canStop) {
      return false;
    }
    final draw = sampler.sample(_lotto.config!, random);
    return draw == null ? cancel() : stopWith(draw);
  }

  /// 按指定号码开奖；数量、范围或唯一性不符抛 ArgumentError。
  bool stopWith(LottoDraw draw) => commitCommand(_lotto.stopWith(draw));

  /// 等待服务端号码及最短有效转动时间，null 作废，返回本局最终结果。
  Future<LottoResult> playUntil(FutureOr<LottoDraw?> Function() resolveDraw,
          {Duration minSpinDuration = Duration.zero}) =>
      runPlayUntil(resolveDraw, minSpinDuration,
          (draw) => draw == null ? cancel() : stopWith(draw));

  /// 创建取消结果，供 reset、detach 和 dispose 完成未决调用。
  @override
  LottoResult createCancelledResult() => const LottoResult.cancelled();
}
