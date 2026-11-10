import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../core/foundation/image.dart';
import '../core/game/game.dart';
import '../core/game/layout.dart';
import '../core/motion/phase.dart';
import '../core/motion/result.dart';
import 'control/lots_controller.dart';
import 'layout/lots_layout.dart';
import 'model/lots_config.dart';
import 'model/lots_parts.dart';
import 'motion/lots_motion.dart';
import 'render/lots_canvas_renderer.dart';

/// 签文卡图片分组名。
const String _imageGroup = 'sticks';

/// 抽签玩法策略；传感器触发由应用自行实现。
final class LotsGame extends LuckyGame<LotsConfig, LotsLayout, LotsFrame,
    LuckyResult<LotsStick>> {
  /// 创建无状态策略。
  const LotsGame();

  /// 计算签筒与签槽布局。
  @override
  LotsLayout computeLayout(LotsConfig config, LuckyLayoutInput input) =>
      computeLotsLayout(config, input);

  /// 签筒命中按钮零，结算后的升签或可见卡片命中条目。
  @override
  List<LuckyHit> hitTestAll(
      LotsConfig config, LotsLayout layout, LotsFrame frame, Offset position) {
    if (layout.isEmpty) return const [];
    if (frame.phase == LuckyPhase.settled &&
        frame.targetIndex >= 0 &&
        frame.targetIndex < config.sticks.length &&
        frame.targetSlot >= 0 &&
        frame.targetSlot < layout.sticks.length) {
      final mouth = layout.cylinder.topCenter;
      final angle = -layout.angles[frame.targetSlot];
      final delta = position - mouth;
      final local = mouth +
          Offset(delta.dx * math.cos(angle) - delta.dy * math.sin(angle),
              delta.dx * math.sin(angle) + delta.dy * math.cos(angle));
      if (layout.raisedStick(frame.targetSlot).contains(local) ||
          frame.revealProgress > 0 && layout.card.contains(position)) {
        return [LuckyHit.item(frame.targetIndex)];
      }
    }
    return layout.cylinder.contains(position)
        ? const [LuckyHit.button(0)]
        : const [];
  }

  /// 返回签文卡的图片请求，解码基准为卡片尺寸。
  @override
  List<LuckyImageRequest> collectImages(LotsConfig config, LotsLayout layout) =>
      [
        for (var i = 0; i < config.sticks.length; i++)
          for (var j = 0; j < config.sticks[i].images.length; j++)
            LuckyImageRequest(
                slot: LuckyImageSlot(_imageGroup, i, j),
                image: config.sticks[i].images[j],
                provider: config.sticks[i].images[j].image,
                decodeLogicalWidth: config.sticks[i].images[j].width
                    ?.resolve(layout.card.width),
                decodeLogicalHeight: config.sticks[i].images[j].height
                    ?.resolve(layout.card.height))
      ];

  /// 创建默认控制器。
  @override
  LotsController createController() => LotsController();

  /// 创建 Canvas 默认后端。
  @override
  LotsCanvasRenderer createDefaultRenderer() => const LotsCanvasRenderer();

  /// 签数或可见槽数改变属于结构变化。
  @override
  bool isStructuralChange(LotsConfig oldConfig, LotsConfig newConfig) =>
      oldConfig.sticks.length != newConfig.sticks.length ||
      oldConfig.options.visibleSticks != newConfig.options.visibleSticks;

  /// 默认无障碍标签。
  @override
  String semanticsLabel(LotsConfig config) => '抽签';
}
