import 'package:flutter_test/flutter_test.dart';
import 'package:roadsman/roadsman.dart';

LayoutCell _cell(String key, double x, double y) => LayoutCell(
  key: key,
  x: x,
  y: y,
  w: 18,
  h: 18,
  resultNo: 1,
  commands: [CircleCommand(x: x + 9, y: y + 9, r: 7)],
);

void main() {
  group('diffLayout', () {
    test('returns empty transitions when prev is null (first frame goes straight to final state)', () {
      final next = RoadLayout(cells: [_cell('0:0', 0, 0)], contentWidth: 18, contentHeight: 108);
      expect(diffLayout(null, next), isEmpty);
    });

    test('a new key produces an enter transition', () {
      final prev = RoadLayout(cells: [_cell('0:0', 0, 0)], contentWidth: 18, contentHeight: 108);
      final next = RoadLayout(
        cells: [_cell('0:0', 0, 0), _cell('0:1', 0, 18)],
        contentWidth: 18,
        contentHeight: 108,
      );
      final transitions = diffLayout(prev, next);
      expect(transitions.whereType<EnterTransition>(), hasLength(1));
      expect((transitions.whereType<EnterTransition>().first).cell.key, '0:1');
    });

    test('a position change on the same key produces a move transition', () {
      final prev = RoadLayout(cells: [_cell('a', 0, 0)], contentWidth: 18, contentHeight: 108);
      final next = RoadLayout(cells: [_cell('a', 18, 0)], contentWidth: 36, contentHeight: 108);
      final transitions = diffLayout(prev, next);
      expect(transitions.whereType<MoveTransition>(), hasLength(1));
    });

    test('a disappearing key produces an exit transition', () {
      final prev = RoadLayout(
        cells: [_cell('a', 0, 0), _cell('b', 18, 0)],
        contentWidth: 36,
        contentHeight: 108,
      );
      final next = RoadLayout(cells: [_cell('a', 0, 0)], contentWidth: 18, contentHeight: 108);
      final transitions = diffLayout(prev, next);
      expect(transitions.whereType<ExitTransition>(), hasLength(1));
      expect((transitions.whereType<ExitTransition>().first).cell.key, 'b');
    });
  });

  group('sampling functions', () {
    test('sampleEnter(fadeIn) sets alpha based on progress', () {
      final cell = _cell('a', 0, 0);
      final cmds = sampleEnter('fadeIn', cell, 0.5);
      expect(cmds.single.alpha, 0.5);
    });

    test('sampleExit(fadeOut) is fully transparent and shifted left at progress=1', () {
      final cell = _cell('a', 0, 0);
      final cmds = sampleExit('fadeOut', cell, 1, 18);
      expect(cmds.single.alpha, 0);
    });

    test('translateCommands shifts all command coordinates', () {
      final cmds = [const CircleCommand(x: 0, y: 0, r: 5)];
      final shifted = translateCommands(cmds, 10, 20);
      final c = shifted.single as CircleCommand;
      expect(c.x, 10);
      expect(c.y, 20);
    });
  });

  group('applyWindow', () {
    test('keeps the most recent N columns and shifts left, contentWidth becomes windowCols*cellSize', () {
      final cells = List.generate(5, (i) => _cell('$i', i * 18.0, 0));
      final layout = RoadLayout(cells: cells, contentWidth: 5 * 18, contentHeight: 108);
      final windowed = applyWindow(layout, 3, 18);
      expect(windowed.contentWidth, 3 * 18);
      expect(windowed.cells, hasLength(3));
      expect(windowed.cells.first.x, 0);
    });
  });
}
