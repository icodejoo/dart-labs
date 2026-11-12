import 'package:flutter_test/flutter_test.dart';

import 'bench_support.dart';

/// 注册 number_wheel 的真机 profile 基准；禁止本机桌面执行。
void main() {
  final binding = benchBinding();
  group('bench', () {
    testWidgets('number wheel 37 pockets ball spin', (tester) async {
      await runSteadyBench(binding, tester, 'number_wheel_spin');
    });
  });
}
