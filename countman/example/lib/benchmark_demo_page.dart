import 'package:flutter/material.dart';
import 'benchmark_common.dart';
import 'benchmark_panel_stub.dart'
    if (dart.library.io) 'benchmark_panel_native.dart';
import 'demo_kit/demo_kit.dart';

/// 公开导航中的原生基准入口；Web 仅显示运行要求。
class BenchmarkDemoPage extends StatefulWidget {
  /// 创建基准说明与手动运行面板。
  const BenchmarkDemoPage({super.key});

  /// 创建显式启动和停止状态。
  @override
  State<BenchmarkDemoPage> createState() => _BenchmarkDemoPageState();
}

/// 通过挂载和卸载控制基准生命周期。
class _BenchmarkDemoPageState extends State<BenchmarkDemoPage> {
  /// 是否已由用户显式启动。
  bool _running = false;

  /// 在开始与停止时更新运行状态。
  void _setRunning(bool running) => setState(() => _running = running);

  /// 构建统一骨架与平台适配内容。
  @override
  Widget build(BuildContext context) => DemoPage(
    title: tr(context, 'Native benchmark', '原生基准'),
    description: tr(
      context,
      'Compare 50 concurrent countdowns across libraries: frame timings, FPS and process RSS. Start manually in a native desktop app.',
      '对比不同库的 50 个并发倒计时：帧耗时、FPS 与进程 RSS；请在桌面原生应用中手动开始。',
    ),
    sections: [
      const BenchmarkNotice(),
      if (!nativeBenchmarkAvailable)
        const BenchmarkUnavailable()
      else ...[
        Wrap(
          spacing: DemoTokens.gap,
          runSpacing: DemoTokens.smallGap,
          children: [
            FilledButton(
              onPressed: _running ? null : () => _setRunning(true),
              child: Text(BenchmarkLabels.start(context)),
            ),
            OutlinedButton(
              onPressed: _running ? () => _setRunning(false) : null,
              child: Text(BenchmarkLabels.stop(context)),
            ),
          ],
        ),
        if (_running)
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 1440,
              height: 1000,
              child: buildBenchmarkPanel(),
            ),
          ),
      ],
    ],
  );
}
