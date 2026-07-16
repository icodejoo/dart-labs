/// 长龙/单跳/双跳高亮 overlay 插件，输出为装饰指令（无 cells）。
///
/// 移植自 `src/core/roads/streak-highlight.ts`。
library;

import 'dart:math' as math;

import '../grid_layout.dart';
import '../types.dart';

/// 连庄/连闲判定的最低列数阈值。
const int _dragonMin = 4;

/// 单跳连续判定最低列数。
const int _singleHopMin = 4;

/// 双跳连续判定最低列数。
const int _doubleHopMin = 4;

/// 高亮区间类型。
enum StreakType { dragon, singleHop, doubleHop }

/// 高亮区间描述。
class StreakInterval {
  /// 高亮类型。
  final StreakType type;

  /// 起始逻辑列。
  final int colStart;

  /// 结束逻辑列。
  final int colEnd;

  const StreakInterval({required this.type, required this.colStart, required this.colEnd});
}

/// 从大路列信息中找出所有高亮区间（长龙/单跳/双跳）。
List<StreakInterval> _findIntervals(List<int> columns) {
  final intervals = <StreakInterval>[];

  // 长龙：单列高度 >= _dragonMin。
  for (var i = 0; i < columns.length; i++) {
    if (columns[i] >= _dragonMin) {
      intervals.add(StreakInterval(type: StreakType.dragon, colStart: i, colEnd: i));
    }
  }

  // 单跳：连续列长为 1 的列数 >= _singleHopMin。
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

  // 双跳：连续列长为 2 的列数 >= _doubleHopMin。
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

/// 长龙/单跳/双跳高亮 overlay 插件。
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
        // 收集大路中逻辑列 c 所占的所有物理列。
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

/// [StreakHighlightPlugin] 的单例实例。
final streakHighlightPlugin = StreakHighlightPlugin();
