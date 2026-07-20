/// 大路合并三点 overlay：在大路格子上叠加大眼仔/小路/曱甴路标记。
///
/// 移植自 `src/core/roads/big-road-merged-dots.ts`。
library;

import 'dart:math' as math;

import '../grid_layout.dart';
import '../types.dart';

/// 大路合并三点 overlay 插件。
class BigRoadMergedDotsPlugin extends RoadPlugin<void> {
  @override
  String get id => 'bigRoadMergedDots';

  @override
  RoadKind get kind => RoadKind.overlay;

  @override
  List<String> get dependsOn => const ['bigRoad', 'bigEyeBoy', 'smallRoad', 'cockroachRoad'];

  @override
  void derive(RoadContext ctx) {}

  @override
  RoadLayout layout(void data, LayoutConfig cfg, RoadContext ctx) {
    final cellSize = cfg.cellSize;
    final rows = cfg.rows;
    final palette = cfg.theme.palette;
    final bigRoad = ctx.get<BigRoadData>('bigRoad');
    final bigEyeBoy = ctx.get<DerivedRoadData>('bigEyeBoy');
    final smallRoad = ctx.get<DerivedRoadData>('smallRoad');
    final cockroach = ctx.get<DerivedRoadData>('cockroachRoad');

    final placed = placeOnGrid(bigRoad.columns, rows);
    final decorations = <DrawCommand>[];

    void addMark(DerivedRoadData road, double dxFactor, double dyFactor, double r, bool isSlash) {
      for (var i = 0; i < road.entries.length; i++) {
        final cellIdx = road.sourceCellIndex[i];
        if (cellIdx >= placed.length) continue;
        final p = placed[cellIdx];
        final px = cellToPixel(p.physCol, p.physRow, cellSize);
        final mx = px.x + dxFactor * cellSize;
        final my = px.y + dyFactor * cellSize;
        final color = road.entries[i] == DerivedColor.red ? palette.red : palette.blue;
        if (isSlash) {
          decorations.add(SlashCommand(x: mx, y: my, r: r, stroke: color, lineWidth: 1.5));
        } else {
          decorations.add(DotCommand(x: mx, y: my, r: r, fill: color));
        }
      }
    }

    addMark(bigEyeBoy, 0.3, -0.3, cellSize * 0.1, false);
    addMark(smallRoad, 0.3, 0.3, cellSize * 0.1, false);
    addMark(cockroach, -0.3, 0.3, cellSize * 0.12, true);

    final maxPhysCol = placed.isNotEmpty ? placed.map((p) => p.physCol).reduce(math.max) : -1;
    return RoadLayout(
      cells: const [],
      decorations: decorations,
      contentWidth: (maxPhysCol + 1) * cellSize,
      contentHeight: rows * cellSize,
    );
  }
}

/// [BigRoadMergedDotsPlugin] 的单例实例。
final bigRoadMergedDotsPlugin = BigRoadMergedDotsPlugin();
