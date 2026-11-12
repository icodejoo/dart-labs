import 'package:flutter/material.dart';
import 'benchmark_page.dart';

export 'benchmark_panel_stub.dart' show BenchmarkUnavailable;

/// 原生平台支持进程内存和环境变量采样。
const nativeBenchmarkAvailable = true;

/// 用户点击开始后才挂载自动采集页。
Widget buildBenchmarkPanel() => const BenchmarkPage(autoStart: true);
