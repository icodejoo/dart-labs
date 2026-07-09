import 'package:flutter/material.dart';
import 'package:countman/countman.dart';

void main() => runApp(const DemoApp());

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Countman Demo',
      theme: ThemeData.dark(useMaterial3: true),
      home: const DemoPage(),
    );
  }
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  double _target = 9999;

  void _toggle() => setState(() => _target = _target == 9999 ? 12345 : 9999);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Countman Demo')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _section('CountupText — default'),
            CountupText(to: _target, duration: const Duration(milliseconds: 1500)),

            _section('CountupText — prefix / suffix String'),
            CountupText(
              to: _target,
              prefix: '¥ ',
              suffix: ' 元',
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              duration: const Duration(milliseconds: 1500),
            ),

            _section('CountupText — prefixWidget / suffixWidget'),
            CountupText(
              to: _target,
              prefixWidget: const Icon(Icons.star, color: Colors.amber, size: 28),
              suffix: ' pts',
              style: const TextStyle(fontSize: 28),
              duration: const Duration(milliseconds: 1500),
            ),

            _section('CountupText — custom formatter (千分位)'),
            CountupText(
              to: _target,
              formatter: (v) {
                final s = v.toInt().toString();
                final buf = StringBuffer();
                for (var i = 0; i < s.length; i++) {
                  if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
                  buf.write(s[i]);
                }
                return buf.toString();
              },
              style: const TextStyle(fontSize: 32, fontFamily: 'monospace'),
              duration: const Duration(milliseconds: 1500),
            ),

            _section('CountupText — Curves.bounceOut'),
            CountupText(
              to: _target,
              curve: Curves.bounceOut,
              duration: const Duration(milliseconds: 2000),
              style: const TextStyle(fontSize: 32),
            ),

            _section('CountupBuilder — color lerp by value'),
            CountupBuilder(
              to: _target,
              duration: const Duration(milliseconds: 1500),
              builder: (_, value) {
                final t = (value / _target).clamp(0.0, 1.0);
                final color = Color.lerp(Colors.red, Colors.green, t)!;
                return Text(
                  value.toInt().toString(),
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                );
              },
            ),

            _section('CountupOdometer — 滚动数字（odometer 风格）'),
            CountupOdometer(
              to: _target,
              duration: const Duration(milliseconds: 1500),
              letterWidth: 24,
              numberTextStyle: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
              verticalOffset: 36,
            ),

            _section('CountupOdometer — 带千分位分隔符'),
            CountupOdometer(
              to: _target,
              duration: const Duration(milliseconds: 1500),
              letterWidth: 24,
              numberTextStyle: const TextStyle(fontSize: 36),
              verticalOffset: 36,
              groupSeparator: const Text(',', style: TextStyle(fontSize: 36)),
            ),

            _section('10 个并发实例（共享同一个 ticker）'),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var i = 1; i <= 10; i++)
                  _Chip(
                    label: '#$i',
                    child: CountupText(
                      to: _target * i / 10,
                      duration: Duration(milliseconds: 600 + i * 120),
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 36),
            FilledButton.icon(
              onPressed: _toggle,
              icon: const Icon(Icons.refresh),
              label: Text('Retarget → ${_target == 9999 ? 12345 : 9999}'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 8),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.outline,
            letterSpacing: 1.1,
          ),
        ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label ', style: const TextStyle(fontSize: 11, color: Colors.grey)),
          child,
        ],
      ),
    );
  }
}
