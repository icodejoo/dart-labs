import 'package:flutter_test/flutter_test.dart';
import 'package:roadsman/roadsman.dart';

RawResult _r(int no, String winner) => RawResult(no: no, winner: winner, bankerPair: false, playerPair: false);

void main() {
  group('deriveRoad', () {
    test('Big Eye Boy (k=1) only starts counting at the second column, second row', () {
      // Column structure [B] [P] [B] ... entries only start being produced once the first
      // two columns are past (k=1 needs at least col==1,row==1 or col==2,row==0),
      // so a short sequence should yield empty entries.
      final short = buildBigRoad([_r(1, 'B'), _r(2, 'P')]);
      final derived = deriveRoad(short, 1);
      expect(derived.entries, isEmpty);
    });

    test('falls red when column lengths follow the pattern, blue when they do not', () {
      // Setup: col0=[B,B] (length 2), col1=[P] (length 1), col2=[B] begins...
      // Big Eye Boy starts counting from col=1,row=... or col=2,row=0, comparing the
      // lengths of column (c-1) and column (c-1-k).
      final results = [
        _r(1, 'B'),
        _r(2, 'B'), // col0 length 2
        _r(3, 'P'), // col1 length 1
        _r(4, 'B'), // col2 length 1 (new column, starting point c=2,row=0, k=1)
        _r(5, 'P'), // col3 length 1
        _r(6, 'B'), // col4 length 1
      ];
      final bigRoad = buildBigRoad(results);
      final derived = deriveRoad(bigRoad, 1);

      // col2 is a new column: compare col1 (length 1) with col0 (length 2) -> different -> blue
      expect(derived.entries.first, DerivedColor.blue);
    });

    test('sourceCellIndex has the same length as entries, and indices point into big road cells', () {
      final results = List.generate(10, (i) => _r(i + 1, i.isEven ? 'B' : 'P'));
      final bigRoad = buildBigRoad(results);
      final derived = deriveRoad(bigRoad, 1);
      expect(derived.sourceCellIndex, hasLength(derived.entries.length));
      for (final idx in derived.sourceCellIndex) {
        expect(idx, lessThan(bigRoad.cells.length));
      }
    });
  });

  group('derivedToColumns', () {
    test('merges consecutive same colors into one column, same rule as the big road but with no ties', () {
      final cols = derivedToColumns([
        DerivedColor.red,
        DerivedColor.red,
        DerivedColor.blue,
        DerivedColor.blue,
        DerivedColor.blue,
        DerivedColor.red,
      ]);
      expect(cols, [2, 3, 1]);
    });

    test('returns an empty list for empty input', () {
      expect(derivedToColumns(const []), isEmpty);
    });
  });
}
