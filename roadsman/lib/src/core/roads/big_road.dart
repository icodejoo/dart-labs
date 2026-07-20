/// 大路插件：百家乐核心路图，龙尾右弯排列。
///
/// 移植自 `src/core/roads/big-road.ts`。
library;

import '../grid_layout.dart';
import '../types.dart';

/// 从原始结果构建大路数据。
///
/// ```dart
/// final data = buildBigRoad(results);
/// // data.cells 按出现顺序，data.columns[i] 为第 i 逻辑列的格子数
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

/// 大路插件：百家乐核心路图，龙尾右弯排列。
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

      // 角标偏移 0.36（不是 0.4/0.46！）：
      // 完全清出本格圆环需要偏移 ≥0.403（diag - 半径 > radiusRatio+半线宽），
      // 但本格是 cellSize 见方，偏移 + 角标半径(0.12) 一旦超过 0.5 就会探出本格边界，
      // 伸进下一格的地盘——下一格的圆环在绘制数组里排在后面，会覆盖探出的部分，
      // 呈现"被相邻圆圈咬掉一块"。两个约束互斥（0.403 vs 0.38 谁大谁小），
      // 优先保证不越界（0.36+0.12=0.48<0.5），代价是跟自己这格的圆环有少量重叠——
      // 这没问题，z-order 在同一格内角标本来就画在圆环之后，稳压得住。
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

/// [BigRoadPlugin] 的单例实例，供 `roadRegistry` 注册使用。
final bigRoadPlugin = BigRoadPlugin();
