import 'package:flutter/material.dart';
import 'package:countman/countman.dart';

/// Performance test page.
/// Animates multiple counters from 0 → 999,999,999 over 10 s.
/// Open via route '/perf'.
class PerfPage extends StatefulWidget {
  const PerfPage({super.key});
  @override
  State<PerfPage> createState() => _PerfPageState();
}

class _PerfPageState extends State<PerfPage> {
  double _value = 0;

  void _start() => setState(() => _value = 999999999);
  void _reset() => setState(() => _value = 0);

  static const _dur = Duration(seconds: 10);
  // Explicit white: the page forces a black background, so relying on the
  // theme's default text color makes digits invisible under a light theme.
  //
  // 显式白色：本页强制黑底，若依赖主题默认文字色，浅色主题下数字会看不见。
  static const _ts  = TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Perf Test  0 → 999,999,999 · 10 s'),
        backgroundColor: Colors.black,
        // Forced dark app bar → set light foreground so the title/actions stay
        // visible under a light theme (default foreground follows the theme).
        //
        // 强制深色 AppBar → 设浅色前景，使标题/操作在浅色主题下仍可见。
        foregroundColor: Colors.white,
        actions: [
          TextButton(onPressed: _reset, child: const Text('Reset')),
          const SizedBox(width: 8),
          FilledButton(onPressed: _start, child: const Text('Start')),
          const SizedBox(width: 12),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _group('AnimatedCounter — roll (default)', [
              for (var i = 0; i < 5; i++)
                AnimatedCounter(value: _value, duration: _dur, curve: Curves.linear,
                    thousandSeparator: ',', textStyle: _ts),
            ]),
            _group('AnimatedCounter — flip', [
              for (var i = 0; i < 5; i++)
                AnimatedCounter(value: _value, duration: _dur, curve: Curves.linear,
                    transition: CounterTransition.flip,
                    thousandSeparator: ',', textStyle: _ts),
            ]),
            _group('AnimatedCounter — blur', [
              for (var i = 0; i < 5; i++)
                AnimatedCounter(value: _value, duration: _dur, curve: Curves.linear,
                    transition: CounterTransition.slideBlur,
                    thousandSeparator: ',', textStyle: _ts),
            ]),
            _group('AnimatedCounter — stagger', [
              for (var i = 0; i < 5; i++)
                AnimatedCounter(value: _value, duration: _dur, curve: Curves.linear,
                    staggerDelay: const Duration(milliseconds: 80),
                    thousandSeparator: ',', textStyle: _ts),
            ]),
            _group('OdometerCounter', [
              for (var i = 0; i < 5; i++)
                OdometerCounter(to: _value, duration: _dur, curve: Curves.linear,
                    style: const OdometerCounterStyle(
                        letterWidth: 18, verticalOffset: 24, numberTextStyle: _ts),
                    groupSeparator: ','),
            ]),
            _group('TextCounter', [
              for (var i = 0; i < 5; i++)
                TextCounter(to: _value, duration: _dur, curve: Curves.linear,
                    formatter: _movingFormatter(
                        _value, _value / (_dur.inMilliseconds / 16.667)),
                    style: TextCounterStyle(textStyle: _ts)),
            ]),
          ],
        ),
      ),
    );
  }

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
  String Function(double) _movingFormatter(double target, double step) {
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
      final disp = iv - (seed % st); // subtract < one step → high digits stay true
      return '${disp < 0 ? 0 : disp}';
    };
  }

  /// True iff [n] is all nines with at least 5 digits (99999, 999999, …).
  ///
  /// [n] 为至少 5 位的全 9（99999、999999…）时为真。
  static bool _allNinesAtLeast5(int n) {
    if (n < 99999) return false;
    var m = n + 1;
    while (m % 10 == 0) m ~/= 10;
    return m == 1;
  }

  Widget _group(String title, List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(title,
            style: const TextStyle(fontSize: 11, color: Colors.grey, letterSpacing: 0.8)),
      ),
      Wrap(
        spacing: 12, runSpacing: 8,
        children: children.map((w) => Card(
          color: Colors.grey[900],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: w,
          ),
        )).toList(),
      ),
      const SizedBox(height: 8),
    ],
  );
}

