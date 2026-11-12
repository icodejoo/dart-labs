import 'package:flutter_test/flutter_test.dart';

import 'bench_support.dart';

/// 注册 slot 的真机 profile 基准；禁止本机桌面执行。
void main() {
  final binding = benchBinding();
  group('bench', () {
    testWidgets('slot 3 reels 10 prizes steady scroll', (tester) async {
      await runSteadyBench(binding, tester, 'slot_steady');
    });
    testWidgets('slot 3 reels 10 prizes raster scroll', (tester) async {
      await runSteadyBench(binding, tester, 'slot_raster');
    });
  });
}
