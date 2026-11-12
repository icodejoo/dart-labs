import 'package:flutter/material.dart';
import 'demo_kit/demo_kit.dart';

/// 当前编译平台是否支持原生进程基准。
const nativeBenchmarkAvailable = false;

/// Web 不挂载依赖 dart:io 的基准页面。
Widget buildBenchmarkPanel() => const SizedBox.shrink();

/// Web 平台的双语降级说明。
class BenchmarkUnavailable extends StatelessWidget {
  /// 创建不可用说明。
  const BenchmarkUnavailable({super.key});

  /// 显示原生运行要求。
  @override
  Widget build(BuildContext context) => InfoNote(
    text: tr(context, 'This page requires a native desktop app.', '该页需桌面原生运行'),
  );
}
