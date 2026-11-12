import 'package:flutter/material.dart';
import 'benchmark_page.dart';
import 'digit_test_page.dart';
import 'perf_page.dart';

/// 原生基准入口，与公开演示的页面骨架完全隔离。
Widget buildBenchApp(String initialRoute) => MaterialApp(
  debugShowCheckedModeBanner: false,
  initialRoute: initialRoute == '/' ? '/benchmark' : initialRoute,
  routes: {
    '/': (_) => const BenchmarkPage(),
    '/benchmark': (_) => const BenchmarkPage(),
    '/perf': (_) => const PerfPage(),
    '/digit-test': (_) => const DigitTestPage(),
  },
);
