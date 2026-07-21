/// Dragon streak/single-jump/double-jump highlight overlay plugin, output as decoration commands (no cells).
///
/// Ported from `src/core/roads/streak-highlight.ts`.
library;

import 'dart:math' as math;

import '../grid_layout.dart';
import '../types.dart';

/// Minimum column-count threshold for detecting a banker/player dragon streak.
const int _dragonMin = 4;

/// Minimum column count for a single-jump run.
const int _singleHopMin = 4;

/// Minimum column count for a double-jump run.
const int _doubleHopMin = 4;

/// Type of highlight interval.
enum StreakType { dragon, singleHop, doubleHop }

/// Description of a highlight interval.
class StreakInterval {
  /// Highlight type.
  final StreakType type;

  /// Starting logical column.
  final int colStart;

  /// Ending logical column.
  final int colEnd;

  const StreakInterval({required this.type, required this.colStart, required this.colEnd});
}

/// Finds all highlight intervals (dragon/single-jump/double-jump) from the big road's column info.
List<StreakInterval> _findIntervals(List<int> columns) {
  final intervals = <StreakInterval>[];

  // Dragon streak: a single column's height >= _dragonMin.
  for (var i = 0; i < columns.length; i++) {
    if (columns[i] >= _dragonMin) {
      intervals.add(StreakInterval(type: StreakType.dragon, colStart: i, colEnd: i));
    }
  }

  // Single-jump: number of consecutive columns of length 1 >= _singleHopMin.
  var start = -1;
  for (var i = 0; i <= columns.length; i++) {
    if (i < columns.length && columns[i] == 1) {
      start = start == -1 ? i : start;
    } else {
      if (start != -1 && i - start >= _singleHopMin) {
        intervals.add(StreakInterval(type: StreakType.singleHop, colStart: start, colEnd: i - 1));
      }
      start = -1;
    }
  }

  // Double-jump: number of consecutive columns of length 2 >= _doubleHopMin.
  start = -1;
  for (var i = 0; i <= columns.length; i++) {
    if (i < columns.length && columns[i] == 2) {
      start = start == -1 ? i : start;
    } else {
      if (start != -1 && i - start >= _doubleHopMin) {
        intervals.add(StreakInterval(type: StreakType.doubleHop, colStart: start, colEnd: i - 1));
      }
      start = -1;
    }
  }

  return intervals;
}

/// Dragon streak/single-jump/double-jump highlight overlay plugin.
class StreakHighlightPlugin extends RoadPlugin<List<StreakInterval>> {
  @override
  String get id => 'streakHighlight';

  @override
  RoadKind get kind => RoadKind.overlay;

  @override
  List<String> get dependsOn => const ['bigRoad'];

  @override
  List<StreakInterval> derive(RoadContext ctx) => _findIntervals(ctx.get<BigRoadData>('bigRoad').columns);

  @override
  RoadLayout layout(List<StreakInterval> data, LayoutConfig cfg, RoadContext ctx) {
    final cellSize = cfg.cellSize;
    final rows = cfg.rows;
    final palette = cfg.theme.palette;
    final bigRoad = ctx.get<BigRoadData>('bigRoad');
    final placed = placeOnGrid(bigRoad.columns, rows);
    final decorations = <DrawCommand>[];

    final highlightPhysCols = <int>{};
    for (final interval in data) {
      for (var c = interval.colStart; c <= interval.colEnd; c++) {
        // Collects all physical columns occupied by logical column c in the big road.
        for (var i = 0; i < bigRoad.cells.length; i++) {
          if (bigRoad.cells[i].col == c) {
            highlightPhysCols.add(placed[i].physCol);
          }
        }
      }
    }

    for (final physCol in highlightPhysCols) {
      decorations.add(
        RectCommand(x: physCol * cellSize, y: 0, w: cellSize, h: rows * cellSize, fill: palette.highlight),
      );
    }

    final maxPhysCol = placed.isNotEmpty ? placed.map((p) => p.physCol).reduce(math.max) : -1;
    return RoadLayout(
      cells: const [],
      decorations: decorations,
      contentWidth: (maxPhysCol + 1) * cellSize,
      contentHeight: rows * cellSize,
    );
  }
}

/// Singleton instance of [StreakHighlightPlugin].
final streakHighlightPlugin = StreakHighlightPlugin();
