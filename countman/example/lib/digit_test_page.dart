import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:countman/countman.dart';
import 'benchmark_common.dart';
import 'demo_kit/demo_kit.dart';

/// 手动检查数字递增、递减与逐帧分解日志。
class DigitTestPage extends StatefulWidget {
  /// 创建数字诊断页。
  const DigitTestPage({super.key});

  /// 创建数值与日志状态。
  @override
  State<DigitTestPage> createState() => _DigitTestPageState();
}

/// 持有诊断方向、计数目标和有限帧日志。
class _DigitTestPageState extends State<DigitTestPage> {
  /// 当前诊断目标。
  double _value = 0;

  /// 当前是否反向归零。
  bool _decreasing = false;

  /// 最多保留一轮有限帧日志。
  final _logs = <String>[];

  /// 本轮已记录帧数。
  int _frameCount = 0;

  /// 停止时更换子树以清除计数动画。
  int _generation = 0;

  /// 是否正在记录本轮更新。
  bool _recording = false;

  /// 诊断动画的原有时长。
  static const _duration = Duration(seconds: 3);

  /// 每轮帧日志的上限。
  static const _maxLog = 30;

  /// 启动原有 0 → 99 的数字诊断。
  void _start() {
    setState(() {
      _value = 0;
      _generation++;
      _decreasing = false;
      _recording = true;
      _logs.clear();
      _frameCount = 0;
    });
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _generation) setState(() => _value = 99);
    });
  }

  /// 反向归零并重新记录日志。
  void _reset() {
    setState(() {
      _value = 0;
      _decreasing = true;
      _recording = true;
      _logs.clear();
      _frameCount = 0;
    });
  }

  /// 卸载动画并停止写入帧日志。
  void _stop() => setState(() {
    _recording = false;
    _value = 0;
    _generation++;
  });

  /// 按原有九位目标归一化规则记录原始值和数字分解。
  void _onUpdate(double raw) {
    if (!_recording || _frameCount >= _maxLog) return;
    _frameCount++;

    // Decompose into digit values (same logic as _updateCurrentDigitValues)
    // from: 0, to: 999999999
    const from = 0.0, to = benchmarkTarget;
    final t = ((raw - from) / (to - from)).clamp(0.0, 1.0);

    final fromDigits = _getDigits(0);
    final toDigits = _getDigits(benchmarkTarget.toInt());
    final maxN = math.max(fromDigits.length, toDigits.length);
    final oldD = [
      ...List<double>.filled(maxN - fromDigits.length, 0.0),
      ...fromDigits,
    ];
    final tarD = [
      ...List<double>.filled(maxN - toDigits.length, 0.0),
      ...toDigits,
    ];

    final cur = <String>[];
    for (int i = 0; i < maxN; i++) {
      final v = oldD[i] + (tarD[i] - oldD[i]) * t;
      final digit = v.truncate() % 10;
      final progress = (v - v.truncate());
      final rnd = v.round();
      cur.add(
        '[$i]v=${v.toStringAsFixed(2)} d=$digit p=${progress.toStringAsFixed(2)} rnd=$rnd',
      );
    }

    final line =
        'f$_frameCount raw=${raw.toStringAsFixed(0)} t=${t.toStringAsFixed(4)}\n'
        '  ${tr(context, 'visible from idx', '首个可见数位')}=${_firstVisible(oldD, tarD, t, maxN)}\n'
        '  ${cur.join(' ')}';

    if (mounted) {
      setState(() => _logs.add(line));
    }
  }

  /// 寻找第一个可见的非零数位。
  int _firstVisible(List<double> oldD, List<double> tarD, double t, int n) {
    for (int i = 0; i < n; i++) {
      final v = oldD[i] + (tarD[i] - oldD[i]) * t;
      if (v.round() != 0) return i;
    }
    return n - 1;
  }

  /// 保留原有数位分解规则。
  List<double> _getDigits(int val) {
    if (val == 0) return [0.0];
    final d = <double>[];
    int v = val.abs();
    while (v > 0) {
      d.add(v.toDouble());
      v ~/= 10;
    }
    return d.reversed.toList();
  }

  /// 诊断数字的等宽样式。
  static const _style = TextStyle(
    fontSize: 40,
    fontWeight: FontWeight.bold,
    fontFamily: 'monospace',
  );

  /// 构建统一说明、诊断计数器和可滚动帧日志。
  @override
  Widget build(BuildContext context) => DemoPage(
    title: tr(context, 'Digit debug', '数字诊断'),
    description: tr(
      context,
      'Inspect 0 → 99 and reverse-to-zero animations over 3 s, with the original nine-digit normalized frame log.',
      '检查 3 秒内 0 → 99 及反向归零动画，保留原有九位目标归一化的逐帧日志。',
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
      Text(
        _decreasing
            ? tr(context, '↓ Decreasing', '↓ 递减')
            : tr(context, '↑ Increasing', '↑ 递增'),
        style: TextStyle(
          color: _decreasing ? Colors.red : Colors.green,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      KeyedSubtree(
        key: ValueKey(_generation),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: AnimatedCounter(
                value: _value,
                format: benchmarkFormat,
                timeline: const CounterTimeline(duration: _duration),
                style: const AnimatedCounterStyle(textStyle: _style),
              ),
            ),
            CounterBuilder(
              to: _value,
              duration: _duration,
              onUpdate: _onUpdate,
              builder: (_, v, _) => Text(
                v.toInt().toString(),
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
      DemoSection(
        title: tr(context, 'Frame log (first 30 updates)', '帧日志（前 30 次更新）'),
        child: SizedBox(
          height: 320,
          child: ListView.builder(
            padding: const EdgeInsets.all(DemoTokens.smallGap),
            itemCount: _logs.length,
            itemBuilder: (_, i) => Text(
              _logs[i],
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
        ),
      ),
    ],
  );
}
