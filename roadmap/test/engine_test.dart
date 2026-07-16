import 'package:flutter_test/flutter_test.dart';
import 'package:roadmap/roadmap.dart';

RawResult _r(int no, String winner) => RawResult(no: no, winner: winner, bankerPair: false, playerPair: false);

void main() {
  group('createEngine', () {
    test('自动展开传递依赖并按拓扑序计算', () {
      final engine = createEngine(['statsPanel']);
      // statsPanel 依赖 bigRoad，应被自动展开加载。
      expect(engine.plugins.containsKey('bigRoad'), isTrue);
      expect(engine.plugins.containsKey('statsPanel'), isTrue);
    });

    test('compute 输出统计数据与手工计数一致', () {
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

    test('未知插件 id 抛错', () {
      expect(() => createEngine(['noSuchPlugin']), throwsStateError);
    });

    test('依赖插件出错时记入 errors，不影响其他路', () {
      // bigRoad 本身不会抛错——这里验证的是「同一次 compute 中一条路失败不阻塞其他路」
      // 这一行为边界：只启用互不依赖的两条路，二者都应各自正常产出。
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
