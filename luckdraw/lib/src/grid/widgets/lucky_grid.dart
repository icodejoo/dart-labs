import 'package:flutter/widgets.dart';
import '../../core/control/hooks.dart';
import '../../core/foundation/image.dart';
import '../../core/foundation/options.dart';
import '../../core/motion/phase.dart';
import '../../core/motion/result.dart';
import '../../core/render/layer.dart';
import '../../core/render/renderer.dart';
import '../../core/widgets/game_view.dart';
import '../control/grid_controller.dart';
import '../grid_game.dart';
import '../layout/grid_layout.dart';
import '../model/grid_config.dart';
import '../model/grid_parts.dart';
import '../motion/grid_motion.dart';
import '../render/grid_canvas_renderer.dart';

/// 九宫格抽奖 Widget；例如 `LuckyGrid(config: config, width: 300, height: 300)`。
final class LuckyGrid extends StatelessWidget {
  /// 创建九宫格；点击按钮通过 onStart 交给调用方决定何时开始。
  const LuckyGrid(
      {super.key,
      required this.config,
      this.controller,
      this.width,
      this.height,
      this.alignment = Alignment.topLeft,
      this.onStart,
      this.onButtonTap,
      this.onCellTap,
      this.onEnd,
      this.onPhaseChanged,
      this.onActiveChanged,
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

  /// 九宫格不可变配置。
  final GridConfig config;

  /// 外部控制器，由调用方释放；未提供时宿主创建。
  final GridController? controller;

  /// 逻辑宽度；未指定时父约束须有界。
  final double? width;

  /// 逻辑高度；未指定时父约束须有界。
  final double? height;

  /// 非正方形容器对齐。
  final AlignmentGeometry alignment;

  /// 可开始阶段点击按钮时调用，不自动开始。
  final VoidCallback? onStart;

  /// 所有阶段点击按钮时调用，携带按钮下标与阶段。
  final LuckyButtonTapCallback? onButtonTap;

  /// 点击奖品格时调用。
  final ValueChanged<int>? onCellTap;

  /// 正常或取消结束时调用。
  final ValueChanged<LuckyResult<GridPrize>>? onEnd;

  /// 运动阶段变化时调用。
  final ValueChanged<LuckyPhase>? onPhaseChanged;

  /// 高亮奖品下标变化时调用。
  final ValueChanged<int>? onActiveChanged;

  /// 图片请求失败时调用。
  final ValueChanged<LuckyImageError>? onImageError;

  /// 所有图片请求均有结论时调用。
  final VoidCallback? onReady;

  /// 初始化、绘制及尺寸钩子。
  final LuckyHooks hooks;

  /// 插入指定绘制位置的扩展层。
  final List<LuckyLayer<GridLayout, GridFrame>> layers;

  /// 可替换渲染后端；null 使用 Canvas。
  final LuckyRenderer<GridConfig, GridLayout, GridFrame,
      LuckyResult<GridPrize>>? renderer;

  /// 在渲染表面上构建可选奖品 Widget 层；data 提供已应用的布局、帧及通知器。
  ///
  /// 例如返回 LuckyItemOverlay(geometry: const GridGame().itemGeometry,
  /// layout: data.layout, frame: data.frame,
  /// frameListenable: data.frameListenable, children: children)。
  /// 仅在需要 Widget 内容（如 GIF）时使用，有额外成本；叠加层忽略指针。
  final Widget Function(BuildContext context,
      LuckySurfaceData<GridConfig, GridLayout, GridFrame> data)? overlayBuilder;

  /// 缓存、采样及隐藏暂停策略。
  final LuckyPerformanceOptions performance;

  /// 是否跟随系统文字缩放。
  final LuckyTextScaling textScaling;

  /// 无障碍标签；null 使用奖品数量描述。
  final String? semanticsLabel;

  /// 阶段和结果的无障碍描述。
  final String Function(LuckyPhase, LuckyResult<GridPrize>?)?
      semanticsValueBuilder;

  /// 使用通用宿主提供时间源、图片和语义。
  @override
  Widget build(BuildContext context) =>
      LuckyGameView<GridConfig, GridLayout, GridFrame, LuckyResult<GridPrize>>(
          game: const GridGame(),
          config: config,
          controller: controller,
          width: width,
          height: height,
          alignment: alignment,
          onStart: onStart,
          onButtonTap: onButtonTap,
          onEnd: onEnd,
          onPhaseChanged: onPhaseChanged,
          onImageError: onImageError,
          onReady: onReady,
          hooks: hooks,
          layers: layers,
          renderer: overlayBuilder == null
              ? renderer
              : _GridOverlayRenderer(
                  renderer ?? const GridCanvasRenderer(), overlayBuilder!),
          performance: performance,
          textScaling: textScaling,
          semanticsLabel: semanticsLabel,
          semanticsValueBuilder: semanticsValueBuilder,
          onItemTap: onCellTap,
          onItemPassed: (_, index) => onActiveChanged?.call(index));
}

/// 组合已有后端与可选 Widget 层，复用宿主提供的布局和可变帧。
final class _GridOverlayRenderer extends LuckyRenderer<GridConfig, GridLayout,
    GridFrame, LuckyResult<GridPrize>> {
  /// 保存已有后端和低频构建回调。
  const _GridOverlayRenderer(this.renderer, this.builder);

  /// 实际绘制玩法的后端。
  final LuckyRenderer<GridConfig, GridLayout, GridFrame, LuckyResult<GridPrize>>
      renderer;

  /// 低频布局构建回调。
  final Widget Function(
          BuildContext, LuckySurfaceData<GridConfig, GridLayout, GridFrame>)
      builder;

  /// 在同一个已布局的表面上叠放奖品 Widget。
  @override
  Widget buildSurface(BuildContext context,
          LuckySurfaceData<GridConfig, GridLayout, GridFrame> data) =>
      Stack(fit: StackFit.expand, children: [
        renderer.buildSurface(context, data),
        IgnorePointer(child: builder(context, data)),
      ]);
}
