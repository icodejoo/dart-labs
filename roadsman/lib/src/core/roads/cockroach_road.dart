/// Cockroach road plugin (k=3): compares column lengths two columns apart, drawn as a slash marker.
///
/// Ported from `src/core/roads/cockroach-road.ts`.
library;

import '../grid_layout.dart';
import '../types.dart';
import 'derived_road.dart';

/// Cockroach road plugin (k=3): compares column lengths two columns apart, drawn as a slash marker.
class CockroachRoadPlugin extends RoadPlugin<DerivedRoadData> {
  @override
  String get id => 'cockroachRoad';

  @override
  RoadKind get kind => RoadKind.grid;

  @override
  List<String> get dependsOn => const ['bigRoad'];

  @override
  DerivedRoadData derive(RoadContext ctx) => deriveRoad(ctx.get<BigRoadData>('bigRoad'), 3);

  @override
  RoadLayout layout(DerivedRoadData data, LayoutConfig cfg, RoadContext ctx) {
    final cellSize = cfg.cellSize;
    final rows = cfg.rows;
    final theme = cfg.theme;
    final palette = theme.palette;
    final cellTheme = theme.cell;
    final roadTheme = theme.roads['cockroachRoad'];
    final radiusRatio = roadTheme?.radiusRatio ?? cellTheme.radiusRatio;
    final lineWidth = roadTheme?.lineWidth ?? cellTheme.lineWidth;

    final cols = derivedToColumns(data.entries);
    final placed = placeOnGrid(cols, rows);
    final cells = <LayoutCell>[];

    for (var i = 0; i < data.entries.length; i++) {
      final p = placed[i];
      final px = cellToPixel(p.physCol, p.physRow, cellSize);
      final stroke = data.entries[i] == DerivedColor.red ? palette.red : palette.blue;

      cells.add(
        LayoutCell(
          key: '$i',
          x: p.physCol * cellSize,
          y: p.physRow * cellSize,
          w: cellSize,
          h: cellSize,
          resultNo: i,
          commands: [SlashCommand(x: px.x, y: px.y, r: cellSize * radiusRatio, stroke: stroke, lineWidth: lineWidth)],
        ),
      );
    }

    final size = contentSize(placed, rows, cellSize);
    return RoadLayout(cells: cells, contentWidth: size.width, contentHeight: size.height);
  }
}

/// Singleton instance of [CockroachRoadPlugin].
final cockroachRoadPlugin = CockroachRoadPlugin();
