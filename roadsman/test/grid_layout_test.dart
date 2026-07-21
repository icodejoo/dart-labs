import 'package:flutter_test/flutter_test.dart';
import 'package:roadsman/roadsman.dart';

void main() {
  group('placeOnGrid', () {
    test('does not switch columns when a single column height stays within rows', () {
      final placed = placeOnGrid([3], 6);
      expect(placed.map((p) => (p.physCol, p.physRow)), [(0, 0), (0, 1), (0, 2)]);
    });

    test('switches column to the right when height exceeds rows (dragon tail bends right, stays on the bottom row instead of wrapping to the top)', () {
      final placed = placeOnGrid([8], 6);
      // The first 6 cells fill column 0 (row 0..5); once at the bottom, every extra cell
      // shifts one column to the right while staying on the same row (row=5), rather than
      // wrapping back to row=0 -- that's the intent of the "dragon tail turns right" rule.
      expect(placed[5].physCol, 0);
      expect(placed[5].physRow, 5);
      expect(placed[6].physCol, 1);
      expect(placed[6].physRow, 5);
      expect(placed[7].physCol, 2);
      expect(placed[7].physRow, 5);
    });

    test('multiple columns are each placed starting from their own headCol', () {
      final placed = placeOnGrid([2, 1, 3], 6);
      // Column 1 has 2 cells: (0,0)(0,1); column 2 has 1 cell: (1,0); column 3 has 3 cells: (2,0)(2,1)(2,2)
      expect(placed.map((p) => (p.physCol, p.physRow)), [
        (0, 0),
        (0, 1),
        (1, 0),
        (2, 0),
        (2, 1),
        (2, 2),
      ]);
    });
  });

  group('placeSequential', () {
    test('places a flat index in column-major order', () {
      expect((placeSequential(0, 6).physCol, placeSequential(0, 6).physRow), (0, 0));
      expect((placeSequential(5, 6).physCol, placeSequential(5, 6).physRow), (0, 5));
      expect((placeSequential(6, 6).physCol, placeSequential(6, 6).physRow), (1, 0));
    });
  });

  group('roundTo', () {
    test('rounds to the specified precision', () {
      expect(roundTo(1.00005, 1e-4), closeTo(1.0001, 1e-9));
      expect(roundTo(-2.55555, 1e-3), closeTo(-2.556, 1e-9));
      expect(roundTo(42, 1), 42);
    });
  });

  group('contentSize', () {
    test('returns width 0 for an empty cell list', () {
      final size = contentSize(const [], 6, 18);
      expect(size.width, 0);
      expect(size.height, 6 * 18);
    });

    test('computes total width from the maximum physical column', () {
      final placed = placeOnGrid([2, 1, 3], 6);
      final size = contentSize(placed, 6, 18);
      expect(size.width, 3 * 18); // max physCol=2 -> 3 columns
    });
  });
}
