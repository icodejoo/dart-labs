/// Physical grid layout: place logical column heights array on physical grid (two algorithms: dragon tail right turn / sequential placement).
///
/// Ported from `src/core/grid-layout.ts`.
library;

import 'dart:math' as math;

import 'types.dart';

/// Placement result of a logical cell on physical grid.
class PlacedCell {
  /// Physical column (0-based).
  final int physCol;

  /// Physical row (0-based).
  final int physRow;

  const PlacedCell({required this.physCol, required this.physRow});
}

/// Place logical column heights array (number of cells in each big road column) on physical grid: move right after column fills [rows] rows
/// ("dragon tail" logic), columns do not overlap.
List<PlacedCell> placeOnGrid(List<int> logicalColumns, int rows) {
  // Occupied set uses integer key (col*4096+row) instead of '$col,$row' string -- this function is on layout hot path
  // (big road/three derived roads/dragon highlight each run per compute), string interpolation+hash is the largest allocation source here.
  // rows is much less than 4096, encoding has no collision.
  final occupied = <int>{};
  final placed = <PlacedCell>[];
  var nextHeadCol = 0;
  int key(int col, int row) => col * 4096 + row;

  for (final len in logicalColumns) {
    var col = nextHeadCol;
    const row = 0;
    while (occupied.contains(key(col, row))) {
      col++;
    }
    occupied.add(key(col, row));
    placed.add(PlacedCell(physCol: col, physRow: row));
    final headCol = col;
    var curCol = col;
    var curRow = row;

    for (var i = 1; i < len; i++) {
      if (curRow + 1 < rows && !occupied.contains(key(curCol, curRow + 1))) {
        curRow = curRow + 1;
      } else {
        curCol = curCol + 1;
      }
      occupied.add(key(curCol, curRow));
      placed.add(PlacedCell(physCol: curCol, physRow: curRow));
    }

    nextHeadCol = headCol + 1;
  }

  return placed;
}

/// Place a flat index in column-first order (bead plate / pair road / natural road use: fill cells sequentially by round, no merging).
PlacedCell placeSequential(int index, int rows) =>
    PlacedCell(physCol: index ~/ rows, physRow: index % rows);

/// Pixel coordinates.
class PixelPoint {
  final double x;
  final double y;
  const PixelPoint(this.x, this.y);
}

/// Convert physical cell coordinates to pixel coordinates (cell center).
PixelPoint cellToPixel(int physCol, int physRow, double cellSize) =>
    PixelPoint(physCol * cellSize + cellSize / 2, physRow * cellSize + cellSize / 2);

/// Generate background grid line commands, drawn before road circles.
List<DrawCommand> gridCommands(int colCount, int rows, double cellSize, {int strokeColor = 0x14FFFFFF}) {
  final w = colCount * cellSize;
  final h = rows * cellSize;
  final cmds = <DrawCommand>[];
  for (var r = 0; r <= rows; r++) {
    final y = r * cellSize;
    cmds.add(LineCommand(points: [0, y, w, y], stroke: strokeColor, lineWidth: 0.5));
  }
  for (var c = 0; c <= colCount; c++) {
    final x = c * cellSize;
    cmds.add(LineCommand(points: [x, 0, x, h], stroke: strokeColor, lineWidth: 0.5));
  }
  return cmds;
}

/// Content size.
class ContentSize {
  final double width;
  final double height;
  const ContentSize(this.width, this.height);
}

/// Compute the total content size of a set of placed cells.
ContentSize contentSize(List<PlacedCell> cells, int rows, double cellSize) {
  if (cells.isEmpty) return ContentSize(0, rows * cellSize);
  final maxCol = cells.map((c) => c.physCol).reduce(math.max);
  return ContentSize((maxCol + 1) * cellSize, rows * cellSize);
}

/// Round [v] to the specified precision (used for golden fixture numeric determinism).
///
/// ```dart
/// roundTo(1.00005, 1e-4); // 1.0001
/// roundTo(-2.55555, 1e-3); // -2.556
/// roundTo(42, 1); // 42
/// ```
double roundTo(double v, double precision) {
  final factor = 1 / precision;
  return (v * factor).round() / factor;
}
