/// Pair road plugin: shows only rounds with a pair, laid out in sequential serpentine order.
///
/// Ported from `src/core/roads/pair-road.ts`.
library;

import '../grid_layout.dart';
import '../types.dart';

/// Pair road plugin: shows only rounds with a pair, laid out in sequential serpentine order.
class PairRoadPlugin extends RoadPlugin<List<RawResult>> {
  @override
  String get id => 'pairRoad';

  @override
  RoadKind get kind => RoadKind.grid;

  @override
  List<RawResult> derive(RoadContext ctx) =>
      ctx.results.where((r) => r.bankerPair || r.playerPair).toList();

  @override
  RoadLayout layout(List<RawResult> data, LayoutConfig cfg, RoadContext ctx) {
    final cellSize = cfg.cellSize;
    final rows = cfg.rows;
    final theme = cfg.theme;
    final palette = theme.palette;
    final cellTheme = theme.cell;
    final roadTheme = theme.roads['pairRoad'];
    final radiusRatio = roadTheme?.radiusRatio ?? cellTheme.radiusRatio;
    final lineWidth = roadTheme?.lineWidth ?? (cellTheme.lineWidth - 0.5);

    final cells = <LayoutCell>[];

    for (var i = 0; i < data.length; i++) {
      final r = data[i];
      final p = placeSequential(i, rows);
      final px = cellToPixel(p.physCol, p.physRow, cellSize);

      final commands = <DrawCommand>[
        CircleCommand(x: px.x, y: px.y, r: cellSize * radiusRatio, stroke: 0xFF999999, lineWidth: lineWidth),
      ];

      if (r.bankerPair) {
        commands.add(
          DotCommand(x: px.x - cellSize * 0.22, y: px.y - cellSize * 0.22, r: cellSize * 0.2, fill: palette.banker),
        );
      }
      if (r.playerPair) {
        commands.add(
          DotCommand(x: px.x + cellSize * 0.22, y: px.y + cellSize * 0.22, r: cellSize * 0.2, fill: palette.player),
        );
      }

      cells.add(
        LayoutCell(
          key: '${r.no}',
          x: p.physCol * cellSize,
          y: p.physRow * cellSize,
          w: cellSize,
          h: cellSize,
          resultNo: r.no,
          commands: commands,
        ),
      );
    }

    final colCount = data.isEmpty ? 0 : ((data.length - 1) ~/ rows) + 1;
    return RoadLayout(cells: cells, contentWidth: colCount * cellSize, contentHeight: rows * cellSize);
  }
}

/// Singleton instance of [PairRoadPlugin].
final pairRoadPlugin = PairRoadPlugin();
