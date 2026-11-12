import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' show Matrix4;

import '../core/foundation/image.dart';
import '../core/game/game.dart';
import '../core/game/layout.dart';
import '../core/widgets/item_overlay.dart';
import 'control/slot_controller.dart';
import 'layout/slot_layout.dart';
import 'model/slot_config.dart';
import 'model/slot_parts.dart';
import 'model/slot_result.dart';
import 'motion/slot_motion.dart';
import 'render/slot_canvas_renderer.dart';

/// 无状态老虎机规则，可直接用于 LuckyGameView 或注册表。
final class SlotGame
    extends LuckyGame<SlotConfig, SlotLayout, SlotFrame, SlotResult> {
  /// 创建规则。
  const SlotGame();

  /// 返回各轮条带位置及循环副本的几何，洞保留位置但不可见。
  ///
  /// 下标按轮、循环副本、条带位置排列。每轮副本数为
  /// ceil(windowLength / period) + ceil(cellExtent / period)；
  /// children 须重复对应的奖品 Widget，cellExtent 是滚动轴格子长度。
  /// 使用 clipRectFor 的轮窗口裁剪，可同时呈现同一奖品的多个副本。
  @override
  LuckyItemGeometry<SlotLayout, SlotFrame> get itemGeometry =>
      const _SlotItemGeometry();

  /// 计算可见窗口布局。
  @override
  SlotLayout computeLayout(SlotConfig config, LuckyLayoutInput input) =>
      computeSlotLayout(config, input);

  /// 收集块和格子的全部图片及逻辑解码尺寸。
  @override
  List<LuckyImageRequest> collectImages(SlotConfig config, SlotLayout layout) =>
      [
        for (final placements in [
          ...layout.blocks.map((b) => b.images),
          ...layout.cells.map((c) => c.images)
        ])
          for (final placement in placements) placement.toRequest()
      ];

  /// 创建由宿主负责释放的控制器。
  @override
  SlotController createController() => SlotController();

  /// 创建默认可见窗口后端。
  @override
  SlotCanvasRenderer createDefaultRenderer() => const SlotCanvasRenderer();

  /// 列数、顺序、奖品数和格距改变属于结构变更。
  @override
  bool isStructuralChange(SlotConfig oldConfig, SlotConfig newConfig) =>
      slotStructureChanged(oldConfig, newConfig);

  /// 默认读屏标签。
  @override
  String semanticsLabel(SlotConfig config) => '老虎机';
}

/// 显式保留循环副本，避免短条带在大窗口中遗漏重复奖品。
final class _SlotItemGeometry
    implements
        LuckyItemGeometry<SlotLayout, SlotFrame>,
        LuckyItemClipGeometry<SlotLayout> {
  /// 创建无状态几何。
  const _SlotItemGeometry();

  /// 返回每轮需要的副本数。
  int _copies(SlotLayout layout, SlotReelLayout reel) {
    if (reel.period <= 0) return 0;
    final extent =
        layout.mode == SlotMode.vertical ? layout.cellHeight : layout.cellWidth;
    return (layout.windowLength / reel.period).ceil() +
        (extent / reel.period).ceil();
  }

  /// 把全局条目下标解析为轮、副本及条带位置。
  (int, int, int) _entry(SlotLayout layout, int index) {
    for (var r = 0; r < layout.reels.length; r++) {
      final reel = layout.reels[r];
      final count = reel.stripPrizes.length;
      final total = count * _copies(layout, reel);
      if (index < total) return (r, index ~/ count, index % count);
      index -= total;
    }
    throw RangeError.index(index, layout.reels);
  }

  /// 返回包括洞和循环副本在内的稳定条目数。
  @override
  int itemCount(SlotLayout layout) => layout.isEmpty
      ? 0
      : layout.reels.fold(
          0,
          (count, reel) =>
              count + reel.stripPrizes.length * _copies(layout, reel));

  /// 所有条目均使用一个格子的逻辑尺寸。
  @override
  Size itemSize(SlotLayout layout, int index) =>
      Size(layout.cellWidth, layout.cellHeight);

  /// 将每个条目裁剪到所属轮窗口，保留边缘部分可见的格子。
  @override
  Rect clipRectFor(SlotLayout layout, int index) =>
      layout.reels[_entry(layout, index).$1].clipRect;

  /// 使用与窗口回放相同的取余及条带起点，隐藏洞和窗口外条目。
  @override
  bool transformFor(
      SlotLayout layout, SlotFrame frame, int index, Matrix4 out) {
    if (layout.isEmpty) return false;
    final (r, copy, strip) = _entry(layout, index);
    final reel = layout.reels[r];
    if (reel.stripPrizes[strip] < 0) return false;
    final vertical = layout.mode == SlotMode.vertical;
    final extent = vertical ? layout.cellHeight : layout.cellWidth;
    var s = frame.scroll[r] + layout.windowStart;
    if (s < 0) s = s.remainder(reel.period) + reel.period;
    if (s > reel.period) s = s.remainder(reel.period);
    var start = reel.stripStart[strip] - s;
    // 规范到与窗口相交的最早副本；其余副本保持稳定且不共享 Widget 状态。
    while (start + extent <= 0) {
      start += reel.period;
    }
    while (start - reel.period + extent > 0) {
      start -= reel.period;
    }
    start += copy * reel.period;
    if (start >= layout.windowLength) return false;
    out
      ..setIdentity()
      // ignore: deprecated_member_use
      ..translate(reel.clipRect.left + (vertical ? 0 : start),
          reel.clipRect.top + (vertical ? start : 0));
    return true;
  }
}
