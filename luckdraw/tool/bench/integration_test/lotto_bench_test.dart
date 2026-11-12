import 'package:flutter_test/flutter_test.dart';

import 'bench_support.dart';

/// 注册 lotto 的真机 profile 基准；禁止本机桌面执行。
void main() {
  final binding = benchBinding();
  group('bench', () {
    testWidgets('lotto 47 balls mixing and drawing', (tester) async {
      await runSteadyBench(binding, tester, 'lotto_draw');
    });
  });
}
