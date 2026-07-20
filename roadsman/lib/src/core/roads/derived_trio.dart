/// 三合一衍生路合板插件：把大眼仔/小路/曱甴路三条衍生路合画在同一张 6 大行网格上，
/// 每个大格切 2×2 子格，对应真实赌场记分牌的合板呈现。
///
/// 不重新实现任何衍生路算法：直接复用三个插件各自的 derive 数据与 layout 纯函数，
/// 只做"半格缩放 + 区域平移"。区域划分：大眼仔占上 3 大行（全宽），小路占下 3 大行
/// 左半，曱甴路占下 3 大行右半。
///
/// 移植自 `src/core/roads/derived-trio.ts`。
library;

import 'dart:math' as math;

import '../types.dart';
import 'band_merge.dart';
import 'big_eye_boy.dart';
import 'cockroach_road.dart';
import 'small_road.dart';

/// 分割列下限（大格数）。小路区域宽度不足此值时仍占满，参考图 18 大格宽的一半。
const int minHalfCols = 9;

/// 总列数下限（大格数）。空数据/数据很少时面板仍铺满一屏瓷砖。
const int minTotalCols = 18;

/// 把 [layout] 输出的像素宽折算成大格列数（向上取整）。
int colsOf(RoadLayout layout, double cellSize) => (layout.contentWidth / cellSize).ceil();

/// 三合一衍生路合板插件。
class DerivedTrioPlugin extends RoadPlugin<void> {
  @override
  String get id => 'derivedTrio';

  @override
  RoadKind get kind => RoadKind.grid;

  @override
  List<String> get dependsOn => const ['bigEyeBoy', 'smallRoad', 'cockroachRoad'];

  @override
  void derive(RoadContext ctx) {}

  @override
  RoadLayout layout(void data, LayoutConfig cfg, RoadContext ctx) {
    final s = cfg.cellSize / 2;
    final subCfg = LayoutConfig(cellSize: s, rows: 6, theme: cfg.theme);

    final eye = bigEyeBoyPlugin.layout(ctx.get<DerivedRoadData>('bigEyeBoy'), subCfg, ctx);
    final small = smallRoadPlugin.layout(ctx.get<DerivedRoadData>('smallRoad'), subCfg, ctx);
    final roach = cockroachRoadPlugin.layout(ctx.get<DerivedRoadData>('cockroachRoad'), subCfg, ctx);

    final eyeCols = colsOf(eye, cfg.cellSize);
    final smallCols = colsOf(small, cfg.cellSize);
    final roachCols = colsOf(roach, cfg.cellSize);

    final h = math.max(smallCols, minHalfCols);
    final totalCols = [eyeCols, h + roachCols, minTotalCols].reduce(math.max);

    final merged = mergeBands([
      Band(prefix: 'eye', layout: eye),
      Band(prefix: 'small', layout: small, dy: 3 * cfg.cellSize),
      Band(prefix: 'roach', layout: roach, dx: h * cfg.cellSize, dy: 3 * cfg.cellSize),
    ]);

    return RoadLayout(
      cells: merged.cells,
      decorations: merged.decorations,
      contentWidth: totalCols * cfg.cellSize,
      contentHeight: 6 * cfg.cellSize,
      // 背景瓷砖网格与内容共用渲染层同一份 viewport 变换，连续绘制不受 totalCols 限制；
      // cellSize 取子格边长 s，colSpan/rowSpan=2 让每 2×2 个子格视觉合并成 1 个大格瓷砖。
      grid: GridSpec(cellSize: s, colSpan: 2, rowSpan: 2, style: GridStyle.tile, tileFill: cfg.theme.palette.tileFill),
    );
  }
}

/// [DerivedTrioPlugin] 的单例实例。
final derivedTrioPlugin = DerivedTrioPlugin();
