/// 紧凑完整路纸插件：大路（全尺寸 6 大行）叠在三合一合板（6 大行）之上，共 12
/// 大行，对应真实赌场记分牌的完整呈现。
///
/// 不重新实现任何路算法，直接复用大路与三条衍生路各自的 layout 纯函数，只做
/// "区域堆叠 + 平移"；瓷砖背景/分割列策略与 [derivedTrioPlugin] 共享同一套常量与
/// 折算逻辑（从 `derived_trio.dart` 导入复用，不复制）。
///
/// 移植自 `src/core/roads/compact-road-sheet.ts`。
library;

import 'dart:math' as math;

import '../types.dart';
import 'band_merge.dart';
import 'big_eye_boy.dart';
import 'big_road.dart';
import 'cockroach_road.dart';
import 'derived_trio.dart' show colsOf, minHalfCols, minTotalCols;
import 'small_road.dart';

/// 紧凑完整路纸插件。
class CompactRoadSheetPlugin extends RoadPlugin<void> {
  @override
  String get id => 'compactRoadSheet';

  @override
  RoadKind get kind => RoadKind.grid;

  @override
  List<String> get dependsOn => const ['bigRoad', 'bigEyeBoy', 'smallRoad', 'cockroachRoad'];

  @override
  void derive(RoadContext ctx) {}

  @override
  RoadLayout layout(void data, LayoutConfig cfg, RoadContext ctx) {
    final big = bigRoadPlugin.layout(
      ctx.get<BigRoadData>('bigRoad'),
      LayoutConfig(cellSize: cfg.cellSize, rows: 6, theme: cfg.theme),
      ctx,
    );
    final bigCols = colsOf(big, cfg.cellSize);

    final s = cfg.cellSize / 2;
    final subCfg = LayoutConfig(cellSize: s, rows: 6, theme: cfg.theme);
    final eye = bigEyeBoyPlugin.layout(ctx.get<DerivedRoadData>('bigEyeBoy'), subCfg, ctx);
    final small = smallRoadPlugin.layout(ctx.get<DerivedRoadData>('smallRoad'), subCfg, ctx);
    final roach = cockroachRoadPlugin.layout(ctx.get<DerivedRoadData>('cockroachRoad'), subCfg, ctx);

    final eyeCols = colsOf(eye, cfg.cellSize);
    final smallCols = colsOf(small, cfg.cellSize);
    final roachCols = colsOf(roach, cfg.cellSize);

    final h = math.max(smallCols, minHalfCols);
    final totalCols = [bigCols, eyeCols, h + roachCols, minTotalCols].reduce(math.max);

    // 大路 band 置顶（dy=0），三合一合板整体下移 6 个大格（dy=6*cellSize）；
    // 三合一内部的相对偏移（小路/曱甴路 dy=9*cellSize、曱甴路 dx=H*cellSize）与
    // derivedTrio 独立计算时一致，只是叠加了大路 band 的整体偏移基准。
    final merged = mergeBands([
      Band(prefix: 'big', layout: big),
      Band(prefix: 'eye', layout: eye, dy: 6 * cfg.cellSize),
      Band(prefix: 'small', layout: small, dy: 9 * cfg.cellSize),
      Band(prefix: 'roach', layout: roach, dx: h * cfg.cellSize, dy: 9 * cfg.cellSize),
    ]);

    return RoadLayout(
      cells: merged.cells,
      decorations: merged.decorations,
      contentWidth: totalCols * cfg.cellSize,
      contentHeight: 12 * cfg.cellSize,
      // 大路区（顶部 6 大行）与三合一合板区（底部 6 大行）共用同一套 cellSize 大格瓷砖，
      // 尽管两区内部标记的最细定位单元不同（大路整格 vs 合板半格），瓷砖网格只关心
      // 视觉呈现的大格粒度，取子格边长 s、colSpan/rowSpan=2 与 derivedTrio 保持一致。
      grid: GridSpec(cellSize: s, colSpan: 2, rowSpan: 2, style: GridStyle.tile, tileFill: cfg.theme.palette.tileFill),
    );
  }
}

/// [CompactRoadSheetPlugin] 的单例实例。
final compactRoadSheetPlugin = CompactRoadSheetPlugin();
