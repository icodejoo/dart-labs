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
                    transitionType: CounterTransitionType.flip,
                    thousandSeparator: ',', textStyle: _ts),
            ]),
            _group('AnimatedCounter — blur', [
              for (var i = 0; i < 5; i++)
                AnimatedCounter(value: _value, duration: _dur, curve: Curves.linear,
                    transitionType: CounterTransitionType.blur,
                    thousandSeparator: ',', textStyle: _ts),
            ]),
            _group('AnimatedCounter — stagger', [
              for (var i = 0; i < 5; i++)
                AnimatedCounter(value: _value, duration: _dur, curve: Curves.linear,
                    staggerDelay: const Duration(milliseconds: 80),
                    thousandSeparator: ',', textStyle: _ts),
            ]),
            _group('CounterOdometer', [
              for (var i = 0; i < 5; i++)
                CounterOdometer(to: _value, duration: _dur, curve: Curves.linear,
                    style: const CounterOdometerStyle(
                        letterWidth: 18, verticalOffset: 24, numberTextStyle: _ts),
                    groupSeparator: ','),
            ]),
            _group('CounterText', [
              for (var i = 0; i < 5; i++)
                CounterText(to: _value, duration: _dur, curve: Curves.linear,
                    style: CounterTextStyle(textStyle: _ts)),
            ]),
          ],
        ),
      ),
    );
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

