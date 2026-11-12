import 'package:flutter/material.dart';
import 'benchmark_page.dart';
import 'digit_test_page.dart';
import 'perf_page.dart';
import 'stress_page.dart';

/// 保留命名路由和自动采集的原生脚本入口。
Widget buildBenchApp(String initialRoute) => MaterialApp(
  debugShowCheckedModeBanner: false,
  initialRoute: initialRoute == '/' ? '/benchmark' : initialRoute,
  routes: {
    '/': (_) => const BenchmarkPage(autoStart: true, scripted: true),
    '/benchmark': (_) => const BenchmarkPage(autoStart: true, scripted: true),
    '/perf': (_) => const Scaffold(body: PerfPage()),
    '/digit-test': (_) => const Scaffold(body: DigitTestPage()),
    '/stress': (_) => const Scaffold(body: StressPage()),
  },
);
