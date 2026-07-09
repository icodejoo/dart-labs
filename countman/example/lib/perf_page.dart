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
  static const _ts  = TextStyle(fontSize: 22, fontWeight: FontWeight.bold);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Perf Test  0 → 999,999,999 · 10 s'),
        backgroundColor: Colors.black,
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
            _group('AnimatedCountup — roll (default)', [
              for (var i = 0; i < 5; i++)
                AnimatedCountup(value: _value, duration: _dur, curve: Curves.linear,
                    thousandSeparator: ',', textStyle: _ts),
            ]),
            _group('AnimatedCountup — flip', [
              for (var i = 0; i < 5; i++)
                AnimatedCountup(value: _value, duration: _dur, curve: Curves.linear,
                    transitionType: CounterTransitionType.flip,
                    thousandSeparator: ',', textStyle: _ts),
            ]),
            _group('AnimatedCountup — blur', [
              for (var i = 0; i < 5; i++)
                AnimatedCountup(value: _value, duration: _dur, curve: Curves.linear,
                    transitionType: CounterTransitionType.blur,
                    thousandSeparator: ',', textStyle: _ts),
            ]),
            _group('AnimatedCountup — stagger', [
              for (var i = 0; i < 5; i++)
                AnimatedCountup(value: _value, duration: _dur, curve: Curves.linear,
                    staggerDelay: const Duration(milliseconds: 80),
                    thousandSeparator: ',', textStyle: _ts),
            ]),
            _group('CountupOdometer', [
              for (var i = 0; i < 5; i++)
                CountupOdometer(to: _value, duration: _dur, curve: Curves.linear,
                    letterWidth: 18, verticalOffset: 24,
                    numberTextStyle: _ts,
                    groupSeparator: Text(',', style: _ts)),
            ]),
            _group('CountupText', [
              for (var i = 0; i < 5; i++)
                CountupText(to: _value, duration: _dur, curve: Curves.linear,
                    style: _ts),
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

