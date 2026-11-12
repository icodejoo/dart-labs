import 'package:flutter/widgets.dart';

import '../../core/render/renderer.dart';
import '../../core/widgets/game_view.dart';
import '../layout/slot_layout.dart';
import '../model/slot_config.dart';
import '../model/slot_result.dart';
import '../motion/slot_motion.dart';
import '../render/slot_canvas_renderer.dart';
import '../slot_game.dart';

/// 受控老虎机；通过外部 SlotController 调用 play、stopEach。
class LuckySlotMachine
    extends LuckyGameView<SlotConfig, SlotLayout, SlotFrame, SlotResult> {
  /// 创建老虎机；无外部控制器时由宿主创建并释放。
  const LuckySlotMachine(
      {super.key,
      required super.config,
      super.controller,
      super.renderer,
      this.overlayBuilder,
      super.width,
      super.height,
      super.alignment,
      super.onEnd,
      super.onPhaseChanged,
      void Function(int reel, int prizeIndex)? onCellPassed,
      super.onImageError,
      super.onReady,
      super.hooks,
      super.layers,
      super.performance,
      super.textScaling,
      super.semanticsLabel,
      super.semanticsValueBuilder})
      : super(game: const SlotGame(), onItemPassed: onCellPassed);

  /// 在表面上构建可选奖品 Widget 层，使用 data 中已应用的布局和帧通知。
  ///
  /// 例如返回 LuckyItemOverlay，geometry 为 const SlotGame().itemGeometry；
  /// children 按该几何约定重复各轮的条带奖品，窗口裁剪由几何自动提供。
  /// 仅在需要 Widget 内容（如 GIF）时使用，有额外成本；叠加层忽略指针。
  final Widget Function(BuildContext context,
      LuckySurfaceData<SlotConfig, SlotLayout, SlotFrame> data)? overlayBuilder;

  /// 保留既有后端，并按需组合 Widget 叠加层。
  @override
  LuckyRenderer<SlotConfig, SlotLayout, SlotFrame, SlotResult>? get renderer =>
      overlayBuilder == null
          ? super.renderer
          : _SlotOverlayRenderer(
              super.renderer ?? const SlotCanvasRenderer(), overlayBuilder!);
}

/// 组合老虎机表面与额外奖品 Widget。
final class _SlotOverlayRenderer
    extends LuckyRenderer<SlotConfig, SlotLayout, SlotFrame, SlotResult> {
  /// 保存已有后端及构建回调。
  const _SlotOverlayRenderer(this.renderer, this.builder);

  /// 已有的老虎机后端。
  final LuckyRenderer<SlotConfig, SlotLayout, SlotFrame, SlotResult> renderer;

  /// 低频布局构建回调。
  final Widget Function(
          BuildContext, LuckySurfaceData<SlotConfig, SlotLayout, SlotFrame>)
      builder;

  /// 使用宿主的同一份输入构建叠加层。
  @override
  Widget buildSurface(BuildContext context,
          LuckySurfaceData<SlotConfig, SlotLayout, SlotFrame> data) =>
      Stack(fit: StackFit.expand, children: [
        renderer.buildSurface(context, data),
        IgnorePointer(child: builder(context, data)),
      ]);
}
