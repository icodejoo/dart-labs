import 'package:flutter/material.dart';
import 'package:countman/countman.dart';
import 'benchmark_common.dart';
import 'demo_kit/demo_kit.dart';

/// 大跨度快速计数用的 formatter：仅打散低位，结尾精确落在 [target]。
///
/// 供压测页复用；参数 [step] 为每帧步长。
String Function(double) movingFormatter(double target, double step) =>
    _PerfPageState._movingFormatter(target, step);

/// 六种效果各五个计数器的大跨度性能对照页。
class PerfPage extends StatefulWidget {
  /// 创建手动启动的性能对照页。
  const PerfPage({super.key});

  /// 创建计数目标与运行状态。
  @override
  State<PerfPage> createState() => _PerfPageState();
}

/// 持有目标值和用于立即停止的挂载代次。
class _PerfPageState extends State<PerfPage> {
  /// 当前计数目标。
  double _value = 0;

  /// 停止时更换子树以立即清除动画。
  int _generation = 0;

  /// 切换目标，运行全部六组计数器。
  void _start() {
    setState(() {
      _value = 0;
      _generation++;
    });
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _generation) {
        setState(() => _value = benchmarkTarget);
      }
    });
  }

  /// 保留原有反向归零效果。
  void _reset() => setState(() => _value = 0);

  /// 立即停止并挂载静止的零值实例。
  void _stop() => setState(() {
    _value = 0;
    _generation++;
  });

  /// 黑色演示区域的数字样式。
  // Explicit white: the page forces a black background, so relying on the
  // theme's default text color makes digits invisible under a light theme.
  //
  // 显式白色：本页强制黑底，若依赖主题默认文字色，浅色主题下数字会看不见。
  static const _ts = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );

  /// 构建统一骨架、显式控件与黑底性能对照区。
  @override
  Widget build(BuildContext context) => DemoPage(
    title: tr(context, 'Performance', '性能对照'),
    description: tr(
      context,
      'Six effects, five counters each: 0 → 999,999,999 in 10 s. Start, reverse to zero, or stop immediately.',
      '六种效果各五个实例：10 秒内 0 → 999,999,999；可开始、反向归零或立即停止。',
    ),
    sections: [
      const BenchmarkNotice(),
      Wrap(
        spacing: DemoTokens.gap,
        runSpacing: DemoTokens.smallGap,
        children: [
          FilledButton(
            onPressed: _start,
            child: Text(BenchmarkLabels.start(context)),
          ),
          OutlinedButton(
            onPressed: _reset,
            child: Text(BenchmarkLabels.reset(context)),
          ),
          OutlinedButton(
            onPressed: _stop,
            child: Text(BenchmarkLabels.stop(context)),
          ),
        ],
      ),
      ColoredBox(
        color: Colors.black,
        child: Padding(
          padding: const EdgeInsets.all(DemoTokens.padding),
          child: KeyedSubtree(
            key: ValueKey(_generation),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _group(
                  tr(
                    context,
                    'AnimatedCounter — roll (default)',
                    'AnimatedCounter — 默认滚动',
                  ),
                  [
                    for (var i = 0; i < benchmarkInstances; i++)
                      AnimatedCounter(
                        value: _value,
                        format: benchmarkFormat,
                        timeline: const CounterTimeline(
                          duration: benchmarkDuration,
                          curve: Curves.linear,
                        ),
                        style: const AnimatedCounterStyle(textStyle: _ts),
                      ),
                  ],
                ),
                _group(
                  tr(context, 'AnimatedCounter — flip', 'AnimatedCounter — 翻转'),
                  [
                    for (var i = 0; i < benchmarkInstances; i++)
                      AnimatedCounter(
                        value: _value,
                        transition: CounterTransition.flip,
                        format: benchmarkFormat,
                        timeline: const CounterTimeline(
                          duration: benchmarkDuration,
                          curve: Curves.linear,
                        ),
                        style: const AnimatedCounterStyle(textStyle: _ts),
                      ),
                  ],
                ),
                _group(
                  tr(
                    context,
                    'AnimatedCounter — blur',
                    'AnimatedCounter — 模糊滑动',
                  ),
                  [
                    for (var i = 0; i < benchmarkInstances; i++)
                      AnimatedCounter(
                        value: _value,
                        transition: CounterTransition.slideBlur,
                        format: benchmarkFormat,
                        timeline: const CounterTimeline(
                          duration: benchmarkDuration,
                          curve: Curves.linear,
                        ),
                        style: const AnimatedCounterStyle(textStyle: _ts),
                      ),
                  ],
                ),
                _group(
                  tr(
                    context,
                    'AnimatedCounter — stagger',
                    'AnimatedCounter — 交错',
                  ),
                  [
                    for (var i = 0; i < benchmarkInstances; i++)
                      AnimatedCounter(
                        value: _value,
                        format: benchmarkFormat,
                        timeline: const CounterTimeline(
                          duration: benchmarkDuration,
                          curve: Curves.linear,
                          staggerDelay: Duration(milliseconds: 80),
                        ),
                        style: const AnimatedCounterStyle(textStyle: _ts),
                      ),
                  ],
                ),
                _group(
                  tr(context, 'OdometerCounter', 'OdometerCounter · 里程表'),
                  [
                    for (var i = 0; i < benchmarkInstances; i++)
                      OdometerCounter(
                        to: _value,
                        duration: benchmarkDuration,
                        curve: Curves.linear,
                        style: const OdometerCounterStyle(numberTextStyle: _ts),
                        groupSeparator: benchmarkSeparator,
                      ),
                  ],
                ),
                _group(tr(context, 'TextCounter', 'TextCounter · 文本'), [
                  for (var i = 0; i < benchmarkInstances; i++)
                    TextCounter(
                      to: _value,
                      duration: benchmarkDuration,
                      curve: Curves.linear,
                      formatter: _movingFormatter(
                        _value,
                        _value /
                            (benchmarkDuration.inMilliseconds /
                                benchmarkFrameMs),
                      ),
                      style: const TextCounterStyle(textStyle: _ts),
                    ),
                ]),
              ],
            ),
          ),
        ),
      ),
    ],
  );

  /// A truthful-where-readable `formatter` for a huge fast count: each frame it
  /// shows `trueValue − rand[0, step)`. The subtraction is smaller than one
  /// per-frame step, so it only scrambles the fast-blurring LOW digits (which
  /// are unreadable at this rate anyway) while leaving the readable HIGH digits
  /// (above the step magnitude) equal to the true value. The number therefore
  /// keeps every column moving instead of freezing, and lands EXACTLY on the
  /// true target at the end ("最后回填"). Deterministic LCG — no platform RNG.
  ///
  /// 「可读处为真」的大跨度快速计数 formatter：每帧显示 `真值 − rand[0, step)`。
  /// 减量小于一帧步长,故只打散快速模糊的低位(该速率下本就读不清),而高于步长量级的
  /// 可读高位仍等于真值。于是每一列都在动而非冻结,并在结尾精确落到真实目标(最后回填)。
  /// 确定性 LCG,不用平台随机。
  static String Function(double) _movingFormatter(double target, double step) {
    var seed = 0x2545F491;
    final tgt = target.round();
    final st = step.round().clamp(1, 1 << 30);
    // Only engage for an all-nines target of ≥ 5 digits (99999, 999999, …).
    // That's the pathological case where floor-borrow freezes the low digits;
    // any other target already animates truthfully, so leave it exact.
    //
    // 仅对 ≥ 5 位的全 9 目标（99999、999999…）生效——这是 floor 借位导致低位冻结的
    // 病态场景；其他目标本就真实滚动，保持精确。
    final bool applies = _allNinesAtLeast5(tgt);
    return (v) {
      final iv = v.round();
      if (!applies || iv >= tgt || iv <= 0) return '$iv'; // exact true value
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      final disp =
          iv - (seed % st); // subtract < one step → high digits stay true
      return '${disp < 0 ? 0 : disp}';
    };
  }

  /// True iff [n] is all nines with at least 5 digits (99999, 999999, …).
  ///
  /// [n] 为至少 5 位的全 9（99999、999999…）时为真。
  static bool _allNinesAtLeast5(int n) {
    if (n < 99999) return false;
    var m = n + 1;
    while (m % 10 == 0) {
      m ~/= 10;
    }
    return m == 1;
  }

  /// 平铺一组同类计数器，保持全部实例挂载。
  Widget _group(String title, List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.grey,
            letterSpacing: 0.8,
          ),
        ),
      ),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: children
            .map(
              (w) => Card(
                color: Colors.grey[900],
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: w,
                ),
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 8),
    ],
  );
}
