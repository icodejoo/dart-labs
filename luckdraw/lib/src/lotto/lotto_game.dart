import 'package:flutter/painting.dart';

import '../core/control/controller.dart';
import '../core/foundation/image.dart';
import '../core/game/game.dart';
import '../core/game/layout.dart';
import '../core/render/renderer.dart';
import 'control/lotto_controller.dart';
import 'layout/lotto_layout.dart';
import 'model/lotto_config.dart';
import 'motion/lotto_motion.dart';
import 'render/lotto_canvas_renderer.dart';

/// 大乐透玩法策略；只依赖 core 和本玩法。
final class LottoGame
    extends LuckyGame<LottoConfig, LottoLayout, LottoFrame, LottoResult> {
  /// 创建无状态玩法策略。
  const LottoGame();

  /// 根据配置和环境计算布局。
  @override
  LottoLayout computeLayout(LottoConfig config, LuckyLayoutInput input) =>
      computeLottoLayout(config, input);

  /// 命中开始按钮返回按钮零，其他位置返回空。
  @override
  List<LuckyHit> hitTestAll(LottoConfig config, LottoLayout layout,
          LottoFrame frame, Offset position) =>
      !layout.isEmpty && layout.button.contains(position)
          ? const [LuckyHit.button(0)]
          : const [];

  /// 本玩法纯矢量绘制，不请求外部图片。
  @override
  List<LuckyImageRequest> collectImages(
          LottoConfig config, LottoLayout layout) =>
      const [];

  /// 创建由宿主拥有的默认控制器。
  @override
  LuckyController<LottoConfig, LottoLayout, LottoFrame, LottoResult>
      createController() => LottoController();

  /// 创建 Canvas 后端。
  @override
  LuckyRenderer<LottoConfig, LottoLayout, LottoFrame, LottoResult>
      createDefaultRenderer() => const LottoCanvasRenderer();

  /// 池范围或抽取数量改变时延后减速期间的配置更新。
  @override
  bool isStructuralChange(LottoConfig oldConfig, LottoConfig newConfig) {
    if (oldConfig.pools.length != newConfig.pools.length) return true;
    for (var p = 0; p < oldConfig.pools.length; p++) {
      final a = oldConfig.pools[p];
      final b = newConfig.pools[p];
      if (a.min != b.min || a.max != b.max || a.count != b.count) return true;
    }
    return false;
  }

  /// 默认无障碍名称。
  @override
  String semanticsLabel(LottoConfig config) => '大乐透摇奖机';
}
