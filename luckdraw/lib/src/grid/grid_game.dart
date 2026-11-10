import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' show Matrix4;

import '../core/foundation/image.dart';
import '../core/game/game.dart';
import '../core/game/layout.dart';
import '../core/motion/result.dart';
import '../core/widgets/item_overlay.dart';
import 'control/grid_controller.dart';
import 'layout/grid_layout.dart';
import 'model/grid_config.dart';
import 'model/grid_parts.dart';
import 'motion/grid_motion.dart';
import 'render/grid_canvas_renderer.dart';

/// 九宫格玩法策略；奖品按声明顺序巡游，重叠按钮按声明顺序全部命中。
final class GridGame extends LuckyGame<GridConfig, GridLayout, GridFrame,
    LuckyResult<GridPrize>> {
  /// 创建无状态策略。
  const GridGame();

  /// 返回奖品完整格子矩形；不包含按钮，不随激活态阴影改变尺寸。
  @override
  LuckyItemGeometry<GridLayout, GridFrame> get itemGeometry =>
      const _GridItemGeometry();

  /// 根据配置及环境返回布局。
  @override
  GridLayout computeLayout(GridConfig config, LuckyLayoutInput input) =>
      computeGridLayout(config, input);

  /// 返回命中的全部按钮；没有按钮命中时返回首个命中奖品。
  @override
  List<LuckyHit> hitTestAll(
      GridConfig config, GridLayout layout, GridFrame frame, Offset position) {
    if (layout.isEmpty) return const [];
    final buttons = <LuckyHit>[];
    for (var i = 0; i < config.buttons.length; i++) {
      if (layout.hitRect(config.prizes.length + i).contains(position)) {
        buttons.add(LuckyHit.button(i));
      }
    }
    if (buttons.isNotEmpty) return buttons;
    for (var i = 0; i < config.prizes.length; i++) {
      if (layout.hitRect(i).contains(position)) return [LuckyHit.item(i)];
    }
    return const [];
  }

  /// 收集普通与激活图片；解码尺寸按各状态的收缩区域解析。
  @override
  List<LuckyImageRequest> collectImages(GridConfig config, GridLayout layout) {
    final requests = <LuckyImageRequest>[];
    for (final block in layout.blocks) {
      for (final placement in block.images) {
        requests.add(LuckyImageRequest(
            slot: placement.slot,
            image: placement.image,
            provider: placement.image.image,
            decodeLogicalWidth:
                placement.image.width?.resolve(placement.maxWidth),
            decodeLogicalHeight:
                placement.image.height?.resolve(placement.maxHeight)));
      }
    }
    for (final cell in layout.cells) {
      for (final placement in cell.normal.images) {
        requests.add(LuckyImageRequest(
            slot: placement.slot,
            image: placement.image,
            provider: placement.image.image,
            decodeLogicalWidth:
                placement.image.width?.resolve(placement.maxWidth),
            decodeLogicalHeight:
                placement.image.height?.resolve(placement.maxHeight)));
      }
      if (identical(cell.normal, cell.active)) continue;
      for (final placement in cell.active.images) {
        final image = placement.image as GridImage;
        if (image.activeImage == null) continue;
        requests.add(LuckyImageRequest(
            slot: placement.slot,
            image: image,
            provider: image.activeImage!,
            decodeLogicalWidth: image.width?.resolve(placement.maxWidth),
            decodeLogicalHeight: image.height?.resolve(placement.maxHeight)));
      }
    }
    return requests;
  }

  /// 创建宿主持有的控制器。
  @override
  GridController createController() => GridController();

  /// 创建默认 Canvas 后端。
  @override
  GridCanvasRenderer createDefaultRenderer() => const GridCanvasRenderer();

  /// 奖品数量、行列或任何奖品和按钮的格子坐标变化均属于结构变化。
  @override
  bool isStructuralChange(GridConfig oldConfig, GridConfig newConfig) {
    if (oldConfig.rows != newConfig.rows ||
        oldConfig.cols != newConfig.cols ||
        oldConfig.prizes.length != newConfig.prizes.length ||
        oldConfig.buttons.length != newConfig.buttons.length) {
      return true;
    }
    final oldCells = <GridCell>[...oldConfig.prizes, ...oldConfig.buttons];
    final newCells = <GridCell>[...newConfig.prizes, ...newConfig.buttons];
    for (var i = 0; i < oldCells.length; i++) {
      final old = oldCells[i];
      final next = newCells[i];
      if (old.x != next.x ||
          old.y != next.y ||
          old.col != next.col ||
          old.row != next.row) {
        return true;
      }
    }
    return false;
  }

  /// 返回包含奖品数量的默认无障碍标签。
  @override
  String semanticsLabel(GridConfig config) =>
      '幸运九宫格，共 ${config.prizes.length} 个奖品';
}

/// 固定格子几何，不受巡游高亮影响。
final class _GridItemGeometry
    implements LuckyItemGeometry<GridLayout, GridFrame> {
  /// 创建无状态几何。
  const _GridItemGeometry();

  /// 只为奖品提供 Widget 内容。
  @override
  int itemCount(GridLayout layout) => layout.prizeCount;

  /// 返回包含跨行跨列及间距的完整矩形尺寸。
  @override
  Size itemSize(GridLayout layout, int index) => layout.hitRect(index).size;

  /// 把 Widget 左上角放到完整格子矩形的左上角。
  @override
  bool transformFor(
      GridLayout layout, GridFrame frame, int index, Matrix4 out) {
    if (layout.isEmpty) return false;
    final rect = layout.hitRect(index);
    out
      ..setIdentity()
      // ignore: deprecated_member_use
      ..translate(rect.left, rect.top);
    return true;
  }
}
