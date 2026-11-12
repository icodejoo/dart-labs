import '../../core/widgets/game_view.dart';
import '../control/lotto_controller.dart';
import '../layout/lotto_layout.dart';
import '../lotto_game.dart';
import '../model/lotto_config.dart';
import '../motion/lotto_motion.dart';

/// 受控摇奖机；按钮通过 onStart 通知，调用者决定何时 play 和 stop。
///
/// 例如 `LuckyLotto(config: LottoConfig.superLotto(), controller: controller)`。
class LuckyLotto
    extends LuckyGameView<LottoConfig, LottoLayout, LottoFrame, LottoResult> {
  /// 创建摇奖机；[onBallDrawn] 每个落槽号码触发一次，参数为池下标和号码。
  const LuckyLotto({
    super.key,
    required super.config,
    LottoController? controller,
    super.renderer,
    super.width,
    super.height,
    super.alignment,
    super.onStart,
    super.onButtonTap,
    super.onItemTap,
    super.onEnd,
    super.onPhaseChanged,
    void Function(int pool, int number)? onBallDrawn,
    super.onImageError,
    super.onReady,
    super.hooks,
    super.layers,
    super.performance,
    super.textScaling,
    super.semanticsLabel,
    super.semanticsValueBuilder,
  }) : super(
            game: const LottoGame(),
            controller: controller,
            onItemPassed: onBallDrawn);

  /// 每个落槽号码的回调，参数为池下标与号码。
  void Function(int pool, int number)? get onBallDrawn => onItemPassed;
}
