import 'package:flutter_test/flutter_test.dart';

import 'bench_support.dart';

/// 注册 lots 的真机 profile 基准；禁止本机桌面执行。
void main() {
  final binding = benchBinding();
  group('bench', () {
    testWidgets('lots 12 sticks steady shake', (tester) async {
      await runSteadyBench(binding, tester, 'lots_shaking');
    });
  });
}
