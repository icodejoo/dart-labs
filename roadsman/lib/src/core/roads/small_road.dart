/// 小路插件（k=2）：比较隔列列长，实心圆。
///
/// 移植自 `src/core/roads/small-road.ts`。
library;

import '../grid_layout.dart';
import '../types.dart';
import 'derived_road.dart';

/// 小路插件（k=2）：比较隔列列长，实心圆。
class SmallRoadPlugin extends RoadPlugin<DerivedRoadData> {
  @override
  String get id => 'smallRoad';

  @override
  RoadKind get kind => RoadKind.grid;

  @override
  List<String> get dependsOn => const ['bigRoad'];

  @override
  DerivedRoadData derive(RoadContext ctx) => deriveRoad(ctx.get<BigRoadData>('bigRoad'), 2);

  @override
  RoadLayout layout(DerivedRoadData data, LayoutConfig cfg, RoadContext ctx) {
    final cellSize = cfg.cellSize;
    final rows = cfg.rows;
    final theme = cfg.theme;
    final palette = theme.palette;
    final cellTheme = theme.cell;
    final roadTheme = theme.roads['smallRoad'];
    final radiusRatio = roadTheme?.radiusRatio ?? cellTheme.radiusRatio;

    final cols = derivedToColumns(data.entries);
    final placed = placeOnGrid(cols, rows);
    final cells = <LayoutCell>[];

    for (var i = 0; i < data.entries.length; i++) {
      final p = placed[i];
      final px = cellToPixel(p.physCol, p.physRow, cellSize);
      final fill = data.entries[i] == DerivedColor.red ? palette.red : palette.blue;

      cells.add(
        LayoutCell(
          key: '$i',
          x: p.physCol * cellSize,
          y: p.physRow * cellSize,
          w: cellSize,
          h: cellSize,
          resultNo: i,
          commands: [CircleCommand(x: px.x, y: px.y, r: cellSize * radiusRatio, fill: fill)],
        ),
      );
    }

    final size = contentSize(placed, rows, cellSize);
    return RoadLayout(cells: cells, contentWidth: size.width, contentHeight: size.height);
  }
}

/// [SmallRoadPlugin] 的单例实例。
final smallRoadPlugin = SmallRoadPlugin();
