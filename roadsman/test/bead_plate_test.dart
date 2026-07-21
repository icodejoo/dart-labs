/// Bead plate spec-driven behavior test: the same plugin produces different colors and
/// text depending on whether the baccarat or roulette game spec is in effect.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:roadsman/roadsman.dart';

RawResult _r(int no, String winner, {bool bp = false, bool pp = false}) =>
    RawResult(no: no, winner: winner, bankerPair: bp, playerPair: pp);

/// Gets the fill of the first CircleCommand among a cell's draw commands.
int? _fillOf(LayoutCell cell) =>
    cell.commands.whereType<CircleCommand>().first.fill;

/// Gets the text of the BadgeCommand among a cell's draw commands.
String _textOf(LayoutCell cell) =>
    cell.commands.whereType<BadgeCommand>().first.text;

void main() {
  final theme = resolveTheme();
  final cfg = LayoutConfig(cellSize: 18, rows: 6, theme: theme);

  group('BeadPlate spec 驱动', () {
    test('百家乐：颜色/文字与规格 paletteKey/label 一致，行为与硬编码时代相同', () {
      final engine = createEngine(['beadPlate']);
      final output = engine.compute([_r(1, 'B', bp: true), _r(2, 'P'), _r(3, 'T')], cfg);
      final cells = output.layouts['beadPlate']!.cells;

      expect(_fillOf(cells[0]), theme.palette.banker);
      expect(_fillOf(cells[1]), theme.palette.player);
      expect(_fillOf(cells[2]), theme.palette.tie);
      expect(_textOf(cells[0]), theme.labels.banker);
      expect(_textOf(cells[1]), theme.labels.player);
      expect(_textOf(cells[2]), theme.labels.tie);

      // The banker-pair corner marker is still produced (via the generalized spec.markers path).
      expect(cells[0].commands.whereType<DotCommand>(), hasLength(1));
      expect(cells[1].commands.whereType<DotCommand>(), isEmpty);
    });

    test('轮盘：号码文字 + 红/黑/绿取色，零改一行渲染代码', () {
      final engine = createEngine(['beadPlate'], spec: rouletteSpec);
      final output = engine.compute([_r(1, '0'), _r(2, '32'), _r(3, '17')], cfg);
      final cells = output.layouts['beadPlate']!.cells;

      expect(_textOf(cells[0]), '0');
      expect(_textOf(cells[1]), '32');
      expect(_textOf(cells[2]), '17');
      expect(_fillOf(cells[0]), theme.palette.tie); // 0 is green
      expect(_fillOf(cells[1]), theme.palette.red); // 32 is red
      expect(_fillOf(cells[2]), theme.palette.blue); // 17 is black (defaults to the blue slot)
    });

    test('主题 palette.outcomes 覆盖单个号码颜色（外部可配，不改规格）', () {
      final custom = resolveTheme(
        palette: (p) => p.copyWith(outcomes: {...?p.outcomes, '17': 0xFF212121}),
      );
      final engine = createEngine(['beadPlate'], spec: rouletteSpec);
      final output = engine.compute(
        [_r(1, '17')],
        LayoutConfig(cellSize: 18, rows: 6, theme: custom),
      );
      expect(_fillOf(output.layouts['beadPlate']!.cells[0]), 0xFF212121);
    });

    test('colorForPaletteKey：自定义键回落 palette.outcomes，未知键回落 blue', () {
      final custom = resolveTheme(
        palette: (p) => p.copyWith(outcomes: {...?p.outcomes, 'gold': 0xFFFFD700}),
      );
      expect(colorForPaletteKey('gold', custom), 0xFFFFD700);
      expect(colorForPaletteKey('nope', theme), theme.palette.blue);
      expect(colorForPaletteKey('banker', theme), theme.palette.banker);
    });
  });
}
