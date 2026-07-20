/// 大眼仔/小路/曱甴路共用的参数化衍生算法。
///
/// 移植自 `src/core/roads/derived-road.ts`。
library;

import '../types.dart';

/// 基于大路 [bigRoad] 按偏移量 [k] 推导衍生路数据（k=1 大眼仔，k=2 小路，k=3 曱甴路）。
DerivedRoadData deriveRoad(BigRoadData bigRoad, int k) {
  final cells = bigRoad.cells;
  final columns = bigRoad.columns;
  final entries = <DerivedColor>[];
  final sourceCellIndex = <int>[];

  var started = false;

  for (var i = 0; i < cells.length; i++) {
    final cell = cells[i];
    final c = cell.col;
    final r = cell.row;

    if (!started) {
      if ((c == k && r == 1) || (c == k + 1 && r == 0)) {
        started = true;
      } else {
        continue;
      }
    }

    DerivedColor color;
    if (r == 0) {
      // 新列：比较 (c-1) 和 (c-1-k) 两列的长度。
      final lenA = (c - 1 >= 0 && c - 1 < columns.length) ? columns[c - 1] : 0;
      final lenB = (c - 1 - k >= 0 && c - 1 - k < columns.length) ? columns[c - 1 - k] : 0;
      color = lenA == lenB ? DerivedColor.red : DerivedColor.blue;
    } else {
      // 同列往下：检查 c-k 列在深度 r 处是否有格子。
      final lenCk = (c - k >= 0 && c - k < columns.length) ? columns[c - k] : 0;
      color = lenCk == r ? DerivedColor.blue : DerivedColor.red;
    }

    entries.add(color);
    sourceCellIndex.add(i);
  }

  return DerivedRoadData(entries: entries, sourceCellIndex: sourceCellIndex);
}

/// 从衍生路的颜色序列构建逻辑列高数组（规则同大路，但无和局）。
List<int> derivedToColumns(List<DerivedColor> entries) {
  final columns = <int>[];
  DerivedColor? last;
  for (final e in entries) {
    if (e == last) {
      columns[columns.length - 1]++;
    } else {
      columns.add(1);
      last = e;
    }
  }
  return columns;
}
