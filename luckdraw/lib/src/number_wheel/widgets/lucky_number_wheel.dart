import 'package:flutter/widgets.dart';

import '../../core/control/hooks.dart';
import '../../core/foundation/image.dart';
import '../../core/foundation/options.dart';
import '../../core/motion/phase.dart';
import '../../core/motion/result.dart';
import '../../core/render/layer.dart';
import '../../core/render/renderer.dart';
import '../../core/widgets/game_view.dart';
import '../control/number_wheel_controller.dart';
import '../layout/number_wheel_layout.dart';
import '../model/number_wheel_config.dart';
import '../motion/number_wheel_motion.dart';
import '../number_wheel_game.dart';

/// NumberWheel 受控组件；外部控制器归调用者所有。
class LuckyNumberWheel extends StatelessWidget {
  /// 创建组件；宽高为空时使用有界父约束，点按开始只通知回调。
  const LuckyNumberWheel(
      {super.key,
      required this.config,
      this.controller,
      this.renderer,
      this.width,
      this.height,
      this.alignment = Alignment.topLeft,
      this.onStart,
      this.onButtonTap,
      this.onItemTap,
      this.onEnd,
      this.onPhaseChanged,
      this.onPocketPassed,
      this.onImageError,
      this.onReady,
      this.hooks = const LuckyHooks(),
      this.layers = const [],
      this.performance = const LuckyPerformanceOptions(),
      this.textScaling = LuckyTextScaling.none,
      this.semanticsLabel,
      this.semanticsValueBuilder});

  /// 不可变配置。
  final NumberWheelConfig config;

  /// 可选外部控制器。
  final NumberWheelController? controller;

  /// 可替换渲染后端。
  final LuckyRenderer<NumberWheelConfig, NumberWheelLayout, NumberWheelFrame,
      LuckyResult<NumberWheelPocket>>? renderer;

  /// 逻辑宽度。
  final double? width;

  /// 逻辑高度。
  final double? height;

  /// 非正方形容器中的对齐。
  final AlignmentGeometry alignment;

  /// 允许开始时点击按钮触发，不自动 play。
  final VoidCallback? onStart;

  /// 任意阶段按钮点击。
  final LuckyButtonTapCallback? onButtonTap;

  /// 已展示条目点击。
  final ValueChanged<int>? onItemTap;

  /// 正常结束或取消结果。
  final ValueChanged<LuckyResult<NumberWheelPocket>>? onEnd;

  /// 运动阶段变化。
  final ValueChanged<LuckyPhase>? onPhaseChanged;

  /// 小球跨过格子时通知下标。
  final ValueChanged<int>? onPocketPassed;

  /// 图片请求失败通知。
  final ValueChanged<LuckyImageError>? onImageError;

  /// 全部图片已有结论时通知。
  final VoidCallback? onReady;

  /// 生命周期及绘制钩子。
  final LuckyHooks hooks;

  /// 自定义绘制层。
  final List<LuckyLayer<NumberWheelLayout, NumberWheelFrame>> layers;

  /// 性能策略。
  final LuckyPerformanceOptions performance;

  /// 文字缩放策略。
  final LuckyTextScaling textScaling;

  /// 无障碍标签。
  final String? semanticsLabel;

  /// 无障碍阶段和结果描述。
  final String Function(
          LuckyPhase phase, LuckyResult<NumberWheelPocket>? result)?
      semanticsValueBuilder;

  /// 组合通用宿主并转发类型化回调。
  @override
  Widget build(BuildContext context) => LuckyGameView<NumberWheelConfig,
          NumberWheelLayout, NumberWheelFrame, LuckyResult<NumberWheelPocket>>(
      game: const NumberWheelGame(),
      config: config,
      controller: controller,
      renderer: renderer,
      width: width,
      height: height,
      alignment: alignment,
      onStart: onStart,
      onButtonTap: onButtonTap,
      onItemTap: onItemTap,
      onEnd: onEnd,
      onPhaseChanged: onPhaseChanged,
      onItemPassed:
          onPocketPassed == null ? null : (_, index) => onPocketPassed!(index),
      onImageError: onImageError,
      onReady: onReady,
      hooks: hooks,
      layers: layers,
      performance: performance,
      textScaling: textScaling,
      semanticsLabel: semanticsLabel,
      semanticsValueBuilder: semanticsValueBuilder);
}
