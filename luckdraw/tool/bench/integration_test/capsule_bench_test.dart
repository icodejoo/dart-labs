import 'package:flutter_test/flutter_test.dart';

import 'bench_support.dart';

/// 注册 capsule 的真机 profile 基准；禁止本机桌面执行。
void main() {
  final binding = benchBinding();
  group('bench', () {
    testWidgets('capsule 30 capsules mixing', (tester) async {
      await runSteadyBench(binding, tester, 'capsule_mixing');
    });
  });
}
