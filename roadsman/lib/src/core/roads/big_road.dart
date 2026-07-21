/// Big road plugin: baccarat's core road chart, laid out with dragon-tail turns to the right.
///
/// Ported from `src/core/roads/big-road.ts`.
library;

import '../grid_layout.dart';
import '../types.dart';

/// Builds big road data from raw results.
///
/// ```dart
/// final data = buildBigRoad(results);
/// // data.cells are in order of appearance; data.columns[i] is the cell count of logical column i
/// ```
BigRoadData buildBigRoad(List<RawResult> results) {
  final cells = <BigRoadCell>[];
  final columns = <int>[];
  var leadingTies = 0;
  String? lastWinner;

  for (final r in results) {
    if (r.winner == 'T') {
      if (cells.isEmpty) {
        leadingTies++;
      } else {
        final last = cells.removeLast();
        cells.add(
          BigRoadCell(
            col: last.col,
            row: last.row,
            winner: last.winner,
            tieCount: last.tieCount + 1,
            bankerPair: last.bankerPair,
            playerPair: last.playerPair,
            natural: last.natural,
            resultNo: last.resultNo,
          ),
        );
      }
      continue;
    }

    if (r.winner == lastWinner) {
      final col = columns.length - 1;
      final row = columns[col];
      columns[col]++;
      cells.add(
        BigRoadCell(
          col: col,
          row: row,
          winner: r.winner,
          tieCount: 0,
          bankerPair: r.bankerPair,
          playerPair: r.playerPair,
          natural: r.natural ?? false,
          resultNo: r.no,
        ),
      );
    } else {
      final col = columns.length;
      columns.add(1);
      lastWinner = r.winner;
      final tie = cells.isEmpty ? leadingTies : 0;
      cells.add(
        BigRoadCell(
          col: col,
          row: 0,
          winner: r.winner,
          tieCount: tie,
          bankerPair: r.bankerPair,
          playerPair: r.playerPair,
          natural: r.natural ?? false,
          resultNo: r.no,
        ),
      );
    }
  }

  return BigRoadData(cells: cells, columns: columns, leadingTies: leadingTies);
}

/// Big road plugin: baccarat's core road chart, laid out with dragon-tail turns to the right.
class BigRoadPlugin extends RoadPlugin<BigRoadData> {
  @override
  String get id => 'bigRoad';

  @override
  RoadKind get kind => RoadKind.grid;

  @override
  BigRoadData derive(RoadContext ctx) => buildBigRoad(ctx.results);

  @override
  RoadLayout layout(BigRoadData data, LayoutConfig cfg, RoadContext ctx) {
    final cellSize = cfg.cellSize;
    final rows = cfg.rows;
    final theme = cfg.theme;
    final palette = theme.palette;
    final cellTheme = theme.cell;
    final placed = placeOnGrid(data.columns, rows);
    final cells = <LayoutCell>[];

    for (var i = 0; i < data.cells.length; i++) {
      final cell = data.cells[i];
      final p = placed[i];
      final px = cellToPixel(p.physCol, p.physRow, cellSize);
      final r = cellSize * cellTheme.radiusRatio;
      final stroke = cell.winner == 'B' ? palette.banker : palette.player;

      final commands = <DrawCommand>[
        CircleCommand(x: px.x, y: px.y, r: r, stroke: stroke, lineWidth: cellTheme.lineWidth + 0.5),
      ];

      if (cell.natural) {
        final naturalFill = theme.roads['bigRoad']?.get<int>('naturalFill', 0xFFFFA726) ?? 0xFFFFA726;
        commands.add(DotCommand(x: px.x, y: px.y, r: cellSize * 0.26, fill: naturalFill));
      }

      if (cell.tieCount > 0) {
        commands.add(SlashCommand(x: px.x, y: px.y, r: cellSize * 0.3, stroke: palette.tie, lineWidth: 2));
        if (cell.tieCount > 1) {
          commands.add(
            BadgeCommand(
              x: px.x + cellSize * 0.3,
              y: px.y - cellSize * 0.3,
              text: '${cell.tieCount}',
              fill: palette.tie,
              fontSize: (cellSize * 0.32).round().toDouble(),
            ),
          );
        }
      }

      // Badge offset 0.36 (not 0.4/0.46!):
      // Fully clearing this cell's ring needs an offset ≥0.403 (diag - radius > radiusRatio + half line width),
      // but since the cell is cellSize square, once offset + badge radius (0.12) exceeds 0.5 it pokes
      // into the next cell's territory — that next cell's ring is drawn later in the command array
      // and would cover the part that pokes out, showing up as "a bite taken out by the adjacent
      // circle." The two constraints conflict (0.403 vs 0.38, whichever is larger), so we prioritize
      // staying in bounds (0.36+0.12=0.48<0.5), at the cost of a small overlap with this cell's own
      // ring — that's fine, since within a single cell the badge is z-ordered after the ring anyway
      // and holds up visually.
      if (cell.bankerPair) {
        commands.add(
          DotCommand(x: px.x - cellSize * 0.36, y: px.y - cellSize * 0.36, r: cellSize * 0.12, fill: palette.banker),
        );
      }
      if (cell.playerPair) {
        commands.add(
          DotCommand(x: px.x + cellSize * 0.36, y: px.y + cellSize * 0.36, r: cellSize * 0.12, fill: palette.player),
        );
      }

      cells.add(
        LayoutCell(
          key: '${cell.col}:${cell.row}',
          x: p.physCol * cellSize,
          y: p.physRow * cellSize,
          w: cellSize,
          h: cellSize,
          resultNo: cell.resultNo,
          commands: commands,
        ),
      );
    }

    final size = contentSize(placed, rows, cellSize);
    return RoadLayout(cells: cells, contentWidth: size.width, contentHeight: size.height);
  }
}

/// Singleton instance of [BigRoadPlugin], used for registration with `roadRegistry`.
final bigRoadPlugin = BigRoadPlugin();
