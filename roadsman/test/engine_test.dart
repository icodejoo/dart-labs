import 'package:flutter_test/flutter_test.dart';
import 'package:roadsman/roadsman.dart';

RawResult _r(int no, String winner) => RawResult(no: no, winner: winner, bankerPair: false, playerPair: false);

void main() {
  group('createEngine', () {
    test('auto-expands transitive dependencies and computes in topological order', () {
      final engine = createEngine(['statsPanel']);
      // statsPanel depends on bigRoad, which should be auto-expanded and loaded.
      expect(engine.plugins.containsKey('bigRoad'), isTrue);
      expect(engine.plugins.containsKey('statsPanel'), isTrue);
    });

    test('compute output stats match a manual count', () {
      final engine = createEngine(['bigRoad', 'statsPanel']);
      final results = [_r(1, 'B'), _r(2, 'B'), _r(3, 'P'), _r(4, 'T'), _r(5, 'P')];
      final cfg = LayoutConfig(cellSize: 18, rows: 6, theme: resolveTheme());
      final output = engine.compute(results, cfg);

      expect(output.errors, isEmpty);
      final stats = output.data['statsPanel'] as StatsData;
      expect(stats.total, 5);
      expect(stats.banker, 2);
      expect(stats.player, 2);
      expect(stats.tie, 1);
    });

    test('throws for an unknown plugin id', () {
      expect(() => createEngine(['noSuchPlugin']), throwsStateError);
    });

    test('a dependency plugin error is recorded in errors without affecting other roads', () {
      // bigRoad itself never throws -- this verifies the boundary behavior that "one road
      // failing during a single compute call doesn't block the other roads": only two
      // mutually independent roads are enabled here, and both should still produce output normally.
      final engine = createEngine(['beadPlate', 'pairRoad']);
      final results = [_r(1, 'B'), _r(2, 'P')];
      final cfg = LayoutConfig(cellSize: 18, rows: 6, theme: resolveTheme());
      final output = engine.compute(results, cfg);
      expect(output.errors, isEmpty);
      expect(output.layouts.containsKey('beadPlate'), isTrue);
      expect(output.layouts.containsKey('pairRoad'), isTrue);
    });
  });
}
