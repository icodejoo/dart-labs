import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/foundation/image.dart';
import '../core/game/game.dart';
import '../core/game/layout.dart';
import '../core/geometry/image_box.dart';
import '../core/motion/phase.dart';
import '../core/motion/result.dart';
import '../core/widgets/physics_reduce.dart';
import 'control/capsule_controller.dart';
import 'layout/capsule_layout.dart';
import 'model/capsule_config.dart';
import 'model/capsule_parts.dart';
import 'motion/capsule_motion.dart';
import 'render/capsule_canvas_renderer.dart';

/// 扭蛋机玩法策略；可直接交给 LuckyGameView 或自定义后端。
final class CapsuleGame extends LuckyGame<CapsuleConfig, CapsuleLayout,
    CapsuleFrame, LuckyResult<CapsulePrize>> {
  /// 创建无状态玩法。
  const CapsuleGame();

  /// 计算布局与卡片内容。
  @override
  CapsuleLayout computeLayout(CapsuleConfig config, LuckyLayoutInput input) =>
      computeCapsuleLayout(config, input);

  /// 旋钮为按钮零；结算后托盘胶囊与展开卡片命中奖品。
  @override
  List<LuckyHit> hitTestAll(CapsuleConfig config, CapsuleLayout layout,
      CapsuleFrame frame, Offset position) {
    if (layout.isEmpty) return const [];
    if ((position - layout.knobCenter).distance <= layout.knobRadius) {
      return const [LuckyHit.button(0)];
    }
    if (frame.phase == LuckyPhase.settled &&
        frame.targetPrize >= 0 &&
        ((position - layout.tray.center).distance <= layout.capsuleRadius ||
            frame.revealProgress > 0 && layout.card.contains(position))) {
      return [LuckyHit.item(frame.targetPrize)];
    }
    return const [];
  }

  /// 收集开蛋卡片图片；百分比尺寸以卡片宽高解析。
  @override
  List<LuckyImageRequest> collectImages(
          CapsuleConfig config, CapsuleLayout layout) =>
      [
        for (var i = 0; i < config.prizes.length; i++)
          for (var j = 0; j < config.prizes[i].images.length; j++)
            LuckyImagePlacement.inRect(
                    slot: LuckyImageSlot('prizes', i, j),
                    image: config.prizes[i].images[j],
                    rect: layout.card)
                .toRequest()
      ];

  /// 系统要求减弱动效（或显式 always）时去掉物理参数，回退参数化轨迹。
  @override
  CapsuleConfig resolveConfig(BuildContext context, CapsuleConfig config) {
    final physics = config.options.physics;
    return physics != null && luckyPhysicsReduced(context, physics)
        ? config.copyWith(options: config.options.withoutPhysics())
        : config;
  }

  /// 创建宿主拥有的控制器。
  @override
  CapsuleController createController() => CapsuleController();

  /// 创建默认 Canvas 后端。
  @override
  CapsuleCanvasRenderer createDefaultRenderer() =>
      const CapsuleCanvasRenderer();

  /// 胶囊映射、数量或奖品变化需要延后到结算后应用。
  @override
  bool isStructuralChange(CapsuleConfig oldConfig, CapsuleConfig newConfig) =>
      oldConfig.prizes.length != newConfig.prizes.length ||
      !listEquals(oldConfig.capsules, newConfig.capsules) ||
      oldConfig.capsulesPerPrize != newConfig.capsulesPerPrize;

  /// 默认无障碍标签。
  @override
  String semanticsLabel(CapsuleConfig config) => '扭蛋机';
}
