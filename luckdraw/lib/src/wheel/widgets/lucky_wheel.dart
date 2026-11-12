import 'package:flutter/widgets.dart';

import '../../core/control/hooks.dart';
import '../../core/foundation/image.dart';
import '../../core/foundation/options.dart';
import '../../core/motion/phase.dart';
import '../../core/motion/result.dart';
import '../../core/render/layer.dart';
import '../../core/render/renderer.dart';
import '../../core/widgets/game_view.dart';
import '../control/wheel_controller.dart';
import '../layout/wheel_layout.dart';
import '../model/wheel_config.dart';
import '../model/wheel_parts.dart';
import '../motion/wheel_motion.dart';
import '../render/wheel_canvas_renderer.dart';
import '../wheel_game.dart';

/// 受控大转盘；例如 `LuckyWheel(config: config, onStart: controller.play)`。
///
/// 未给宽高时父约束必须有界。外部 controller 由调用者释放；点击不自动 play。
class LuckyWheel extends StatelessWidget {
  /// 创建转盘，结构变化在减速期间延后到本局结束应用。
  const LuckyWheel(
      {super.key,
      required this.config,
      this.controller,
      this.width,
      this.height,
      this.alignment = Alignment.topLeft,
      this.onStart,
      this.onButtonTap,
      this.onEnd,
      this.onPhaseChanged,
      this.onSectorPassed,
      this.onImageError,
      this.onReady,
      this.hooks = const LuckyHooks(),
      this.layers = const [],
      this.renderer,
      this.overlayBuilder,
      this.performance = const LuckyPerformanceOptions(),
      this.textScaling = LuckyTextScaling.none,
      this.semanticsLabel,
      this.semanticsValueBuilder});

  /// 不可变转盘配置。
  final WheelConfig config;

  /// 可选外部控制器，未指定时宿主创建并释放。
  final WheelController? controller;

  /// 逻辑宽度，null 时取父约束。
  final double? width;

  /// 逻辑高度，null 时取父约束。
  final double? height;

  /// 转盘在非正方形盒子中的位置。
  final AlignmentGeometry alignment;

  /// 命中按钮且允许开始时触发。
  final VoidCallback? onStart;

  /// 任意阶段命中按钮时触发，提供按钮下标及阶段。
  final LuckyButtonTapCallback? onButtonTap;

  /// 正常结束或作废后返回本局结果。
  final ValueChanged<LuckyResult<WheelPrize>>? onEnd;

  /// 运动阶段变化通知。
  final ValueChanged<LuckyPhase>? onPhaseChanged;

  /// 指针越过扇区时返回下标。
  final ValueChanged<int>? onSectorPassed;

  /// 图片失败通知，不阻塞其它内容呈现。
  final ValueChanged<LuckyImageError>? onImageError;

  /// 全部图片请求成功或失败后触发。
  final VoidCallback? onReady;

  /// 初始化、尺寸和绘制钩子。
  final LuckyHooks hooks;

  /// 按插入位置绘制的用户层。
  final List<LuckyLayer<WheelLayout, WheelFrame>> layers;

  /// 自定义后端，null 使用 WheelCanvasRenderer。
  final LuckyRenderer<WheelConfig, WheelLayout, WheelFrame,
      LuckyResult<WheelPrize>>? renderer;

  /// 在渲染表面上构建可选奖品 Widget 层；data 提供已应用的布局、帧及通知器。
  ///
  /// 例如返回 LuckyItemOverlay(geometry: const WheelGame().itemGeometry,
  /// layout: data.layout, frame: data.frame,
  /// frameListenable: data.frameListenable, children: children)。
  /// 仅在需要 Widget 内容（如 GIF）时使用，有额外成本；叠加层忽略指针。
  final Widget Function(BuildContext context,
          LuckySurfaceData<WheelConfig, WheelLayout, WheelFrame> data)?
      overlayBuilder;

  /// 缓存和采样选项。
  final LuckyPerformanceOptions performance;

  /// 系统文字缩放策略。
  final LuckyTextScaling textScaling;

  /// 默认无障碍标签的覆盖值。
  final String? semanticsLabel;

  /// 可选的阶段和结果播报文本。
  final String Function(LuckyPhase phase, LuckyResult<WheelPrize>? result)?
      semanticsValueBuilder;

  /// 把转盘参数交给通用宿主；帧监听直接连接渲染器。
  @override
  Widget build(BuildContext context) => LuckyGameView<WheelConfig, WheelLayout,
          WheelFrame, LuckyResult<WheelPrize>>(
      game: const WheelGame(),
      config: config,
      controller: controller,
      width: width,
      height: height,
      alignment: alignment,
      onStart: onStart,
      onButtonTap: onButtonTap,
      onEnd: onEnd,
      onPhaseChanged: onPhaseChanged,
      onItemPassed: (_, index) => onSectorPassed?.call(index),
      onImageError: onImageError,
      onReady: onReady,
      hooks: hooks,
      layers: layers,
      renderer: overlayBuilder == null
          ? renderer
          : _WheelOverlayRenderer(
              renderer ?? const WheelCanvasRenderer(), overlayBuilder!),
      performance: performance,
      textScaling: textScaling,
      semanticsLabel: semanticsLabel,
      semanticsValueBuilder: semanticsValueBuilder);
}

/// 组合已有后端与可选 Widget 层，复用宿主提供的布局和可变帧。
final class _WheelOverlayRenderer extends LuckyRenderer<WheelConfig,
    WheelLayout, WheelFrame, LuckyResult<WheelPrize>> {
  /// 保存已有后端和低频构建回调。
  const _WheelOverlayRenderer(this.renderer, this.builder);

  /// 实际绘制玩法的后端。
  final LuckyRenderer<WheelConfig, WheelLayout, WheelFrame,
      LuckyResult<WheelPrize>> renderer;

  /// 低频布局构建回调。
  final Widget Function(
          BuildContext, LuckySurfaceData<WheelConfig, WheelLayout, WheelFrame>)
      builder;

  /// 在同一个已布局的表面上叠放奖品 Widget。
  @override
  Widget buildSurface(BuildContext context,
          LuckySurfaceData<WheelConfig, WheelLayout, WheelFrame> data) =>
      Stack(fit: StackFit.expand, children: [
        renderer.buildSurface(context, data),
        IgnorePointer(child: builder(context, data)),
      ]);
}
