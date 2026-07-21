/// Compact full road sheet plugin: big road (full size, 6 grid rows) stacked on top of the trio
/// board (6 grid rows), 12 grid rows total, matching a real casino scoreboard's full presentation.
///
/// Does not reimplement any road algorithm; directly reuses the pure layout functions of big road
/// and the three derived roads, only doing "region stacking + translation". The tile background /
/// split-column strategy shares the same constants and conversion logic as [derivedTrioPlugin]
/// (imported and reused from `derived_trio.dart`, not duplicated).
///
/// Ported from `src/core/roads/compact-road-sheet.ts`.
library;

import 'dart:math' as math;

import '../types.dart';
import 'band_merge.dart';
import 'big_eye_boy.dart';
import 'big_road.dart';
import 'cockroach_road.dart';
import 'derived_trio.dart' show colsOf, minHalfCols, minTotalCols;
import 'small_road.dart';

/// Compact full road sheet plugin.
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

    // The big road band sits at the top (dy=0); the trio board is shifted down 6 grid cells
    // (dy=6*cellSize) as a whole. The relative offsets within the trio (small road/cockroach road
    // dy=9*cellSize, cockroach road dx=H*cellSize) match what derivedTrio computes on its own —
    // just added on top of the big road band's overall offset baseline.
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
      // The big road region (top 6 grid rows) and the trio board region (bottom 6 grid rows)
      // share the same cellSize grid tile, even though the finest positioning unit differs
      // between the two regions (big road whole cells vs. trio board half-cells) — the tile grid
      // only cares about the visual grid granularity, so it uses the sub-cell edge length s with
      // colSpan/rowSpan=2, consistent with derivedTrio.
      grid: GridSpec(cellSize: s, colSpan: 2, rowSpan: 2, style: GridStyle.tile, tileFill: cfg.theme.palette.tileFill),
    );
  }
}

/// Singleton instance of [CompactRoadSheetPlugin].
final compactRoadSheetPlugin = CompactRoadSheetPlugin();
