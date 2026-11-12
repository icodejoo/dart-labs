import 'package:flutter/painting.dart';

import '../core/foundation/image.dart';
import '../core/game/game.dart';
import '../core/game/layout.dart';
import '../core/motion/result.dart';
import 'control/number_wheel_controller.dart';
import 'layout/number_wheel_layout.dart';
import 'model/number_wheel_config.dart';
import 'motion/number_wheel_motion.dart';
import 'render/number_wheel_canvas_renderer.dart';

/// 数字转盘玩法 SPI，可独立传给 LuckyGameView。
final class NumberWheelGame extends LuckyGame<NumberWheelConfig,
    NumberWheelLayout, NumberWheelFrame, LuckyResult<NumberWheelPocket>> {
  /// 创建无状态策略。
  const NumberWheelGame();

  /// 计算布局。
  @override
  NumberWheelLayout computeLayout(
          NumberWheelConfig config, LuckyLayoutInput input) =>
      computeNumberWheelLayout(config, input);

  /// 中心毂命中按钮零，空布局无命中。
  @override
  List<LuckyHit> hitTestAll(NumberWheelConfig config, NumberWheelLayout layout,
          NumberWheelFrame frame, Offset position) =>
      !layout.isEmpty && (position - layout.center).distance <= layout.hubRadius
          ? const [LuckyHit.button(0)]
          : const [];

  /// 数字盘不请求图片。
  @override
  List<LuckyImageRequest> collectImages(
          NumberWheelConfig config, NumberWheelLayout layout) =>
      const [];

  /// 创建默认控制器。
  @override
  NumberWheelController createController() => NumberWheelController();

  /// 创建默认 Canvas 渲染器。
  @override
  NumberWheelCanvasRenderer createDefaultRenderer() =>
      const NumberWheelCanvasRenderer();

  /// 格子数或偏移角变化属于影响落点的结构变化。
  @override
  bool isStructuralChange(
          NumberWheelConfig oldConfig, NumberWheelConfig newConfig) =>
      oldConfig.pockets.length != newConfig.pockets.length ||
      oldConfig.options.offsetDegree != newConfig.options.offsetDegree;

  /// 默认无障碍标签。
  @override
  String semanticsLabel(NumberWheelConfig config) => '数字转盘';
}
