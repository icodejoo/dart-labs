import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' show Matrix4;

import '../core/foundation/angles.dart';
import '../core/foundation/constants.dart';
import '../core/foundation/image.dart';
import '../core/game/game.dart';
import '../core/game/layout.dart';
import '../core/geometry/image_box.dart';
import '../core/motion/result.dart';
import '../core/widgets/item_overlay.dart';
import 'control/wheel_controller.dart';
import 'layout/wheel_layout.dart';
import 'model/wheel_config.dart';
import 'model/wheel_parts.dart';
import 'motion/wheel_motion.dart';
import 'render/wheel_canvas_renderer.dart';

/// 无状态大转盘策略；例如传给 LuckyGameView 使用自定义宿主。
final class WheelGame extends LuckyGame<WheelConfig, WheelLayout, WheelFrame,
    LuckyResult<WheelPrize>> {
  /// 创建可复用的玩法策略。
  const WheelGame();

  /// 返回奖品几何；盒子顶边中点位于扇区外缘，局部正 y 指向圆心。
  @override
  LuckyItemGeometry<WheelLayout, WheelFrame> get itemGeometry =>
      const _WheelItemGeometry();

  /// 按配置和环境计算零旋转角的布局。
  @override
  WheelLayout computeLayout(WheelConfig config, LuckyLayoutInput input) =>
      computeWheelLayout(config, input);

  /// 返回包含 [position] 的最小半径按钮；边界算命中，无按钮返回空。
  @override
  List<LuckyHit> hitTestAll(WheelConfig config, WheelLayout layout,
      WheelFrame frame, Offset position) {
    final distance = (position - layout.center).distance;
    var index = -1;
    var radius = double.infinity;
    for (var i = 0; i < layout.buttons.length; i++) {
      final current = layout.buttons[i].radius;
      if (current > 0 && distance <= current && current < radius) {
        index = i;
        radius = current;
      }
    }
    return index < 0 ? const [] : [LuckyHit.button(index)];
  }

  /// 收集三组图片；仅为显式指定的宽高提供解码提示，保留自然宽高比。
  @override
  List<LuckyImageRequest> collectImages(
      WheelConfig config, WheelLayout layout) {
    final placements = <LuckyImagePlacement>[
      for (final block in layout.blocks) ...block.images,
      for (final sector in layout.sectors) ...sector.images,
      for (final button in layout.buttons) ...button.images,
    ];
    return [
      for (final placement in placements)
        LuckyImageRequest(
            slot: placement.slot,
            image: placement.image,
            provider: placement.image.image,
            decodeLogicalWidth:
                placement.image.width?.resolve(placement.maxWidth),
            decodeLogicalHeight:
                placement.image.height?.resolve(placement.maxHeight)),
    ];
  }

  /// 创建由宿主负责释放的默认控制器。
  @override
  WheelController createController() => WheelController();

  /// 创建默认 Canvas 后端。
  @override
  WheelCanvasRenderer createDefaultRenderer() => const WheelCanvasRenderer();

  /// 数量、扇区权重或起始角变化会改变停止几何。
  @override
  bool isStructuralChange(WheelConfig oldConfig, WheelConfig newConfig) {
    if (oldConfig.prizes.length != newConfig.prizes.length ||
        oldConfig.options.offsetDegree != newConfig.options.offsetDegree) {
      return true;
    }
    for (var i = 0; i < oldConfig.prizes.length; i++) {
      if (oldConfig.prizes[i].sectorWeight !=
          newConfig.prizes[i].sectorWeight) {
        return true;
      }
    }
    return false;
  }

  /// 返回包含奖品数量的默认无障碍标签。
  @override
  String semanticsLabel(WheelConfig config) =>
      '幸运大转盘，共 ${config.prizes.length} 个奖品';
}

/// 与 Canvas 奖品使用相同的圆心、外缘锚点和旋转顺序。
final class _WheelItemGeometry
    implements LuckyItemGeometry<WheelLayout, WheelFrame> {
  /// 创建无状态几何。
  const _WheelItemGeometry();

  /// 按奖品顺序返回扇区数。
  @override
  int itemCount(WheelLayout layout) => layout.sectors.length;

  /// 使用外缘弦长及外缘到按钮的高度。
  @override
  Size itemSize(WheelLayout layout, int index) {
    final sector = layout.sectors[index];
    return Size(sector.shortSide, sector.prizeHeight.clamp(0, double.infinity));
  }

  /// 把 Widget 顶边中点放到外缘中点，并叠加本帧转盘旋转。
  @override
  bool transformFor(
      WheelLayout layout, WheelFrame frame, int index, Matrix4 out) {
    if (layout.isEmpty) return false;
    final sector = layout.sectors[index];
    out
      ..setIdentity()
      // ignore: deprecated_member_use
      ..translate(layout.center.dx, layout.center.dy)
      ..rotateZ(luckyDegToRad(frame.rotateDeg))
      // ignore: deprecated_member_use
      ..translate(sector.anchor.dx, sector.anchor.dy)
      ..rotateZ(sector.localRotation)
      // ignore: deprecated_member_use
      ..translate(-sector.shortSide / kLuckyHalfDivisor, 0.0);
    return true;
  }
}
