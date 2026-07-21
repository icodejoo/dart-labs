/// Trio derived-road board plugin: draws the three derived roads (Big Eye Boy/Small Road/
/// Cockroach Road) together on a single 6-grid-row grid, splitting each grid cell into 2x2
/// sub-cells, matching a real casino scoreboard's combined board presentation.
///
/// Does not reimplement any derived-road algorithm: directly reuses each of the three plugins'
/// own derive data and pure layout functions, only doing "half-cell scaling + region
/// translation". Region layout: Big Eye Boy occupies the top 3 grid rows (full width), Small
/// Road occupies the bottom 3 grid rows' left half, Cockroach Road occupies the bottom 3 grid
/// rows' right half.
///
/// Ported from `src/core/roads/derived-trio.ts`.
library;

import 'dart:math' as math;

import '../types.dart';
import 'band_merge.dart';
import 'big_eye_boy.dart';
import 'cockroach_road.dart';
import 'small_road.dart';

/// Minimum split-column count (in grid cells). When the Small Road region's width falls short of
/// this value it still occupies the full width; the reference figure is half of an 18-grid-cell width.
const int minHalfCols = 9;

/// Minimum total column count (in grid cells). Keeps the panel filled with a full screen of tiles
/// even when data is empty or sparse.
const int minTotalCols = 18;

/// Converts the pixel width output by [layout] into a grid column count (rounded up).
int colsOf(RoadLayout layout, double cellSize) => (layout.contentWidth / cellSize).ceil();

/// Trio derived-road board plugin.
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
      // The background tile grid shares the same viewport transform as the content on the
      // rendering layer, so continuous drawing isn't limited by totalCols; cellSize takes the
      // sub-cell edge length s, with colSpan/rowSpan=2 making every 2x2 sub-cells visually merge
      // into one grid tile.
      grid: GridSpec(cellSize: s, colSpan: 2, rowSpan: 2, style: GridStyle.tile, tileFill: cfg.theme.palette.tileFill),
    );
  }
}

/// Singleton instance of [DerivedTrioPlugin].
final derivedTrioPlugin = DerivedTrioPlugin();
