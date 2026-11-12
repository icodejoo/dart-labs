import 'package:flutter_test/flutter_test.dart';

import 'bench_support.dart';

/// 注册 wheel 的真机 profile 基准；禁止本机桌面执行。
void main() {
  final binding = benchBinding();
  group('bench', () {
    testWidgets('wheel 12 prizes steady spin', (tester) async {
      await runSteadyBench(binding, tester, 'wheel_steady');
    });
    testWidgets('wheel first frame layout and record time', (tester) async {
      await runFirstFrameBench(binding, tester);
    });
  });
}
