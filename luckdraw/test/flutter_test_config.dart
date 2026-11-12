import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'support/fonts.dart';
import 'support/golden_comparator.dart';

/// 全局测试配置：显式加载 SDK Roboto 并注册容差比较器。
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadLuckyTestFonts();
  if (goldenFileComparator is LocalFileComparator) {
    goldenFileComparator = LuckyToleranceComparator.fromLocal(
        goldenFileComparator as LocalFileComparator);
  }
  await testMain();
}
