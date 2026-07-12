import 'package:flutter/material.dart';

/// Web-safe placeholder for [BenchmarkPage].
///
/// The real benchmark page (`benchmark_page.dart`) uses `dart:io`
/// (`ProcessInfo.currentRss`, `exit`) and the `stop_watch_timer` /
/// `slide_countdown` packages for profiling, none of which compile for the
/// web. `main.dart` conditionally imports this stub instead when `dart:io` is
/// unavailable, so the web demo still builds.
///
/// [BenchmarkPage] 的 web 安全占位。
///
/// 真正的基准页（`benchmark_page.dart`）用到 `dart:io`（`ProcessInfo.currentRss`、
/// `exit`）及性能对比用的三方包，均无法在 web 编译。`main.dart` 在无 `dart:io` 时
/// 条件导入本桩，使 web demo 仍可构建。
class BenchmarkPage extends StatelessWidget {
  const BenchmarkPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Benchmark')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'The A/B benchmark runs on desktop only\n'
            '(it uses dart:io for RSS sampling and process exit).\n\n'
            'Run it with:  flutter run --profile -d windows',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
