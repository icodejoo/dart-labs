import 'package:flutter_test/flutter_test.dart';

import 'bench_support.dart';

/// 注册 grid 的真机 profile 基准；禁止本机桌面执行。
void main() {
  final binding = benchBinding();
  group('bench', () {
    testWidgets('grid 3x3 steady walk', (tester) async {
      await runSteadyBench(binding, tester, 'grid_steady');
    });
  });
}
