import 'package:countman/countman.dart';
import 'package:flutter/material.dart';
import 'demo_kit/demo_kit.dart';
import 'demo_samples.dart';
import 'perf_page.dart' show movingFormatter;

/// 压测的目标值：九位全 9，覆盖低位快速翻滚的最坏情况。
const double _stressTarget = 999999999;

/// 压测的单次动画时长。
const Duration _stressDuration = Duration(seconds: 10);

/// 每个玩法并发的实例数。
const int _instancesPerGroup = 5;

/// 千分位格式，全部玩法共用。
const CounterFormat _stressFormat = CounterFormat(thousandSeparator: ',');

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

  /// 让所有实例同时从 0 重新开始。
  void _restartAll() => setState(() => _generation++);

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
          for (var i = 1; i <= _instancesPerGroup; i++)
            DemoGridItem(
              child: DemoCard(
                title: '$title #$i',
                description: tr(
                  context,
                  '0 → 999,999,999 in 10 s. Replay restarts only this instance.',
                  '10 秒内 0 → 999,999,999；重播只重启这一个实例。',
                ),
                child: _FromZero(builder: builder),
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
      'Run many counters at once from 0 to 999,999,999. Replay one, or restart all.',
      '同时运行多个计数器，从 0 到 999,999,999；可单个重播，也可全部重来。',
    ),
    sections: [
      DemoSection(
        title: tr(context, 'Run all', '全部运行'),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _restartAll,
            icon: const Icon(Icons.replay_rounded),
            label: Text(tr(context, 'Restart all', '全部重来')),
          ),
        ),
      ),
      _group(
        'AnimatedCounter · roll',
        (v) => AnimatedCounter(
          value: v,
          format: _stressFormat,
          timeline: const CounterTimeline(
            duration: _stressDuration,
            curve: Curves.linear,
          ),
          style: const AnimatedCounterStyle(textStyle: demoNumberStyle),
        ),
      ),
      _group(
        'AnimatedCounter · flip',
        (v) => AnimatedCounter(
          value: v,
          transition: CounterTransition.flip,
          format: _stressFormat,
          timeline: const CounterTimeline(
            duration: _stressDuration,
            curve: Curves.linear,
          ),
          style: const AnimatedCounterStyle(textStyle: demoNumberStyle),
        ),
      ),
      _group(
        'AnimatedCounter · blur',
        (v) => AnimatedCounter(
          value: v,
          transition: CounterTransition.slideBlur,
          format: _stressFormat,
          timeline: const CounterTimeline(
            duration: _stressDuration,
            curve: Curves.linear,
          ),
          style: const AnimatedCounterStyle(textStyle: demoNumberStyle),
        ),
      ),
      _group(
        'AnimatedCounter · stagger',
        (v) => AnimatedCounter(
          value: v,
          format: _stressFormat,
          timeline: const CounterTimeline(
            duration: _stressDuration,
            curve: Curves.linear,
            staggerDelay: Duration(milliseconds: 80),
          ),
          style: const AnimatedCounterStyle(textStyle: demoNumberStyle),
        ),
      ),
      _group(
        'OdometerCounter',
        (v) => OdometerCounter(
          to: v,
          duration: _stressDuration,
          curve: Curves.linear,
          groupSeparator: ',',
          style: const OdometerCounterStyle(numberTextStyle: demoNumberStyle),
        ),
      ),
      _group(
        'TextCounter',
        (v) => TextCounter(
          to: v,
          duration: _stressDuration,
          curve: Curves.linear,
          formatter: movingFormatter(
            v,
            v / (_stressDuration.inMilliseconds / 16.667),
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
  const _FromZero({required this.builder});

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _value = _stressTarget);
    });
  }

  /// 以当前值构建计数器。
  @override
  Widget build(BuildContext context) => widget.builder(_value);
}
