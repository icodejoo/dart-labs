import 'package:countman/countman.dart';
import 'package:flutter/material.dart';
import 'demo_kit/demo_kit.dart';
import 'demo_samples.dart';
import 'benchmark_common.dart';
import 'perf_page.dart' show movingFormatter;

/// 并发压测页：每种玩法同时跑多个实例，每个实例可单独重播。
class StressPage extends StatefulWidget {
  /// 创建压测页。
  const StressPage({super.key});

  /// 创建全部重播状态。
  @override
  State<StressPage> createState() => _StressPageState();
}

/// 持有「全部重播」的代次，换 Key 即重新挂载所有实例。
class _StressPageState extends State<StressPage> {
  /// 全部重播的代次。
  int _generation = 0;

  /// 是否允许挂载实例开始动画。
  bool _running = false;

  /// 让所有实例同时从 0 重新开始。
  void _restartAll() => setState(() {
    _running = true;
    _generation++;
  });

  /// 卸载运行中的实例，归零时不反向播放。
  void _stopAll() => setState(() {
    _running = false;
    _generation++;
  });

  /// 构建一个玩法分组：并发的实例各占一张可重播卡片。
  DemoSection _group(
    String title,
    Widget Function(double value) builder,
  ) => DemoSection(
    title: title,
    child: KeyedSubtree(
      key: ValueKey('$title/$_generation'),
      child: DemoGrid(
        children: [
          for (var i = 1; i <= benchmarkInstances; i++)
            DemoGridItem(
              child: DemoCard(
                title: '$title #$i',
                description: tr(
                  context,
                  '0 → 999,999,999 in 10 s. Replay restarts only this instance.',
                  '10 秒内 0 → 999,999,999；重播只重启这一个实例。',
                ),
                replayable: _running,
                child: _FromZero(active: _running, builder: builder),
              ),
            ),
        ],
      ),
    ),
  );

  /// 构建控制区与五组并发实例。
  @override
  Widget build(BuildContext context) => DemoPage(
    title: tr(context, 'Stress test', '并发压测'),
    description: tr(
      context,
      'Manually run 30 counters from 0 to 999,999,999. Replay one, restart all, or stop.',
      '手动启动 30 个计数器，从 0 到 999,999,999；可单个重播、全部重来或停止。',
    ),
    sections: [
      const BenchmarkNotice(),
      DemoSection(
        title: tr(context, 'Run all', '全部运行'),
        child: Wrap(
          spacing: DemoTokens.gap,
          runSpacing: DemoTokens.smallGap,
          children: [
            FilledButton.icon(
              onPressed: _restartAll,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(BenchmarkLabels.start(context)),
            ),
            OutlinedButton(
              onPressed: _running ? _stopAll : null,
              child: Text(BenchmarkLabels.stop(context)),
            ),
          ],
        ),
      ),
      _group(
        tr(context, 'AnimatedCounter · roll', 'AnimatedCounter · 滚动'),
        (v) => AnimatedCounter(
          value: v,
          format: benchmarkFormat,
          timeline: const CounterTimeline(
            duration: benchmarkDuration,
            curve: Curves.linear,
          ),
          style: const AnimatedCounterStyle(textStyle: demoNumberStyle),
        ),
      ),
      _group(
        tr(context, 'AnimatedCounter · flip', 'AnimatedCounter · 翻转'),
        (v) => AnimatedCounter(
          value: v,
          transition: CounterTransition.flip,
          format: benchmarkFormat,
          timeline: const CounterTimeline(
            duration: benchmarkDuration,
            curve: Curves.linear,
          ),
          style: const AnimatedCounterStyle(textStyle: demoNumberStyle),
        ),
      ),
      _group(
        tr(context, 'AnimatedCounter · blur', 'AnimatedCounter · 模糊滑动'),
        (v) => AnimatedCounter(
          value: v,
          transition: CounterTransition.slideBlur,
          format: benchmarkFormat,
          timeline: const CounterTimeline(
            duration: benchmarkDuration,
            curve: Curves.linear,
          ),
          style: const AnimatedCounterStyle(textStyle: demoNumberStyle),
        ),
      ),
      _group(
        tr(context, 'AnimatedCounter · stagger', 'AnimatedCounter · 交错'),
        (v) => AnimatedCounter(
          value: v,
          format: benchmarkFormat,
          timeline: const CounterTimeline(
            duration: benchmarkDuration,
            curve: Curves.linear,
            staggerDelay: Duration(milliseconds: 80),
          ),
          style: const AnimatedCounterStyle(textStyle: demoNumberStyle),
        ),
      ),
      _group(
        tr(context, 'OdometerCounter · odometer', 'OdometerCounter · 里程表'),
        (v) => OdometerCounter(
          to: v,
          duration: benchmarkDuration,
          curve: Curves.linear,
          groupSeparator: benchmarkSeparator,
          style: const OdometerCounterStyle(numberTextStyle: demoNumberStyle),
        ),
      ),
      _group(
        tr(context, 'TextCounter · text', 'TextCounter · 文本'),
        (v) => TextCounter(
          to: v,
          duration: benchmarkDuration,
          curve: Curves.linear,
          formatter: movingFormatter(
            v,
            v / (benchmarkDuration.inMilliseconds / benchmarkFrameMs),
          ),
          style: const TextCounterStyle(textStyle: demoNumberStyle),
        ),
      ),
    ],
  );
}

/// 挂载时先以 0 渲染，下一帧再切到压测目标，使每次挂载都从 0 重播。
class _FromZero extends StatefulWidget {
  /// 创建从 0 起跑的包装，[builder] 接收当前目标值。
  const _FromZero({required this.active, required this.builder});

  /// 用户已启动本轮时才允许首帧后切换目标。
  final bool active;

  /// 按当前值构建被压测的计数器。
  final Widget Function(double value) builder;

  /// 创建起跑状态。
  @override
  State<_FromZero> createState() => _FromZeroState();
}

/// 首帧后把值从 0 切到目标，触发一次完整动画。
class _FromZeroState extends State<_FromZero> {
  /// 当前交给计数器的值。
  double _value = 0;

  /// 首帧后启动动画。
  @override
  void initState() {
    super.initState();
    if (!widget.active) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _value = benchmarkTarget);
    });
  }

  /// 以当前值构建计数器。
  @override
  Widget build(BuildContext context) => widget.builder(_value);
}
