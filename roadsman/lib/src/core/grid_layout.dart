/// 物理网格布局：把逻辑列高数组摆放到物理网格上（龙尾右弯/顺序摆放两种算法）。
///
/// 移植自 `src/core/grid-layout.ts`。
library;

import 'dart:math' as math;

import 'types.dart';

/// 一个逻辑格子在物理网格上的放置结果。
class PlacedCell {
  /// 物理列（0-based）。
  final int physCol;

  /// 物理行（0-based）。
  final int physRow;

  const PlacedCell({required this.physCol, required this.physRow});
}

/// 把逻辑列高数组（大路每列的格数）摆放到物理网格上：列满 [rows] 行后向右换列
/// （"龙尾"逻辑），列间不重叠。
List<PlacedCell> placeOnGrid(List<int> logicalColumns, int rows) {
  // 占用集用整数键（col*4096+row）而非 '$col,$row' 字符串——本函数是布局热路径
  // （每次 compute 大路/三条衍生路/长龙高亮各跑一遍），字符串插值+哈希是这里
  // 最大的分配来源。rows 远小于 4096，编码无碰撞。
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

/// 按列优先顺序摆放一个扁平索引（珠盘路/对子路/例牌路用：逐局顺序填格，不做归并）。
PlacedCell placeSequential(int index, int rows) =>
    PlacedCell(physCol: index ~/ rows, physRow: index % rows);

/// 像素坐标。
class PixelPoint {
  final double x;
  final double y;
  const PixelPoint(this.x, this.y);
}

/// 物理格子坐标转像素坐标（格子中心点）。
PixelPoint cellToPixel(int physCol, int physRow, double cellSize) =>
    PixelPoint(physCol * cellSize + cellSize / 2, physRow * cellSize + cellSize / 2);

/// 生成背景网格线指令，在路圆圈之前绘制。
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

/// 内容尺寸。
class ContentSize {
  final double width;
  final double height;
  const ContentSize(this.width, this.height);
}

/// 计算一组已摆放格子的总内容尺寸。
ContentSize contentSize(List<PlacedCell> cells, int rows, double cellSize) {
  if (cells.isEmpty) return ContentSize(0, rows * cellSize);
  final maxCol = cells.map((c) => c.physCol).reduce(math.max);
  return ContentSize((maxCol + 1) * cellSize, rows * cellSize);
}

/// 把 [v] 四舍五入到指定精度（golden fixture 数值确定性用）。
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
