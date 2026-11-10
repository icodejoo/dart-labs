import '../../core/motion/result.dart';
import '../../core/widgets/game_view.dart';
import '../capsule_game.dart';
import '../layout/capsule_layout.dart';
import '../model/capsule_config.dart';
import '../model/capsule_parts.dart';
import '../motion/capsule_motion.dart';

/// 扭蛋机组件；旋钮触发 onStart，由调用者执行 controller.play()。
///
/// 例如 `LuckyCapsuleMachine(config: config, width: 300, height: 500)`；
/// 外部控制器由调用者释放，不内置传感器摇动触发。
class LuckyCapsuleMachine extends LuckyGameView<CapsuleConfig, CapsuleLayout,
    CapsuleFrame, LuckyResult<CapsulePrize>> {
  /// 创建扭蛋机；参数契约与 LuckyGameView 一致。
  const LuckyCapsuleMachine(
      {super.key,
      required super.config,
      super.controller,
      super.renderer,
      super.width,
      super.height,
      super.alignment,
      super.onStart,
      super.onButtonTap,
      super.onItemTap,
      super.onEnd,
      super.onPhaseChanged,
      super.onImageError,
      super.onReady,
      super.hooks,
      super.layers,
      super.performance,
      super.textScaling,
      super.semanticsLabel,
      super.semanticsValueBuilder})
      : super(game: const CapsuleGame());
}
