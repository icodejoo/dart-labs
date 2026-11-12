import 'package:countman/countman.dart';
import 'package:flutter/material.dart';
import 'demo_kit/demo_kit.dart';

/// 九位全 9 的大跨度计数目标。
const double benchmarkTarget = 999999999;

/// 大跨度动画的单轮时长。
const benchmarkDuration = Duration(seconds: 10);

/// 每种效果并发运行的实例数。
const benchmarkInstances = 5;

/// 共用千分位分隔符。
const benchmarkSeparator = ',';

/// 共用大跨度计数格式。
const benchmarkFormat = CounterFormat(thousandSeparator: benchmarkSeparator);

/// 估算低位扰动步长时采用的名义帧间隔。
const benchmarkFrameMs = 16.667;

/// 压测页面共用的双语按钮标签。
abstract final class BenchmarkLabels {
  /// 开始或重新开始一轮运行。
  static String start(BuildContext context) =>
      tr(context, 'Start / restart', '开始 / 重来');

  /// 停止并卸载运行中的实例。
  static String stop(BuildContext context) => tr(context, 'Stop', '停止');

  /// 反向归零的按钮标签。
  static String reset(BuildContext context) => tr(context, 'Reset', '归零');
}

/// 说明浏览器数字的适用范围。
class BenchmarkNotice extends StatelessWidget {
  /// 创建各压测页面共用的提示。
  const BenchmarkNotice({super.key});

  /// 根据当前语言展示基准测试说明。
  @override
  Widget build(BuildContext context) => InfoNote(
    text: tr(
      context,
      'Browser numbers are for reference only. Use desktop or a real device in profile mode for real benchmarks.',
      '浏览器里的数字仅供参考，真实基准请用桌面 / 真机 profile 模式。',
    ),
    kind: InfoNoteKind.warning,
  );
}
