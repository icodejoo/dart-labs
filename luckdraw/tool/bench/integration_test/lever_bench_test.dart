import 'package:flutter_test/flutter_test.dart';

import 'bench_support.dart';

/// 注册真实拉霸机页面，使用与三列老虎机一致的保守预算。
void main() {
  final binding = benchBinding();
  group('bench', () {
    testWidgets('lever 3 reels 10 prizes steady scroll', (tester) async {
      await runSteadyBench(binding, tester, 'lever_steady');
    });
  });
}
