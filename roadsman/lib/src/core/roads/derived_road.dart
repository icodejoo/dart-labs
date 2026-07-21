/// The shared parameterized derived-road algorithm for Big Eye Boy/Small Road/Cockroach Road.
///
/// Ported from `src/core/roads/derived-road.ts`.
library;

import '../types.dart';

/// Derives derived-road data from big road [bigRoad] using offset [k] (k=1 Big Eye Boy, k=2 Small Road, k=3 Cockroach Road).
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
      // New column: compares the lengths of columns (c-1) and (c-1-k).
      final lenA = (c - 1 >= 0 && c - 1 < columns.length) ? columns[c - 1] : 0;
      final lenB = (c - 1 - k >= 0 && c - 1 - k < columns.length) ? columns[c - 1 - k] : 0;
      color = lenA == lenB ? DerivedColor.red : DerivedColor.blue;
    } else {
      // Continuing down the same column: checks whether column c-k has a cell at depth r.
      final lenCk = (c - k >= 0 && c - k < columns.length) ? columns[c - k] : 0;
      color = lenCk == r ? DerivedColor.blue : DerivedColor.red;
    }

    entries.add(color);
    sourceCellIndex.add(i);
  }

  return DerivedRoadData(entries: entries, sourceCellIndex: sourceCellIndex);
}

/// Builds the array of logical column heights from a derived road's color sequence (same rule as big road, but with no ties).
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
