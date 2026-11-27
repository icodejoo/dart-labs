import 'package:flutter_test/flutter_test.dart';

import 'repro.dart';

/// Reproduces analytic edge stepping in flutter_tester. / 在 flutter_tester 中复现解析式边缘步进。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Skia CPU changes coverage for convex paths and shared scan rows',
    () async {
      final result = await scanConversionCases();
      expect(result['convexSeparateRows']!.maxDelta, greaterThan(1));
      expect(result['concaveSameRows']!.maxDelta, greaterThan(1));
      expect(result['concaveSeparateRows'], (maxDelta: 0, changedPixels: 0));
    },
  );
}
