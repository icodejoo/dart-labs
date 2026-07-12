import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:countman/countman.dart';
import 'demo_card.dart';

class CounterPage extends StatefulWidget {
  const CounterPage({super.key});
  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> {
  int _resetKey = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Counter'),
        actions: [
          IconButton(
            icon: const Icon(Icons.replay_rounded),
            tooltip: 'Reset all demos',
            onPressed: () => setState(() => _resetKey++),
          ),
        ],
      ),
      body: PageSectionCounter(
        child: KeyedSubtree(
        key: ValueKey(_resetKey),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
          // ?�?� CounterText ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�
          DemoSection(title: 'CounterText', children: [
            DemoCard(
              title: 'Basic',
              child: CounterText(
                from: 0,
                to: 9999,
                style: CounterTextStyle(textStyle: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => CounterText(\n"
                "    from: 0,\n"
                "    to: 9999,\n"
                "    style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold),\n"
                "  );\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'Custom formatter',
              description: 'Formats value as currency ? with 2 decimals',
              child: CounterText(
                from: 0,
                to: 9999.99,
                formatter: (v) => '?${v.toStringAsFixed(2)}',
                style: CounterTextStyle(textStyle: const TextStyle(fontSize: 32)),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => CounterText(\n"
                "    from: 0,\n"
                "    to: 9999.99,\n"
                "    formatter: (v) => '?\${v.toStringAsFixed(2)}',\n"
                "    style: TextStyle(fontSize: 32),\n"
                "  );\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'Prefix & suffix',
              child: CounterText(
                from: 0,
                to: 500,
                prefix: '?? ',
                suffix: ' pts',
                style: CounterTextStyle(textStyle: const TextStyle(fontSize: 32)),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => CounterText(\n"
                "    from: 0,\n"
                "    to: 500,\n"
                "    prefix: '?? ',\n"
                "    suffix: ' pts',\n"
                "    style: TextStyle(fontSize: 32),\n"
                "  );\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'Duration & curve',
              description: '3 s, bounceOut easing',
              child: CounterText(
                from: 0,
                to: 100,
                duration: const Duration(seconds: 3),
                curve: Curves.bounceOut,
                style: CounterTextStyle(textStyle: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => CounterText(\n"
                "    from: 0,\n"
                "    to: 100,\n"
                "    duration: Duration(seconds: 3),\n"
                "    curve: Curves.bounceOut,\n"
                "    style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold),\n"
                "  );\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'Negative values',
              description: 'Counts from 50 down through 0 to -50',
              child: CounterText(
                from: 50,
                to: -50,
                allowNegative: true,
                style: CounterTextStyle(textStyle: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => CounterText(\n"
                "    from: 50,\n"
                "    to: -50,\n"
                "    allowNegative: true,\n"
                "    style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold),\n"
                "  );\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'onComplete callback',
              description: 'Shows a SnackBar when the animation finishes',
              child: _CounterTextOnComplete(),
              code: runnable(
                "class _Demo extends StatefulWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  State<_Demo> createState() => _DemoState();\n"
                "}\n"
                "\n"
                "class _DemoState extends State<_Demo> {\n"
                "  int _seed = 0;\n"
                "  @override\n"
                "  Widget build(BuildContext context) {\n"
                "    return Column(\n"
                "      mainAxisSize: MainAxisSize.min,\n"
                "      children: [\n"
                "        KeyedSubtree(\n"
                "          key: ValueKey(_seed),\n"
                "          child: CounterText(\n"
                "            from: 0,\n"
                "            to: 100,\n"
                "            style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold),\n"
                "            onComplete: (_) => ScaffoldMessenger.of(context)\n"
                "              .showSnackBar(const SnackBar(content: Text('Done!'))),\n"
                "          ),\n"
                "        ),\n"
                "        const SizedBox(height: 12),\n"
                "        ElevatedButton(\n"
                "          onPressed: () => setState(() => _seed++),\n"
                "          child: const Text('Replay'),\n"
                "        ),\n"
                "      ],\n"
                "    );\n"
                "  }\n"
                "}",
              ),
            ),
          ]),

          // ?�?� CounterBuilder ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�
          DemoSection(title: 'CounterBuilder', children: [
            DemoCard(
              title: 'Basic builder',
              child: CounterBuilder(
                from: 0,
                to: 9999,
                builder: (_, value, child) => Text(
                  value.toInt().toString(),
                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
                ),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => CounterBuilder(\n"
                "    from: 0,\n"
                "    to: 9999,\n"
                "    builder: (_, value, __) => Text(\n"
                "      value.toInt().toString(),\n"
                "      style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold),\n"
                "    ),\n"
                "  );\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'Progress bar',
              description: 'valueTransform normalizes value to 0??',
              child: CounterBuilder(
                from: 0,
                to: 100,
                valueTransform: (v) => v / 100,
                builder: (_, progress, child) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 220,
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 12,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('${(progress * 100).toInt()}%'),
                  ],
                ),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => CounterBuilder(\n"
                "    from: 0,\n"
                "    to: 100,\n"
                "    valueTransform: (v) => v / 100,\n"
                "    builder: (_, progress, __) => Column(\n"
                "      mainAxisSize: MainAxisSize.min,\n"
                "      children: [\n"
                "        SizedBox(\n"
                "          width: 220,\n"
                "          child: LinearProgressIndicator(\n"
                "            value: progress,\n"
                "            minHeight: 12,\n"
                "            borderRadius: BorderRadius.circular(6),\n"
                "          ),\n"
                "        ),\n"
                "        SizedBox(height: 8),\n"
                "        Text('\${(progress * 100).toInt()}%'),\n"
                "      ],\n"
                "    ),\n"
                "  );\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'Color lerp',
              description: 'Interpolates red ??green as value grows',
              child: CounterBuilder(
                from: 0,
                to: 100,
                duration: const Duration(seconds: 2),
                builder: (_, value, child) {
                  final t = (value / 100).clamp(0.0, 1.0);
                  final color = Color.lerp(Colors.red, Colors.green, t)!;
                  return Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      value.toInt().toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                },
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => CounterBuilder(\n"
                "    from: 0,\n"
                "    to: 100,\n"
                "    duration: Duration(seconds: 2),\n"
                "    builder: (_, value, __) {\n"
                "      final t = (value / 100).clamp(0.0, 1.0);\n"
                "      final color = Color.lerp(Colors.red, Colors.green, t)!;\n"
                "      return Container(\n"
                "        width: 100, height: 100,\n"
                "        decoration: BoxDecoration(\n"
                "          color: color,\n"
                "          borderRadius: BorderRadius.circular(12),\n"
                "        ),\n"
                "        alignment: Alignment.center,\n"
                "        child: Text(\n"
                "          value.toInt().toString(),\n"
                "          style: TextStyle(color: Colors.white, fontSize: 28,\n"
                "              fontWeight: FontWeight.bold),\n"
                "        ),\n"
                "      );\n"
                "    },\n"
                "  );\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'Child optimization',
              description: 'Static child passed through without rebuilding',
              child: CounterBuilder(
                from: 0,
                to: 9999,
                child: const Icon(Icons.star, size: 28, color: Colors.amber),
                builder: (_, value, child) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    child!,
                    const SizedBox(width: 8),
                    Text(
                      value.toInt().toString(),
                      style: const TextStyle(
                          fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => CounterBuilder(\n"
                "    from: 0,\n"
                "    to: 9999,\n"
                "    child: const Icon(Icons.star, size: 28, color: Colors.amber),\n"
                "    builder: (_, value, child) => Row(\n"
                "      mainAxisSize: MainAxisSize.min,\n"
                "      children: [\n"
                "        child!,\n"
                "        const SizedBox(width: 8),\n"
                "        Text(value.toInt().toString(),\n"
                "            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),\n"
                "      ],\n"
                "    ),\n"
                "  );\n"
                "}",
              ),
            ),
          ]),

          // ?�?� CounterOdometer ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�
          DemoSection(title: 'CounterOdometer', children: [
            DemoCard(
              title: 'Basic',
              child: CounterOdometer(
                from: 0,
                to: 9999,
                style: const CounterOdometerStyle(
                  letterWidth: 22,
                  numberTextStyle: TextStyle(fontSize: 32),
                ),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => CounterOdometer(\n"
                "    from: 0,\n"
                "    to: 9999,\n"
                "    letterWidth: 22,\n"
                "    numberTextStyle: TextStyle(fontSize: 32),\n"
                "  );\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'Group separator',
              description: "Comma every 3 digits",
              child: CounterOdometer(
                from: 0,
                to: 1234567,
                groupSeparator: ',',
                style: const CounterOdometerStyle(
                  letterWidth: 22,
                  numberTextStyle: TextStyle(fontSize: 32),
                ),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => CounterOdometer(\n"
                "    from: 0,\n"
                "    to: 1234567,\n"
                "    letterWidth: 22,\n"
                "    groupSeparator: ',',\n"
                "    numberTextStyle: TextStyle(fontSize: 32),\n"
                "  );\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'Bounce on arrival',
              description: 'bounceOvershoot: 0.67, bounceElasticity: 5.0',
              child: CounterOdometer(
                from: 0,
                to: 999,
                bounceOvershoot: 0.67,
                bounceElasticity: 5.0,
                style: const CounterOdometerStyle(
                  letterWidth: 22,
                  numberTextStyle: TextStyle(fontSize: 36),
                ),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => CounterOdometer(\n"
                "    from: 0,\n"
                "    to: 999,\n"
                "    letterWidth: 22,\n"
                "    bounceOvershoot: 0.67,\n"
                "    bounceElasticity: 5.0,\n"
                "    numberTextStyle: TextStyle(fontSize: 36),\n"
                "  );\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'Decreasing',
              child: CounterOdometer(
                from: 10000,
                to: 0,
                style: const CounterOdometerStyle(
                  letterWidth: 22,
                  numberTextStyle: TextStyle(fontSize: 32),
                ),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => CounterOdometer(\n"
                "    from: 10000,\n"
                "    to: 0,\n"
                "    letterWidth: 22,\n"
                "    numberTextStyle: TextStyle(fontSize: 32),\n"
                "  );\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'Fade disabled',
              description: 'Slide-only, no cross-fade',
              child: CounterOdometer(
                from: 0,
                to: 9999,
                style: const CounterOdometerStyle(
                  letterWidth: 22,
                  fadeEnabled: false,
                  numberTextStyle: TextStyle(fontSize: 32),
                ),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => CounterOdometer(\n"
                "    from: 0,\n"
                "    to: 9999,\n"
                "    letterWidth: 22,\n"
                "    fadeEnabled: false,\n"
                "    numberTextStyle: TextStyle(fontSize: 32),\n"
                "  );\n"
                "}",
              ),
            ),
          ]),

          // ?�?� CounterRing ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�
          DemoSection(title: 'CounterRing', children: [
            DemoCard(
              title: 'Basic',
              child: CounterRing(
                to: 100,
                style: const CounterRingStyle(size: 100),
                center: CounterBuilder(
                  from: 0,
                  to: 100,
                  builder: (_, v, child) => Text(
                    '${v.toInt()}%',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => CounterRing(\n"
                "    size: 100,\n"
                "    to: 100,\n"
                "    center: CounterBuilder(\n"
                "      from: 0,\n"
                "      to: 100,\n"
                "      builder: (_, v, __) => Text(\n"
                "        '\${v.toInt()}%',\n"
                "        style: TextStyle(fontWeight: FontWeight.bold),\n"
                "      ),\n"
                "    ),\n"
                "  );\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'Custom colors',
              child: CounterRing(
                to: 100,
                style: CounterRingStyle(
                  size: 100,
                  color: Colors.orange,
                  trackColor: Colors.orange.withValues(alpha: 0.2),
                ),
                center: const Icon(Icons.local_fire_department,
                    color: Colors.orange, size: 28),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => CounterRing(\n"
                "    size: 100,\n"
                "    to: 100,\n"
                "    color: Colors.orange,\n"
                "    trackColor: Colors.orange.withOpacity(0.2),\n"
                "    center: Icon(Icons.local_fire_department,\n"
                "        color: Colors.orange, size: 28),\n"
                "  );\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'Gradient',
              child: CounterRing(
                to: 100,
                style: const CounterRingStyle(
                  size: 100,
                  gradient: SweepGradient(
                    colors: [Colors.blue, Colors.purple, Colors.pink],
                  ),
                ),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => CounterRing(\n"
                "    size: 100,\n"
                "    to: 100,\n"
                "    gradient: SweepGradient(\n"
                "      colors: [Colors.blue, Colors.purple, Colors.pink],\n"
                "    ),\n"
                "  );\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'Anti-clockwise',
              child: CounterRing(
                to: 100,
                style: const CounterRingStyle(
                  size: 100,
                  clockwise: false,
                ),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => CounterRing(\n"
                "    size: 100,\n"
                "    to: 100,\n"
                "    clockwise: false,\n"
                "  );\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'Large stroke',
              child: CounterRing(
                to: 100,
                style: const CounterRingStyle(
                  size: 120,
                  strokeWidth: 16,
                ),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => CounterRing(\n"
                "    size: 120,\n"
                "    to: 100,\n"
                "    strokeWidth: 16,\n"
                "  );\n"
                "}",
              ),
            ),
          ]),

          // ?�?� CounterBar ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�
          DemoSection(title: 'CounterBar', children: [
            DemoCard(
              title: 'Basic',
              child: CounterBar(
                  to: 100,
                  style: const CounterBarStyle(width: 240, height: 12)),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) =>\n"
                "      CounterBar(width: 240, height: 12, to: 100);\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'Gradient fill',
              child: CounterBar(
                to: 100,
                style: const CounterBarStyle(
                  width: 240,
                  height: 12,
                  gradient: LinearGradient(
                    colors: [Colors.blue, Colors.purple],
                  ),
                ),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => CounterBar(\n"
                "    width: 240,\n"
                "    height: 12,\n"
                "    to: 100,\n"
                "    gradient: LinearGradient(\n"
                "      colors: [Colors.blue, Colors.purple],\n"
                "    ),\n"
                "  );\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'Fill from end',
              child: CounterBar(
                to: 100,
                style: const CounterBarStyle(
                  width: 240,
                  height: 12,
                  fillFromStart: false,
                ),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => CounterBar(\n"
                "    width: 240,\n"
                "    height: 12,\n"
                "    to: 100,\n"
                "    fillFromStart: false,\n"
                "  );\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'Rounded corners',
              child: CounterBar(
                to: 100,
                style: const CounterBarStyle(
                  width: 240,
                  height: 20,
                  borderRadius: Radius.circular(10),
                ),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => CounterBar(\n"
                "    width: 240,\n"
                "    height: 20,\n"
                "    to: 100,\n"
                "    borderRadius: Radius.circular(10),\n"
                "  );\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'Custom track height',
              description: 'Thin fill (4) inside a taller track (20)',
              child: CounterBar(
                to: 100,
                style: const CounterBarStyle(
                  width: 240,
                  height: 4,
                  trackHeight: 20,
                  borderRadius: Radius.circular(10),
                ),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => CounterBar(\n"
                "    width: 240,\n"
                "    height: 4,\n"
                "    trackHeight: 20,\n"
                "    to: 100,\n"
                "    borderRadius: Radius.circular(10),\n"
                "  );\n"
                "}",
              ),
            ),
          ]),

          // ?�?� AnimatedCounter ??Transitions ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�
          DemoSection(title: 'AnimatedCounter ??Transitions', children: [
            DemoCard(
              title: 'roll',
              child: _CyclingAnimatedCounter(
                  transitionType: CounterTransitionType.roll),
              code: runnable(
                "class _Demo extends StatefulWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  State<_Demo> createState() => _DemoState();\n"
                "}\n"
                "\n"
                "class _DemoState extends State<_Demo> {\n"
                "  final _ctrl = AnimatedCounterController(initialValue: 0);\n"
                "  final _values = [0, 99, 42, 1000, 7];\n"
                "  int _idx = 0;\n"
                "\n"
                "  @override\n"
                "  void dispose() { _ctrl.dispose(); super.dispose(); }\n"
                "\n"
                "  @override\n"
                "  Widget build(BuildContext context) {\n"
                "    return Column(\n"
                "      mainAxisSize: MainAxisSize.min,\n"
                "      children: [\n"
                "        AnimatedCounter(\n"
                "          controller: _ctrl,\n"
                "          transitionType: CounterTransitionType.roll,\n"
                "          duration: Duration(milliseconds: 600),\n"
                "          textStyle: TextStyle(fontSize: 48),\n"
                "        ),\n"
                "        const SizedBox(height: 12),\n"
                "        ElevatedButton(\n"
                "          onPressed: () {\n"
                "            _idx = (_idx + 1) % _values.length;\n"
                "            _ctrl.animateTo(_values[_idx]);\n"
                "          },\n"
                "          child: const Text('Next'),\n"
                "        ),\n"
                "      ],\n"
                "    );\n"
                "  }\n"
                "}",
                extraImports: "import 'dart:async';",
              ),
            ),

            DemoCard(
              title: 'fade',
              child: _CyclingAnimatedCounter(
                  transitionType: CounterTransitionType.fade),
              code: runnable(
                "class _Demo extends StatefulWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  State<_Demo> createState() => _DemoState();\n"
                "}\n"
                "\n"
                "class _DemoState extends State<_Demo> {\n"
                "  final _ctrl = AnimatedCounterController(initialValue: 0);\n"
                "  final _values = [0, 99, 42, 1000, 7];\n"
                "  int _idx = 0;\n"
                "\n"
                "  @override\n"
                "  void dispose() { _ctrl.dispose(); super.dispose(); }\n"
                "\n"
                "  @override\n"
                "  Widget build(BuildContext context) {\n"
                "    return Column(\n"
                "      mainAxisSize: MainAxisSize.min,\n"
                "      children: [\n"
                "        AnimatedCounter(\n"
                "          controller: _ctrl,\n"
                "          transitionType: CounterTransitionType.fade,\n"
                "          duration: Duration(milliseconds: 600),\n"
                "          textStyle: TextStyle(fontSize: 48),\n"
                "        ),\n"
                "        const SizedBox(height: 12),\n"
                "        ElevatedButton(\n"
                "          onPressed: () {\n"
                "            _idx = (_idx + 1) % _values.length;\n"
                "            _ctrl.animateTo(_values[_idx]);\n"
                "          },\n"
                "          child: const Text('Next'),\n"
                "        ),\n"
                "      ],\n"
                "    );\n"
                "  }\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'scale',
              child: _CyclingAnimatedCounter(
                  transitionType: CounterTransitionType.scale),
              code: runnable(
                "class _Demo extends StatefulWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  State<_Demo> createState() => _DemoState();\n"
                "}\n"
                "\n"
                "class _DemoState extends State<_Demo> {\n"
                "  final _ctrl = AnimatedCounterController(initialValue: 0);\n"
                "  final _values = [0, 99, 42, 1000, 7];\n"
                "  int _idx = 0;\n"
                "\n"
                "  @override\n"
                "  void dispose() { _ctrl.dispose(); super.dispose(); }\n"
                "\n"
                "  @override\n"
                "  Widget build(BuildContext context) {\n"
                "    return Column(\n"
                "      mainAxisSize: MainAxisSize.min,\n"
                "      children: [\n"
                "        AnimatedCounter(\n"
                "          controller: _ctrl,\n"
                "          transitionType: CounterTransitionType.scale,\n"
                "          duration: Duration(milliseconds: 600),\n"
                "          textStyle: TextStyle(fontSize: 48),\n"
                "        ),\n"
                "        const SizedBox(height: 12),\n"
                "        ElevatedButton(\n"
                "          onPressed: () {\n"
                "            _idx = (_idx + 1) % _values.length;\n"
                "            _ctrl.animateTo(_values[_idx]);\n"
                "          },\n"
                "          child: const Text('Next'),\n"
                "        ),\n"
                "      ],\n"
                "    );\n"
                "  }\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'fadeScale',
              child: _CyclingAnimatedCounter(
                  transitionType: CounterTransitionType.fadeScale),
              code: runnable(
                "class _Demo extends StatefulWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  State<_Demo> createState() => _DemoState();\n"
                "}\n"
                "\n"
                "class _DemoState extends State<_Demo> {\n"
                "  final _ctrl = AnimatedCounterController(initialValue: 0);\n"
                "  final _values = [0, 99, 42, 1000, 7];\n"
                "  int _idx = 0;\n"
                "\n"
                "  @override\n"
                "  void dispose() { _ctrl.dispose(); super.dispose(); }\n"
                "\n"
                "  @override\n"
                "  Widget build(BuildContext context) {\n"
                "    return Column(\n"
                "      mainAxisSize: MainAxisSize.min,\n"
                "      children: [\n"
                "        AnimatedCounter(\n"
                "          controller: _ctrl,\n"
                "          transitionType: CounterTransitionType.fadeScale,\n"
                "          duration: Duration(milliseconds: 600),\n"
                "          textStyle: TextStyle(fontSize: 48),\n"
                "        ),\n"
                "        const SizedBox(height: 12),\n"
                "        ElevatedButton(\n"
                "          onPressed: () {\n"
                "            _idx = (_idx + 1) % _values.length;\n"
                "            _ctrl.animateTo(_values[_idx]);\n"
                "          },\n"
                "          child: const Text('Next'),\n"
                "        ),\n"
                "      ],\n"
                "    );\n"
                "  }\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'rotate',
              child: _CyclingAnimatedCounter(
                  transitionType: CounterTransitionType.rotate),
              code: runnable(
                "class _Demo extends StatefulWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  State<_Demo> createState() => _DemoState();\n"
                "}\n"
                "\n"
                "class _DemoState extends State<_Demo> {\n"
                "  final _ctrl = AnimatedCounterController(initialValue: 0);\n"
                "  final _values = [0, 99, 42, 1000, 7];\n"
                "  int _idx = 0;\n"
                "\n"
                "  @override\n"
                "  void dispose() { _ctrl.dispose(); super.dispose(); }\n"
                "\n"
                "  @override\n"
                "  Widget build(BuildContext context) {\n"
                "    return Column(\n"
                "      mainAxisSize: MainAxisSize.min,\n"
                "      children: [\n"
                "        AnimatedCounter(\n"
                "          controller: _ctrl,\n"
                "          transitionType: CounterTransitionType.rotate,\n"
                "          duration: Duration(milliseconds: 600),\n"
                "          textStyle: TextStyle(fontSize: 48),\n"
                "        ),\n"
                "        const SizedBox(height: 12),\n"
                "        ElevatedButton(\n"
                "          onPressed: () {\n"
                "            _idx = (_idx + 1) % _values.length;\n"
                "            _ctrl.animateTo(_values[_idx]);\n"
                "          },\n"
                "          child: const Text('Next'),\n"
                "        ),\n"
                "      ],\n"
                "    );\n"
                "  }\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'flip',
              child: _CyclingAnimatedCounter(
                  transitionType: CounterTransitionType.flip),
              code: runnable(
                "class _Demo extends StatefulWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  State<_Demo> createState() => _DemoState();\n"
                "}\n"
                "\n"
                "class _DemoState extends State<_Demo> {\n"
                "  final _ctrl = AnimatedCounterController(initialValue: 0);\n"
                "  final _values = [0, 99, 42, 1000, 7];\n"
                "  int _idx = 0;\n"
                "\n"
                "  @override\n"
                "  void dispose() { _ctrl.dispose(); super.dispose(); }\n"
                "\n"
                "  @override\n"
                "  Widget build(BuildContext context) {\n"
                "    return Column(\n"
                "      mainAxisSize: MainAxisSize.min,\n"
                "      children: [\n"
                "        AnimatedCounter(\n"
                "          controller: _ctrl,\n"
                "          transitionType: CounterTransitionType.flip,\n"
                "          duration: Duration(milliseconds: 600),\n"
                "          textStyle: TextStyle(fontSize: 48),\n"
                "        ),\n"
                "        const SizedBox(height: 12),\n"
                "        ElevatedButton(\n"
                "          onPressed: () {\n"
                "            _idx = (_idx + 1) % _values.length;\n"
                "            _ctrl.animateTo(_values[_idx]);\n"
                "          },\n"
                "          child: const Text('Next'),\n"
                "        ),\n"
                "      ],\n"
                "    );\n"
                "  }\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'blur',
              description: 'AnimatedCounterBuilder with blur transition',
              child: _CyclingAnimatedCounterBuilder(
                  transitionType: CounterTransitionType.blur),
              code: runnable(
                "class _Demo extends StatefulWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  State<_Demo> createState() => _DemoState();\n"
                "}\n"
                "\n"
                "class _DemoState extends State<_Demo> {\n"
                "  final _ctrl = AnimatedCounterController(initialValue: 0);\n"
                "  final _values = [0, 99, 42, 1000, 7];\n"
                "  int _idx = 0;\n"
                "\n"
                "  @override\n"
                "  void dispose() { _ctrl.dispose(); super.dispose(); }\n"
                "\n"
                "  @override\n"
                "  Widget build(BuildContext context) {\n"
                "    return Column(\n"
                "      mainAxisSize: MainAxisSize.min,\n"
                "      children: [\n"
                "        AnimatedCounterBuilder(\n"
                "          controller: _ctrl,\n"
                "          transitionType: CounterTransitionType.blur,\n"
                "          duration: Duration(milliseconds: 600),\n"
                "          textStyle: TextStyle(fontSize: 48),\n"
                "        ),\n"
                "        const SizedBox(height: 12),\n"
                "        ElevatedButton(\n"
                "          onPressed: () {\n"
                "            _idx = (_idx + 1) % _values.length;\n"
                "            _ctrl.animateTo(_values[_idx]);\n"
                "          },\n"
                "          child: const Text('Next'),\n"
                "        ),\n"
                "      ],\n"
                "    );\n"
                "  }\n"
                "}",
              ),
            ),
          ]),

          // ?�?� AnimatedCounter ??Formatting ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�
          DemoSection(title: 'AnimatedCounter ??Formatting', children: [
            DemoCard(
              title: 'Thousand separator',
              child: AnimatedCounter(
                value: 1234567,
                thousandSeparator: ',',
                duration: const Duration(milliseconds: 800),
                textStyle: const TextStyle(fontSize: 36),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => AnimatedCounter(\n"
                "    value: 1234567,\n"
                "    thousandSeparator: ',',\n"
                "    duration: Duration(milliseconds: 800),\n"
                "    textStyle: TextStyle(fontSize: 36),\n"
                "  );\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'Fraction digits',
              child: AnimatedCounter(
                value: 9999.99,
                fractionDigits: 2,
                duration: const Duration(milliseconds: 800),
                textStyle: const TextStyle(fontSize: 36),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => AnimatedCounter(\n"
                "    value: 9999.99,\n"
                "    fractionDigits: 2,\n"
                "    duration: Duration(milliseconds: 800),\n"
                "    textStyle: TextStyle(fontSize: 36),\n"
                "  );\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'Compact notation',
              child: AnimatedCounter(
                value: 1500000,
                compactNotation: true,
                duration: const Duration(milliseconds: 800),
                textStyle: const TextStyle(fontSize: 36),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => AnimatedCounter(\n"
                "    value: 1500000,\n"
                "    compactNotation: true,\n"
                "    duration: Duration(milliseconds: 800),\n"
                "    textStyle: TextStyle(fontSize: 36),\n"
                "  );\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'Prefix & suffix (Row)',
              child: AnimatedCounter(
                value: 9999,
                prefix: '¥',
                suffix: ' 元',
                duration: const Duration(milliseconds: 800),
                textStyle: const TextStyle(fontSize: 36),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => AnimatedCounter(\n"
                "    value: 9999,\n"
                "    prefix: '?',\n"
                "    suffix: ' ??,\n"
                "    duration: Duration(milliseconds: 800),\n"
                "    textStyle: TextStyle(fontSize: 36),\n"
                "  );\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'Negative sign',
              child: AnimatedCounter(
                value: -12345,
                thousandSeparator: ',',
                duration: const Duration(milliseconds: 800),
                textStyle: const TextStyle(fontSize: 36),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => AnimatedCounter(\n"
                "    value: -12345,\n"
                "    thousandSeparator: ',',\n"
                "    duration: Duration(milliseconds: 800),\n"
                "    textStyle: TextStyle(fontSize: 36),\n"
                "  );\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'Stagger right→left',
              description: '80 ms delay per digit, right to left',
              child: AnimatedCounter(
                value: 9876,
                staggerDelay: const Duration(milliseconds: 80),
                staggerDirection: StaggerDirection.rightToLeft,
                duration: const Duration(milliseconds: 600),
                textStyle: const TextStyle(fontSize: 36),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => AnimatedCounter(\n"
                "    value: 9876,\n"
                "    staggerDelay: Duration(milliseconds: 80),\n"
                "    staggerDirection: StaggerDirection.rightToLeft,\n"
                "    duration: Duration(milliseconds: 600),\n"
                "    textStyle: TextStyle(fontSize: 36),\n"
                "  );\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'Stagger left→right',
              description: '80 ms delay per digit, left to right',
              child: AnimatedCounter(
                value: 9876,
                staggerDelay: const Duration(milliseconds: 80),
                staggerDirection: StaggerDirection.leftToRight,
                duration: const Duration(milliseconds: 600),
                textStyle: const TextStyle(fontSize: 36),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => AnimatedCounter(\n"
                "    value: 9876,\n"
                "    staggerDelay: Duration(milliseconds: 80),\n"
                "    staggerDirection: StaggerDirection.leftToRight,\n"
                "    duration: Duration(milliseconds: 600),\n"
                "    textStyle: TextStyle(fontSize: 36),\n"
                "  );\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'Align left',
              description: 'numberAlignment: -1.0  (shrinks left??ight)',
              child: _AlignmentCycler(numberAlignment: -1.0),
              code: runnable(
                "class _Demo extends StatefulWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override State<_Demo> createState() => _S();\n"
                "}\n"
                "class _S extends State<_Demo> {\n"
                "  final _ctrl = AnimatedCounterController(initialValue: 1000);\n"
                "  final _vals = [1000, 7, 42, 999];\n"
                "  int _i = 0;\n"
                "  @override void dispose() { _ctrl.dispose(); super.dispose(); }\n"
                "  @override\n"
                "  Widget build(BuildContext context) => Column(\n"
                "    mainAxisSize: MainAxisSize.min,\n"
                "    children: [\n"
                "      AnimatedCounter(\n"
                "        controller: _ctrl,\n"
                "        numberAlignment: -1.0,\n"
                "        textStyle: TextStyle(fontSize: 40),\n"
                "      ),\n"
                "      ElevatedButton(\n"
                "        onPressed: () { _i = (_i+1)%_vals.length; _ctrl.animateTo(_vals[_i].toDouble()); },\n"
                "        child: Text('Next'),\n"
                "      ),\n"
                "    ],\n"
                "  );\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'Align center',
              description: 'numberAlignment: 0.0  (default, shrinks to center)',
              child: _AlignmentCycler(numberAlignment: 0.0),
              code: runnable(
                "class _Demo extends StatefulWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override State<_Demo> createState() => _S();\n"
                "}\n"
                "class _S extends State<_Demo> {\n"
                "  final _ctrl = AnimatedCounterController(initialValue: 1000);\n"
                "  final _vals = [1000, 7, 42, 999];\n"
                "  int _i = 0;\n"
                "  @override void dispose() { _ctrl.dispose(); super.dispose(); }\n"
                "  @override\n"
                "  Widget build(BuildContext context) => Column(\n"
                "    mainAxisSize: MainAxisSize.min,\n"
                "    children: [\n"
                "      AnimatedCounter(\n"
                "        controller: _ctrl,\n"
                "        numberAlignment: 0.0,\n"
                "        textStyle: TextStyle(fontSize: 40),\n"
                "      ),\n"
                "      ElevatedButton(\n"
                "        onPressed: () { _i = (_i+1)%_vals.length; _ctrl.animateTo(_vals[_i].toDouble()); },\n"
                "        child: Text('Next'),\n"
                "      ),\n"
                "    ],\n"
                "  );\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'Align right',
              description: 'numberAlignment: 1.0  (shrinks right??eft)',
              child: _AlignmentCycler(numberAlignment: 1.0),
              code: runnable(
                "class _Demo extends StatefulWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override State<_Demo> createState() => _S();\n"
                "}\n"
                "class _S extends State<_Demo> {\n"
                "  final _ctrl = AnimatedCounterController(initialValue: 1000);\n"
                "  final _vals = [1000, 7, 42, 999];\n"
                "  int _i = 0;\n"
                "  @override void dispose() { _ctrl.dispose(); super.dispose(); }\n"
                "  @override\n"
                "  Widget build(BuildContext context) => Column(\n"
                "    mainAxisSize: MainAxisSize.min,\n"
                "    children: [\n"
                "      AnimatedCounter(\n"
                "        controller: _ctrl,\n"
                "        numberAlignment: 1.0,\n"
                "        textStyle: TextStyle(fontSize: 40),\n"
                "      ),\n"
                "      ElevatedButton(\n"
                "        onPressed: () { _i = (_i+1)%_vals.length; _ctrl.animateTo(_vals[_i].toDouble()); },\n"
                "        child: Text('Next'),\n"
                "      ),\n"
                "    ],\n"
                "  );\n"
                "}",
              ),
            ),
          ]),

          // ?�?� AnimatedCounter ??Numeral Systems ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�
          DemoSection(title: 'AnimatedCounter ??Numeral Systems', children: [
            DemoCard(
              title: 'Eastern Arabic',
              child: AnimatedCounter(
                value: 1234,
                numeralSystem: NumeralSystem.easternArabic,
                duration: const Duration(milliseconds: 800),
                textStyle: const TextStyle(fontSize: 40),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => AnimatedCounter(\n"
                "    value: 1234,\n"
                "    numeralSystem: NumeralSystem.easternArabic,\n"
                "    duration: Duration(milliseconds: 800),\n"
                "    textStyle: TextStyle(fontSize: 40),\n"
                "  );\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'Persian',
              child: AnimatedCounter(
                value: 5678,
                numeralSystem: NumeralSystem.persian,
                duration: const Duration(milliseconds: 800),
                textStyle: const TextStyle(fontSize: 40),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => AnimatedCounter(\n"
                "    value: 5678,\n"
                "    numeralSystem: NumeralSystem.persian,\n"
                "    duration: Duration(milliseconds: 800),\n"
                "    textStyle: TextStyle(fontSize: 40),\n"
                "  );\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'Custom mapper',
              description: 'Maps digits to circled numbers ①②③',
              child: AnimatedCounter(
                value: 9,
                numeralMapper: (d) =>
                    ['⓪', '①', '②', '③', '④', '⑤', '⑥', '⑦', '⑧', '⑨'][d],
                duration: const Duration(milliseconds: 800),
                textStyle: const TextStyle(fontSize: 40),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => AnimatedCounter(\n"
                "    value: 9,\n"
                "    numeralMapper: (d) =>\n"
                "        ['⓪','①','②','③','④','⑤','⑥','⑦','⑧','⑨'][d],\n"
                "    duration: Duration(milliseconds: 800),\n"
                "    textStyle: TextStyle(fontSize: 40),\n"
                "  );\n"
                "}",
              ),
            ),
          ]),

          // ?�?� AnimatedCounter ??Locale Factories ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�
          DemoSection(title: 'AnimatedCounter ??Locale Factories', children: [
            DemoCard(
              title: 'USD',
              child: AnimatedCounter.usd(
                value: 1234567.89,
                duration: const Duration(milliseconds: 800),
                textStyle: const TextStyle(fontSize: 32),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => AnimatedCounter.usd(\n"
                "    value: 1234567.89,\n"
                "    duration: Duration(milliseconds: 800),\n"
                "    textStyle: TextStyle(fontSize: 32),\n"
                "  );\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'CNY (?)',
              child: AnimatedCounter.cny(
                value: 9999.99,
                duration: const Duration(milliseconds: 800),
                textStyle: const TextStyle(fontSize: 32),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => AnimatedCounter.cny(\n"
                "    value: 9999.99,\n"
                "    duration: Duration(milliseconds: 800),\n"
                "    textStyle: TextStyle(fontSize: 32),\n"
                "  );\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'INR (??',
              child: AnimatedCounter.inr(
                value: 1234567.89,
                duration: const Duration(milliseconds: 800),
                textStyle: const TextStyle(fontSize: 32),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => AnimatedCounter.inr(\n"
                "    value: 1234567.89,\n"
                "    duration: Duration(milliseconds: 800),\n"
                "    textStyle: TextStyle(fontSize: 32),\n"
                "  );\n"
                "}",
              ),
            ),
          ]),

          // ?�?� AnimatedCounter ??Bounce ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�
          DemoSection(title: 'AnimatedCounter ??Bounce', children: [
            DemoCard(
              title: 'Bounce overshoot',
              child: _CyclingAnimatedCounter(
                transitionType: CounterTransitionType.roll,
                bounceOvershoot: 0.67,
                bounceElasticity: 4.0,
              ),
              code: runnable(
                "class _Demo extends StatefulWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  State<_Demo> createState() => _DemoState();\n"
                "}\n"
                "\n"
                "class _DemoState extends State<_Demo> {\n"
                "  final _ctrl = AnimatedCounterController(initialValue: 0);\n"
                "  final _values = [0, 99, 42, 1000, 7];\n"
                "  int _idx = 0;\n"
                "\n"
                "  @override\n"
                "  void dispose() { _ctrl.dispose(); super.dispose(); }\n"
                "\n"
                "  @override\n"
                "  Widget build(BuildContext context) {\n"
                "    return Column(\n"
                "      mainAxisSize: MainAxisSize.min,\n"
                "      children: [\n"
                "        AnimatedCounter(\n"
                "          controller: _ctrl,\n"
                "          transitionType: CounterTransitionType.roll,\n"
                "          bounceOvershoot: 0.67,\n"
                "          bounceElasticity: 4.0,\n"
                "          duration: Duration(milliseconds: 600),\n"
                "          textStyle: TextStyle(fontSize: 48),\n"
                "        ),\n"
                "        const SizedBox(height: 12),\n"
                "        ElevatedButton(\n"
                "          onPressed: () {\n"
                "            _idx = (_idx + 1) % _values.length;\n"
                "            _ctrl.animateTo(_values[_idx]);\n"
                "          },\n"
                "          child: const Text('Next'),\n"
                "        ),\n"
                "      ],\n"
                "    );\n"
                "  }\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'High elasticity',
              description: 'Peak near end of transition (elasticity 8)',
              child: _CyclingAnimatedCounter(
                transitionType: CounterTransitionType.roll,
                bounceOvershoot: 0.67,
                bounceElasticity: 8.0,
              ),
              code: runnable(
                "class _Demo extends StatefulWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  State<_Demo> createState() => _DemoState();\n"
                "}\n"
                "\n"
                "class _DemoState extends State<_Demo> {\n"
                "  final _ctrl = AnimatedCounterController(initialValue: 0);\n"
                "  final _values = [0, 99, 42, 1000, 7];\n"
                "  int _idx = 0;\n"
                "\n"
                "  @override\n"
                "  void dispose() { _ctrl.dispose(); super.dispose(); }\n"
                "\n"
                "  @override\n"
                "  Widget build(BuildContext context) {\n"
                "    return Column(\n"
                "      mainAxisSize: MainAxisSize.min,\n"
                "      children: [\n"
                "        AnimatedCounter(\n"
                "          controller: _ctrl,\n"
                "          transitionType: CounterTransitionType.roll,\n"
                "          bounceOvershoot: 0.67,\n"
                "          bounceElasticity: 8.0,\n"
                "          duration: Duration(milliseconds: 600),\n"
                "          textStyle: TextStyle(fontSize: 48),\n"
                "        ),\n"
                "        const SizedBox(height: 12),\n"
                "        ElevatedButton(\n"
                "          onPressed: () {\n"
                "            _idx = (_idx + 1) % _values.length;\n"
                "            _ctrl.animateTo(_values[_idx]);\n"
                "          },\n"
                "          child: const Text('Next'),\n"
                "        ),\n"
                "      ],\n"
                "    );\n"
                "  }\n"
                "}",
              ),
            ),
          ]),

          // ?�?� AnimatedCounter ??Controller ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�
          DemoSection(title: 'AnimatedCounter ??Controller', children: [
            DemoCard(
              title: 'animateTo()',
              description: 'Buttons animate to preset values',
              child: _AnimateToDemo(),
              code: runnable(
                "class _Demo extends StatefulWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  State<_Demo> createState() => _DemoState();\n"
                "}\n"
                "\n"
                "class _DemoState extends State<_Demo> {\n"
                "  final _ctrl = AnimatedCounterController(initialValue: 0);\n"
                "\n"
                "  @override\n"
                "  void dispose() { _ctrl.dispose(); super.dispose(); }\n"
                "\n"
                "  @override\n"
                "  Widget build(BuildContext context) {\n"
                "    return Column(\n"
                "      mainAxisSize: MainAxisSize.min,\n"
                "      children: [\n"
                "        AnimatedCounter(\n"
                "          controller: _ctrl,\n"
                "          duration: Duration(milliseconds: 700),\n"
                "          textStyle: TextStyle(fontSize: 48),\n"
                "        ),\n"
                "        const SizedBox(height: 12),\n"
                "        Wrap(\n"
                "          spacing: 8,\n"
                "          children: [\n"
                "            for (final v in [0, 100, 500, 9999])\n"
                "              ElevatedButton(\n"
                "                onPressed: () => _ctrl.animateTo(v),\n"
                "                child: Text('\$v'),\n"
                "              ),\n"
                "          ],\n"
                "        ),\n"
                "      ],\n"
                "    );\n"
                "  }\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'pause / resume',
              description: 'Pause and resume mid-animation',
              child: _PauseResumeDemo(),
              code: runnable(
                "class _Demo extends StatefulWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  State<_Demo> createState() => _DemoState();\n"
                "}\n"
                "\n"
                "class _DemoState extends State<_Demo> {\n"
                "  final _ctrl = AnimatedCounterController(initialValue: 0);\n"
                "  bool _paused = false;\n"
                "\n"
                "  @override\n"
                "  void initState() {\n"
                "    super.initState();\n"
                "    _ctrl.animateTo(9999);\n"
                "  }\n"
                "\n"
                "  @override\n"
                "  void dispose() { _ctrl.dispose(); super.dispose(); }\n"
                "\n"
                "  @override\n"
                "  Widget build(BuildContext context) {\n"
                "    return Column(\n"
                "      mainAxisSize: MainAxisSize.min,\n"
                "      children: [\n"
                "        AnimatedCounter(\n"
                "          controller: _ctrl,\n"
                "          duration: Duration(seconds: 5),\n"
                "          textStyle: TextStyle(fontSize: 48),\n"
                "        ),\n"
                "        const SizedBox(height: 12),\n"
                "        Row(\n"
                "          mainAxisSize: MainAxisSize.min,\n"
                "          children: [\n"
                "            ElevatedButton(\n"
                "              onPressed: () {\n"
                "                setState(() => _paused = true);\n"
                "                _ctrl.pause();\n"
                "              },\n"
                "              child: const Text('Pause'),\n"
                "            ),\n"
                "            const SizedBox(width: 8),\n"
                "            ElevatedButton(\n"
                "              onPressed: () {\n"
                "                setState(() => _paused = false);\n"
                "                _ctrl.resume();\n"
                "              },\n"
                "              child: const Text('Resume'),\n"
                "            ),\n"
                "          ],\n"
                "        ),\n"
                "      ],\n"
                "    );\n"
                "  }\n"
                "}",
              ),
            ),
          ]),

          // ?�?� AnimatedCounterBuilder ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�
          DemoSection(title: 'AnimatedCounterBuilder', children: [
            DemoCard(
              title: 'Custom digitBuilder',
              description: 'Each digit rendered as a colored box',
              child: _CustomDigitBuilderDemo(),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "\n"
                "  static const _colors = [\n"
                "    Colors.red, Colors.orange, Colors.yellow, Colors.green,\n"
                "    Colors.teal, Colors.blue, Colors.indigo, Colors.purple,\n"
                "    Colors.pink, Colors.brown,\n"
                "  ];\n"
                "\n"
                "  @override\n"
                "  Widget build(BuildContext context) => AnimatedCounterBuilder(\n"
                "    value: 5678,\n"
                "    duration: Duration(milliseconds: 800),\n"
                "    textStyle: TextStyle(fontSize: 32, color: Colors.white),\n"
                "    digitBuilder: (_, digit, style) => Container(\n"
                "      width: 40,\n"
                "      height: 52,\n"
                "      margin: EdgeInsets.symmetric(horizontal: 2),\n"
                "      decoration: BoxDecoration(\n"
                "        color: _colors[digit],\n"
                "        borderRadius: BorderRadius.circular(8),\n"
                "      ),\n"
                "      alignment: Alignment.center,\n"
                "      child: Text('\$digit', style: style),\n"
                "    ),\n"
                "  );\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'Custom transition',
              description: 'digitTransitionBuilder with scale + opacity effect',
              child: _CustomTransitionDemo(),
              code: runnable(
                "import 'dart:ui';\n"
                "\n"
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "\n"
                "  @override\n"
                "  Widget build(BuildContext context) => AnimatedCounterBuilder(\n"
                "    value: 9876,\n"
                "    duration: Duration(milliseconds: 800),\n"
                "    textStyle: TextStyle(fontSize: 44),\n"
                "    digitTransitionBuilder: (ctx, current, next, progress, size) {\n"
                "      return Stack(\n"
                "        alignment: Alignment.center,\n"
                "        children: [\n"
                "          Opacity(\n"
                "            opacity: (1.0 - progress).clamp(0.0, 1.0),\n"
                "            child: Transform.scale(\n"
                "              scale: 1.0 - progress * 0.4,\n"
                "              child: current,\n"
                "            ),\n"
                "          ),\n"
                "          Opacity(\n"
                "            opacity: progress.clamp(0.0, 1.0),\n"
                "            child: Transform.scale(\n"
                "              scale: 0.6 + progress * 0.4,\n"
                "              child: next,\n"
                "            ),\n"
                "          ),\n"
                "        ],\n"
                "      );\n"
                "    },\n"
                "  );\n"
                "}",
              ),
            ),
          ]),

          // ?�?� CounterProvider ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�
          DemoSection(title: 'CounterProvider', children: [
            DemoCard(
              title: 'Cascaded defaults',
              description:
                  'Provider sets duration + colors for all descendants',
              child: CounterProvider(
                duration: const Duration(seconds: 2),
                color: Colors.deepPurple,
                trackColor: Colors.deepPurple.withValues(alpha: 0.15),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CounterRing(to: 100, style: CounterRingStyle(size: 80)),
                    SizedBox(height: 16),
                    CounterBar(
                        to: 100,
                        style: CounterBarStyle(width: 200, height: 10)),
                  ],
                ),
              ),
              code: runnable(
                "class _Demo extends StatelessWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  Widget build(BuildContext context) => CounterProvider(\n"
                "    duration: Duration(seconds: 2),\n"
                "    color: Colors.deepPurple,\n"
                "    trackColor: Colors.deepPurple.withOpacity(0.15),\n"
                "    child: Column(\n"
                "      mainAxisSize: MainAxisSize.min,\n"
                "      children: [\n"
                "        CounterRing(to: 100, size: 80),\n"
                "        SizedBox(height: 16),\n"
                "        CounterBar(to: 100, width: 200, height: 10),\n"
                "      ],\n"
                "    ),\n"
                "  );\n"
                "}",
              ),
            ),

            DemoCard(
              title: 'Group callbacks',
              description: 'onGroupReady / onAllComplete via status Text',
              child: _CounterProviderGroupCallbacksDemo(),
              code: runnable(
                "class _Demo extends StatefulWidget {\n"
                "  const _Demo({super.key});\n"
                "  @override\n"
                "  State<_Demo> createState() => _DemoState();\n"
                "}\n"
                "\n"
                "class _DemoState extends State<_Demo> {\n"
                "  String _status = 'idle';\n"
                "\n"
                "  @override\n"
                "  Widget build(BuildContext context) {\n"
                "    return Column(\n"
                "      mainAxisSize: MainAxisSize.min,\n"
                "      children: [\n"
                "        Text('Group: \$_status',\n"
                "            style: TextStyle(fontWeight: FontWeight.bold)),\n"
                "        const SizedBox(height: 12),\n"
                "        CounterProvider(\n"
                "          duration: Duration(seconds: 2),\n"
                "          onGroupReady: () =>\n"
                "              setState(() => _status = 'animating'),\n"
                "          onAllComplete: () =>\n"
                "              setState(() => _status = 'complete'),\n"
                "          child: Row(\n"
                "            mainAxisSize: MainAxisSize.min,\n"
                "            children: [\n"
                "              CounterRing(to: 75, size: 70),\n"
                "              SizedBox(width: 16),\n"
                "              CounterRing(to: 50, size: 70),\n"
                "            ],\n"
                "          ),\n"
                "        ),\n"
                "      ],\n"
                "    );\n"
                "  }\n"
                "}",
              ),
            ),
          ]),
        ],
        ),    // ListView
      ),      // KeyedSubtree
      ),      // PageSectionCounter
    );
  }
}

// ?�?� Helper StatefulWidgets ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�

/// CounterText with onComplete snackbar.
class _CounterTextOnComplete extends StatefulWidget {
  const _CounterTextOnComplete();
  @override
  State<_CounterTextOnComplete> createState() => _CounterTextOnCompleteState();
}

class _CounterTextOnCompleteState extends State<_CounterTextOnComplete> {
  int _seed = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        KeyedSubtree(
          key: ValueKey(_seed),
          child: CounterText(
            from: 0,
            to: 100,
            style: CounterTextStyle(textStyle: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
            onComplete: (_) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Done!')),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: () => setState(() => _seed++),
          child: const Text('Replay'),
        ),
      ],
    );
  }
}

/// Cycles through preset values on button press using AnimatedCounterController.
class _CyclingAnimatedCounter extends StatefulWidget {
  final CounterTransitionType transitionType;
  final double bounceOvershoot;
  final double bounceElasticity;

  const _CyclingAnimatedCounter({
    required this.transitionType,
    this.bounceOvershoot = 0.0,
    this.bounceElasticity = 4.0,
  });

  @override
  State<_CyclingAnimatedCounter> createState() =>
      _CyclingAnimatedCounterState();
}

class _CyclingAnimatedCounterState extends State<_CyclingAnimatedCounter> {
  final _ctrl = AnimatedCounterController(initialValue: 0);
  final _values = [0, 99, 42, 1000, 7];
  int _idx = 0;
  Timer? _autoTimer;

  @override
  void initState() {
    super.initState();
    // Auto-start the first cycle so bounce is immediately visible.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _advance();
    });
    // Auto-cycle every 2 s so the demo keeps playing.
    _autoTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) _advance();
    });
  }

  void _advance() {
    _idx = (_idx + 1) % _values.length;
    _ctrl.animateTo(_values[_idx].toDouble());
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedCounter(
          controller: _ctrl,
          transitionType: widget.transitionType,
          bounceOvershoot: widget.bounceOvershoot,
          bounceElasticity: widget.bounceElasticity,
          duration: const Duration(milliseconds: 600),
          textStyle: const TextStyle(fontSize: 48),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _advance,
          child: const Text('Next'),
        ),
      ],
    );
  }
}

/// Same cycling pattern but using AnimatedCounterBuilder (for blur transition).
class _CyclingAnimatedCounterBuilder extends StatefulWidget {
  final CounterTransitionType transitionType;

  const _CyclingAnimatedCounterBuilder({required this.transitionType});

  @override
  State<_CyclingAnimatedCounterBuilder> createState() =>
      _CyclingAnimatedCounterBuilderState();
}

class _CyclingAnimatedCounterBuilderState
    extends State<_CyclingAnimatedCounterBuilder> {
  final _ctrl = AnimatedCounterController(initialValue: 0);
  final _values = [0, 99, 42, 1000, 7];
  int _idx = 0;
  Timer? _autoTimer;

  void _advance() {
    _idx = (_idx + 1) % _values.length;
    _ctrl.animateTo(_values[_idx].toDouble());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _advance(); });
    _autoTimer = Timer.periodic(const Duration(seconds: 2), (_) { if (mounted) _advance(); });
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedCounterBuilder(
          controller: _ctrl,
          transitionType: widget.transitionType,
          duration: const Duration(milliseconds: 600),
          textStyle: const TextStyle(fontSize: 48),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _advance,
          child: const Text('Next'),
        ),
      ],
    );
  }
}

/// animateTo() with multiple preset buttons.
class _AnimateToDemo extends StatefulWidget {
  const _AnimateToDemo();
  @override
  State<_AnimateToDemo> createState() => _AnimateToDemoState();
}

class _AnimateToDemoState extends State<_AnimateToDemo> {
  final _ctrl = AnimatedCounterController(initialValue: 0);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedCounter(
          controller: _ctrl,
          duration: const Duration(milliseconds: 700),
          textStyle: const TextStyle(fontSize: 48),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final v in [0, 100, 500, 9999])
              ElevatedButton(
                onPressed: () => _ctrl.animateTo(v),
                child: Text('$v'),
              ),
          ],
        ),
      ],
    );
  }
}

/// pause / resume demo.
class _PauseResumeDemo extends StatefulWidget {
  const _PauseResumeDemo();
  @override
  State<_PauseResumeDemo> createState() => _PauseResumeDemoState();
}

class _PauseResumeDemoState extends State<_PauseResumeDemo> {
  final _ctrl = AnimatedCounterController(initialValue: 0);
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _ctrl.animateTo(9999);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedCounter(
          controller: _ctrl,
          duration: const Duration(seconds: 5),
          textStyle: const TextStyle(fontSize: 48),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: _paused
                  ? null
                  : () {
                      setState(() => _paused = true);
                      _ctrl.pause();
                    },
              child: const Text('Pause'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: !_paused
                  ? null
                  : () {
                      setState(() => _paused = false);
                      _ctrl.resume();
                    },
              child: const Text('Resume'),
            ),
          ],
        ),
      ],
    );
  }
}

/// AnimatedCounterBuilder with a colored box digitBuilder.
class _CustomDigitBuilderDemo extends StatelessWidget {
  const _CustomDigitBuilderDemo();

  static const _colors = [
    Colors.red, Colors.orange, Colors.yellow, Colors.green,
    Colors.teal, Colors.blue, Colors.indigo, Colors.purple,
    Colors.pink, Colors.brown,
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedCounterBuilder(
      value: 5678,
      duration: const Duration(milliseconds: 800),
      textStyle: const TextStyle(fontSize: 32, color: Colors.white),
      digitBuilder: (_, digit, style) => Container(
        width: 40,
        height: 52,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: _colors[digit],
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text('$digit', style: style),
      ),
    );
  }
}

/// AnimatedCounterBuilder with a scale+opacity digitTransitionBuilder.
class _CustomTransitionDemo extends StatelessWidget {
  const _CustomTransitionDemo();

  @override
  Widget build(BuildContext context) {
    return AnimatedCounterBuilder(
      value: 9876,
      duration: const Duration(milliseconds: 800),
      textStyle: const TextStyle(fontSize: 44),
      digitTransitionBuilder: (ctx, current, next, progress, size) {
        return Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: (1.0 - progress).clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 1.0 - progress * 0.4,
                child: current,
              ),
            ),
            Opacity(
              opacity: progress.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 0.6 + progress * 0.4,
                child: next,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Cycles through [1000, 7, 42, 999] to demonstrate numberAlignment.
class _AlignmentCycler extends StatefulWidget {
  const _AlignmentCycler({required this.numberAlignment});
  final double numberAlignment;
  @override
  State<_AlignmentCycler> createState() => _AlignmentCyclerState();
}

class _AlignmentCyclerState extends State<_AlignmentCycler> {
  final _ctrl = AnimatedCounterController(initialValue: 1000);
  final _vals = [1000, 7, 42, 999];
  int _i = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedCounter(
          controller: _ctrl,
          numberAlignment: widget.numberAlignment,
          textStyle: const TextStyle(fontSize: 40),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: () {
            _i = (_i + 1) % _vals.length;
            _ctrl.animateTo(_vals[_i].toDouble());
          },
          child: const Text('Next'),
        ),
      ],
    );
  }
}

/// CounterProvider group callbacks demo.
class _CounterProviderGroupCallbacksDemo extends StatefulWidget {
  const _CounterProviderGroupCallbacksDemo();
  @override
  State<_CounterProviderGroupCallbacksDemo> createState() =>
      _CounterProviderGroupCallbacksDemoState();
}

class _CounterProviderGroupCallbacksDemoState
    extends State<_CounterProviderGroupCallbacksDemo> {
  String _status = 'idle';

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Group: $_status',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        CounterProvider(
          plugin: defaultCounter, // explicit plugin avoids same-name conflict in Countman.use
          duration: const Duration(seconds: 2),
          onGroupReady: () { WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) setState(() => _status = 'animating'); }); },
          onAllComplete: () { WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) setState(() => _status = 'complete'); }); },
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CounterRing(to: 75, style: CounterRingStyle(size: 70)),
              SizedBox(width: 16),
              CounterRing(to: 50, style: CounterRingStyle(size: 70)),
            ],
          ),
        ),
      ],
    );
  }
}


