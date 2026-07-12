import 'package:flutter/material.dart';
import 'package:countman/countman.dart';
// ignore: implementation_imports
import 'package:countman/src/widgets/countdown_dial.dart';
import 'demo_card.dart';

class CountdownPage extends StatefulWidget {
  const CountdownPage({super.key});
  @override
  State<CountdownPage> createState() => _CountdownPageState();
}

class _CountdownPageState extends State<CountdownPage> {
  int _resetKey = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Countdown'),
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
            _builderSection(),
            _textSection(),
            _ringSection(),
            _barSection(),
            _dialSection(),
            _cardSection(),
            _providerSection(),
          ],
        ),
      ),
      ),    // PageSectionCounter
    );
  }
}

// ── Section builders ──────────────────────────────────────────────────────────

Widget _builderSection() => DemoSection(
      title: 'CountdownBuilder',
      children: [
        // 1 — Fixed duration
        DemoCard(
          title: 'Fixed duration',
          description: 'Shows MM:SS from a Duration.',
          code: runnable(r'''
class _Demo extends StatelessWidget {
  const _Demo();
  @override
  Widget build(BuildContext context) {
    return CountdownBuilder(
      duration: const Duration(minutes: 5),
      builder: (context, parts, _) {
        final m = parts.totalMinutes.toString().padLeft(2, '0');
        final s = parts.seconds.toString().padLeft(2, '0');
        return Text(
          '$m:$s',
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
        );
      },
    );
  }
}
'''),
          child: CountdownBuilder(
            duration: const Duration(minutes: 5),
            builder: (_, parts, __) {
              final m = parts.totalMinutes.toString().padLeft(2, '0');
              final s = parts.seconds.toString().padLeft(2, '0');
              return Text(
                '$m:$s',
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              );
            },
          ),
        ),

        // 2 — Target DateTime
        DemoCard(
          title: 'Target DateTime',
          description: 'Counts down to a specific DateTime (2 hours away).',
          code: runnable(r'''
class _Demo extends StatelessWidget {
  const _Demo();
  @override
  Widget build(BuildContext context) {
    return CountdownBuilder(
      to: DateTime.now().add(const Duration(hours: 2)),
      builder: (context, parts, _) {
        final h = parts.totalHours.toString().padLeft(2, '0');
        final m = parts.minutes.toString().padLeft(2, '0');
        final s = parts.seconds.toString().padLeft(2, '0');
        return Text(
          '$h:$m:$s',
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
        );
      },
    );
  }
}
'''),
          child: CountdownBuilder(
            to: DateTime.now().add(const Duration(hours: 2)),
            builder: (_, parts, __) {
              final h = parts.totalHours.toString().padLeft(2, '0');
              final m = parts.minutes.toString().padLeft(2, '0');
              final s = parts.seconds.toString().padLeft(2, '0');
              return Text(
                '$h:$m:$s',
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              );
            },
          ),
        ),

        // 3 — Pause / Resume / Reset
        DemoCard(
          title: 'Pause / Resume / Reset',
          description: 'CountdownController wires up imperative controls.',
          code: runnable(r'''
class _Demo extends StatefulWidget {
  const _Demo();
  @override
  State<_Demo> createState() => _DemoState();
}

class _DemoState extends State<_Demo> {
  final _ctrl = CountdownController();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CountdownBuilder(
          duration: const Duration(minutes: 2),
          controller: _ctrl,
          builder: (context, parts, _) {
            final m = parts.totalMinutes.toString().padLeft(2, '0');
            final s = parts.seconds.toString().padLeft(2, '0');
            return Text(
              '$m:$s',
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            );
          },
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: _ctrl.pause,
              child: const Text('Pause'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _ctrl.resume,
              child: const Text('Resume'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _ctrl.reset,
              child: const Text('Reset'),
            ),
          ],
        ),
      ],
    );
  }
}
'''),
          child: _ControllerBuilderDemo(),
        ),

        // 4 — Threshold callback
        DemoCard(
          title: 'Threshold callback',
          description: 'Text turns red when 10 seconds remain.',
          code: runnable(r'''
class _Demo extends StatefulWidget {
  const _Demo();
  @override
  State<_Demo> createState() => _DemoState();
}

class _DemoState extends State<_Demo> {
  bool _urgent = false;

  @override
  Widget build(BuildContext context) {
    return CountdownBuilder(
      duration: const Duration(seconds: 30),
      threshold: const Duration(seconds: 10),
      onThreshold: () { if (mounted) setState(() => _urgent = true); },
      builder: (context, parts, _) {
        final m = parts.totalMinutes.toString().padLeft(2, '0');
        final s = parts.seconds.toString().padLeft(2, '0');
        return Text(
          '$m:$s',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: _urgent ? Colors.red : null,
          ),
        );
      },
    );
  }
}
'''),
          child: _ThresholdDemo(),
        ),

        // 5 — onComplete callback
        DemoCard(
          title: 'onComplete callback',
          description: 'Shows "Done!" overlay when the countdown finishes.',
          code: runnable(r'''
class _Demo extends StatefulWidget {
  const _Demo();
  @override
  State<_Demo> createState() => _DemoState();
}

class _DemoState extends State<_Demo> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        CountdownBuilder(
          duration: const Duration(seconds: 10),
          onComplete: () { if (mounted) setState(() => _done = true); },
          builder: (context, parts, _) {
            final s = parts.totalSeconds.toString().padLeft(2, '0');
            return Text(
              '00:$s',
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            );
          },
        ),
        if (_done)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Done!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }
}
'''),
          child: _OnCompleteDemo(),
        ),

        // 6 — Custom builder clock face
        DemoCard(
          title: 'Custom builder — clock face',
          description: 'Hours, minutes, and seconds in separate boxes.',
          code: runnable(r'''
class _Demo extends StatelessWidget {
  const _Demo();
  @override
  Widget build(BuildContext context) {
    return CountdownBuilder(
      duration: const Duration(hours: 1, minutes: 23, seconds: 45),
      builder: (context, parts, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ClockBox(value: parts.hours, label: 'H'),
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(':', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            ),
            _ClockBox(value: parts.minutes, label: 'M'),
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(':', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            ),
            _ClockBox(value: parts.seconds, label: 'S'),
          ],
        );
      },
    );
  }
}

class _ClockBox extends StatelessWidget {
  const _ClockBox({required this.value, required this.label});
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value.toString().padLeft(2, '0'),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}
'''),
          child: CountdownBuilder(
            duration: const Duration(hours: 1, minutes: 23, seconds: 45),
            builder: (_, parts, __) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ClockBox(value: parts.hours, label: 'H'),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text(
                      ':',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                  ),
                  _ClockBox(value: parts.minutes, label: 'M'),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text(
                      ':',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                  ),
                  _ClockBox(value: parts.seconds, label: 'S'),
                ],
              );
            },
          ),
        ),

        // 7 — Millisecond precision
        DemoCard(
          title: 'Millisecond precision',
          description: 'Countdown(interval: 1000 ~/ 60) ticks at ~60 fps; '
              'CountdownFormat.msMillis shows MM:SS.mmm.',
          code: runnable(r'''
final _plugin = Countdown(name: 'ms', interval: 1000 ~/ 60);

class _Demo extends StatefulWidget {
  const _Demo();
  @override
  State<_Demo> createState() => _DemoState();
}

class _DemoState extends State<_Demo> {
  @override
  void initState() {
    super.initState();
    Countman.use(_plugin);
  }

  @override
  Widget build(BuildContext context) {
    return CountdownBuilder(
      duration: const Duration(seconds: 10),
      plugin: _plugin,
      builder: (context, parts, _) => Text(
        CountdownFormat.msMillis(parts),
        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
      ),
    );
  }
}
'''),
          child: _MsBuilderDemo(),
        ),
      ],
    );

Widget _textSection() => DemoSection(
      title: 'CountdownText',
      children: [
        // 1 — Auto format (hms)
        DemoCard(
          title: 'Auto format (hms)',
          description: 'CountdownFormat.auto picks the most compact format.',
          code: runnable(r'''
class _Demo extends StatelessWidget {
  const _Demo();
  @override
  Widget build(BuildContext context) {
    return CountdownText(
      to: const Duration(hours: 1, minutes: 30),
      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
    );
  }
}
'''),
          child: const CountdownText(
            to: Duration(hours: 1, minutes: 30),
            style: CountdownTextStyle(textStyle: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          ),
        ),

        // 2 — MM:SS format
        DemoCard(
          title: 'MM:SS format',
          description: 'CountdownFormat.ms shows minutes and seconds.',
          code: runnable(r'''
class _Demo extends StatelessWidget {
  const _Demo();
  @override
  Widget build(BuildContext context) {
    return CountdownText(
      to: const Duration(minutes: 3, seconds: 45),
      formatter: CountdownFormat.ms,
      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
    );
  }
}
'''),
          child: const CountdownText(
            to: Duration(minutes: 3, seconds: 45),
            formatter: CountdownFormat.ms,
            style: CountdownTextStyle(textStyle: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          ),
        ),

        // 3 — Tenths format
        DemoCard(
          title: 'Tenths format',
          description: 'CountdownFormat.msTenths shows sub-second tenths.',
          code: runnable(r'''
class _Demo extends StatelessWidget {
  const _Demo();
  @override
  Widget build(BuildContext context) {
    return CountdownText(
      to: const Duration(seconds: 30),
      formatter: CountdownFormat.msTenths,
      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
    );
  }
}
'''),
          child: const CountdownText(
            to: Duration(seconds: 30),
            formatter: CountdownFormat.msTenths,
            style: CountdownTextStyle(textStyle: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          ),
        ),

        // 4 — Custom formatter
        DemoCard(
          title: 'Custom formatter',
          description: 'A formatter closure builds any string from TimeParts.',
          code: runnable(r'''
class _Demo extends StatelessWidget {
  const _Demo();
  @override
  Widget build(BuildContext context) {
    return CountdownText(
      to: const Duration(minutes: 5),
      formatter: (parts) {
        if (parts.totalSeconds == 0) return 'Time up!';
        return '${parts.totalSeconds}s left';
      },
      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
    );
  }
}
'''),
          child: CountdownText(
            to: const Duration(minutes: 5),
            formatter: (parts) {
              if (parts.totalSeconds == 0) return 'Time up!';
              return '${parts.totalSeconds}s left';
            },
            style: CountdownTextStyle(textStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          ),
        ),

        // 5 — Target ISO-8601 string
        DemoCard(
          title: 'Target ISO-8601 string',
          description: 'The `to` param accepts an ISO-8601 String directly.',
          code: runnable(r'''
class _Demo extends StatelessWidget {
  const _Demo();
  @override
  Widget build(BuildContext context) {
    final target = DateTime.now().add(const Duration(hours: 1)).toIso8601String();
    return CountdownText(
      to: target,
      formatter: CountdownFormat.hms,
      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
    );
  }
}
'''),
          child: CountdownText(
            to: DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
            formatter: CountdownFormat.hms,
            style: CountdownTextStyle(textStyle: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          ),
        ),

        // 6 — onThreshold style change
        DemoCard(
          title: 'onThreshold style change',
          description: 'Text style changes when 5 seconds remain.',
          code: runnable(r'''
class _Demo extends StatefulWidget {
  const _Demo();
  @override
  State<_Demo> createState() => _DemoState();
}

class _DemoState extends State<_Demo> {
  bool _urgent = false;

  @override
  Widget build(BuildContext context) {
    return CountdownText(
      to: const Duration(seconds: 20),
      formatter: CountdownFormat.ms,
      threshold: const Duration(seconds: 5),
      onThreshold: () { if (mounted) setState(() => _urgent = true); },
      style: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: _urgent ? Colors.red : null,
        letterSpacing: _urgent ? 2 : 0,
      ),
    );
  }
}
'''),
          child: _ThresholdTextDemo(),
        ),
      ],
    );

Widget _ringSection() => DemoSection(
      title: 'CountdownRing',
      children: [
        // 1 — Basic
        DemoCard(
          title: 'Basic',
          description: 'Minimal CountdownRing with default theme colors.',
          code: runnable(r'''
class _Demo extends StatelessWidget {
  const _Demo();
  @override
  Widget build(BuildContext context) {
    return CountdownRing(
      to: const Duration(minutes: 2),
      size: 100,
    );
  }
}
'''),
          child: const CountdownRing(
            to: Duration(minutes: 2),
            style: CountdownRingStyle(size: 100),
          ),
        ),

        // 2 — With center text
        DemoCard(
          title: 'With center text',
          description: 'A CountdownText widget sits in the ring center.',
          code: runnable(r'''
class _Demo extends StatelessWidget {
  const _Demo();
  @override
  Widget build(BuildContext context) {
    return CountdownRing(
      to: const Duration(minutes: 2),
      size: 110,
      center: const CountdownText(
        to: Duration(minutes: 2),
        formatter: CountdownFormat.ms,
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }
}
'''),
          child: const CountdownRing(
            to: Duration(minutes: 2),
            style: CountdownRingStyle(size: 110),
            center: CountdownText(
              to: Duration(minutes: 2),
              formatter: CountdownFormat.ms,
              style: CountdownTextStyle(textStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
        ),

        // 3 — Custom colors
        DemoCard(
          title: 'Custom colors',
          description: 'deepOrange arc on a faded orange track.',
          code: runnable(r'''
class _Demo extends StatelessWidget {
  const _Demo();
  @override
  Widget build(BuildContext context) {
    return CountdownRing(
      to: const Duration(minutes: 2),
      size: 100,
      strokeWidth: 12,
      color: Colors.deepOrange,
      trackColor: Colors.orange.withValues(alpha: 0.2),
    );
  }
}
'''),
          child: CountdownRing(
            to: const Duration(minutes: 2),
            style: CountdownRingStyle(
              size: 100,
              strokeWidth: 12,
              color: Colors.deepOrange,
              trackColor: Colors.orange.withValues(alpha: 0.2),
            ),
          ),
        ),

        // 4 — Gradient arc
        DemoCard(
          title: 'Gradient arc',
          description: 'A SweepGradient paints the arc.',
          code: runnable(r'''
class _Demo extends StatelessWidget {
  const _Demo();
  @override
  Widget build(BuildContext context) {
    return CountdownRing(
      to: const Duration(minutes: 2),
      size: 100,
      strokeWidth: 10,
      gradient: const SweepGradient(
        colors: [Colors.blue, Colors.purple, Colors.pink],
      ),
    );
  }
}
'''),
          child: const CountdownRing(
            to: Duration(minutes: 2),
            style: CountdownRingStyle(
              size: 100,
              strokeWidth: 10,
              gradient: SweepGradient(
                colors: [Colors.blue, Colors.purple, Colors.pink],
              ),
            ),
          ),
        ),

        // 5 — Anti-clockwise
        DemoCard(
          title: 'Anti-clockwise',
          description: 'clockwise: false reverses the arc direction.',
          code: runnable(r'''
class _Demo extends StatelessWidget {
  const _Demo();
  @override
  Widget build(BuildContext context) {
    return CountdownRing(
      to: const Duration(minutes: 2),
      size: 100,
      clockwise: false,
    );
  }
}
'''),
          child: const CountdownRing(
            to: Duration(minutes: 2),
            style: CountdownRingStyle(
              size: 100,
              clockwise: false,
            ),
          ),
        ),

        // 6 — Controller
        DemoCard(
          title: 'Controller',
          description: 'Pause / resume the ring from outside.',
          code: runnable(r'''
class _Demo extends StatefulWidget {
  const _Demo();
  @override
  State<_Demo> createState() => _DemoState();
}

class _DemoState extends State<_Demo> {
  final _ctrl = CountdownController();
  bool _paused = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CountdownRing(
          to: const Duration(minutes: 2),
          size: 100,
          controller: _ctrl,
          center: const CountdownText(
            to: Duration(minutes: 2),
            formatter: CountdownFormat.ms,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: () {
                if (_paused) {
                  _ctrl.resume();
                } else {
                  _ctrl.pause();
                }
                setState(() => _paused = !_paused);
              },
              child: Text(_paused ? 'Resume' : 'Pause'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () {
                _ctrl.reset();
                setState(() => _paused = false);
              },
              child: const Text('Reset'),
            ),
          ],
        ),
      ],
    );
  }
}
'''),
          child: _RingControllerDemo(),
        ),
      ],
    );

Widget _barSection() => DemoSection(
      title: 'CountdownBar',
      children: [
        // 1 — Basic
        DemoCard(
          title: 'Basic',
          description: 'A simple horizontal progress bar.',
          code: runnable(r'''
class _Demo extends StatelessWidget {
  const _Demo();
  @override
  Widget build(BuildContext context) {
    return CountdownBar(
      to: const Duration(minutes: 1),
      width: 250,
      height: 10,
    );
  }
}
'''),
          child: const CountdownBar(
            to: Duration(minutes: 1),
            style: CountdownBarStyle(width: 250, height: 10),
          ),
        ),

        // 2 — Gradient
        DemoCard(
          title: 'Gradient',
          description: 'LinearGradient flows from green to red.',
          code: runnable(r'''
class _Demo extends StatelessWidget {
  const _Demo();
  @override
  Widget build(BuildContext context) {
    return CountdownBar(
      to: const Duration(minutes: 1),
      width: 250,
      height: 10,
      gradient: const LinearGradient(
        colors: [Colors.green, Colors.yellow, Colors.red],
      ),
    );
  }
}
'''),
          child: const CountdownBar(
            to: Duration(minutes: 1),
            style: CountdownBarStyle(
              width: 250,
              height: 10,
              gradient: LinearGradient(
                colors: [Colors.green, Colors.yellow, Colors.red],
              ),
            ),
          ),
        ),

        // 3 — Fill from end
        DemoCard(
          title: 'Fill from end',
          description: 'fillFromStart: false anchors the fill to the right.',
          code: runnable(r'''
class _Demo extends StatelessWidget {
  const _Demo();
  @override
  Widget build(BuildContext context) {
    return CountdownBar(
      to: const Duration(minutes: 1),
      width: 250,
      height: 10,
      fillFromStart: false,
    );
  }
}
'''),
          child: const CountdownBar(
            to: Duration(minutes: 1),
            style: CountdownBarStyle(
              width: 250,
              height: 10,
              fillFromStart: false,
            ),
          ),
        ),

        // 4 — Tall track
        DemoCard(
          title: 'Tall track',
          description: 'Thin fill (6 dp) centered in a tall track (24 dp).',
          code: runnable(r'''
class _Demo extends StatelessWidget {
  const _Demo();
  @override
  Widget build(BuildContext context) {
    return CountdownBar(
      to: const Duration(minutes: 1),
      width: 250,
      height: 6,
      trackHeight: 24,
    );
  }
}
'''),
          child: const CountdownBar(
            to: Duration(minutes: 1),
            style: CountdownBarStyle(
              width: 250,
              height: 6,
              trackHeight: 24,
            ),
          ),
        ),

        // 5 — Rounded
        DemoCard(
          title: 'Rounded',
          description: 'A pill-shaped bar with circular end caps.',
          code: runnable(r'''
class _Demo extends StatelessWidget {
  const _Demo();
  @override
  Widget build(BuildContext context) {
    return CountdownBar(
      to: const Duration(minutes: 1),
      width: 250,
      height: 12,
      borderRadius: const Radius.circular(6),
    );
  }
}
'''),
          child: const CountdownBar(
            to: Duration(minutes: 1),
            style: CountdownBarStyle(
              width: 250,
              height: 12,
              borderRadius: Radius.circular(6),
            ),
          ),
        ),
      ],
    );

Widget _cardSection() => DemoSection(
      title: 'CountdownCard',
      children: [
        // 1 — Calendar style
        DemoCard(
          title: 'Calendar style',
          description: 'Split-flap calendar animation (default).',
          code: runnable(r'''
class _Demo extends StatelessWidget {
  const _Demo();
  @override
  Widget build(BuildContext context) {
    return CountdownCard(
      to: const Duration(hours: 1, minutes: 30),
      transitionType: CountdownType.calendar,
    );
  }
}
'''),
          child: const CountdownCard(
            to: Duration(hours: 1, minutes: 30),
            style: CountdownCardStyle(transitionType: CountdownType.calendar),
          ),
        ),

        // 2 — Slide transition
        DemoCard(
          title: 'Slide transition',
          description: 'Digits slide in and out; scaleEffect: SlideEffect.enter.',
          code: runnable(r'''
class _Demo extends StatelessWidget {
  const _Demo();
  @override
  Widget build(BuildContext context) {
    return CountdownCard(
      to: const Duration(hours: 1, minutes: 30),
      transitionType: CountdownType.slide,
      scaleEffect: SlideEffect.enter,
    );
  }
}
'''),
          child: const CountdownCard(
            to: Duration(hours: 1, minutes: 30),
            style: CountdownCardStyle(
              transitionType: CountdownType.slide,
              scaleEffect: SlideEffect.enter,
            ),
          ),
        ),

        // 3 — Flip 3D
        DemoCard(
          title: 'Flip 3D',
          description: 'Each card rotates around the X axis as a rigid plane.',
          code: runnable(r'''
class _Demo extends StatelessWidget {
  const _Demo();
  @override
  Widget build(BuildContext context) {
    return CountdownCard(
      to: const Duration(hours: 1, minutes: 30),
      transitionType: CountdownType.flip,
    );
  }
}
'''),
          child: const CountdownCard(
            to: Duration(hours: 1, minutes: 30),
            style: CountdownCardStyle(transitionType: CountdownType.flip),
          ),
        ),

        // 4 — Split digits
        DemoCard(
          title: 'Split digits',
          description: 'Each individual digit gets its own card.',
          code: runnable(r'''
class _Demo extends StatelessWidget {
  const _Demo();
  @override
  Widget build(BuildContext context) {
    return CountdownCard(
      to: const Duration(hours: 1, minutes: 30),
      splitDigits: true,
    );
  }
}
'''),
          child: const CountdownCard(
            to: Duration(hours: 1, minutes: 30),
            style: CountdownCardStyle(splitDigits: true),
          ),
        ),

        // 5 — No hours shown
        DemoCard(
          title: 'No hours shown',
          description: 'showHours: false forces MM:SS only.',
          code: runnable(r'''
class _Demo extends StatelessWidget {
  const _Demo();
  @override
  Widget build(BuildContext context) {
    return CountdownCard(
      to: const Duration(hours: 1, minutes: 30),
      showHours: false,
    );
  }
}
'''),
          child: const CountdownCard(
            to: Duration(hours: 1, minutes: 30),
            showHours: false,
          ),
        ),

        // 6 — Custom colors & style
        DemoCard(
          title: 'Custom colors & style',
          description: 'Deep blue cards with cyan digits and label text.',
          code: runnable(r'''
class _Demo extends StatelessWidget {
  const _Demo();
  @override
  Widget build(BuildContext context) {
    return CountdownCard(
      to: const Duration(hours: 1, minutes: 30),
      cardColor: const Color(0xFF1A237E),
      textStyle: const TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.bold,
        color: Colors.cyanAccent,
      ),
      labelStyle: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: Colors.cyanAccent,
        letterSpacing: 0.5,
      ),
    );
  }
}
'''),
          child: const CountdownCard(
            to: Duration(hours: 1, minutes: 30),
            style: CountdownCardStyle(
              cardColor: Color(0xFF1A237E),
              textStyle: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: Colors.cyanAccent,
              ),
              labelStyle: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: Colors.cyanAccent,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ],
    );

Widget _providerSection() => DemoSection(
      title: 'CountdownProvider',
      children: [
        // 1 — Cascaded defaults
        DemoCard(
          title: 'Cascaded defaults',
          description:
              'One provider cascades color + textStyle to ring, bar, and text.',
          code: runnable(r'''
class _Demo extends StatelessWidget {
  const _Demo();
  @override
  Widget build(BuildContext context) {
    return CountdownProvider(
      color: Colors.teal,
      trackColor: Colors.teal.withValues(alpha: 0.15),
      textStyle: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Colors.teal,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CountdownRing(
            to: const Duration(minutes: 3),
            size: 90,
            center: const CountdownText(
              to: Duration(minutes: 3),
              formatter: CountdownFormat.ms,
            ),
          ),
          const SizedBox(height: 12),
          const CountdownBar(
            to: Duration(minutes: 3),
            width: 200,
            height: 8,
          ),
          const SizedBox(height: 8),
          const CountdownText(
            to: Duration(minutes: 3),
            formatter: CountdownFormat.ms,
          ),
        ],
      ),
    );
  }
}
'''),
          child: CountdownProvider(
            color: Colors.teal,
            trackColor: Colors.teal.withValues(alpha: 0.15),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.teal,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CountdownRing(
                  to: Duration(minutes: 3),
                  style: CountdownRingStyle(size: 90),
                  center: CountdownText(
                    to: Duration(minutes: 3),
                    formatter: CountdownFormat.ms,
                  ),
                ),
                const SizedBox(height: 12),
                const CountdownBar(
                  to: Duration(minutes: 3),
                  style: CountdownBarStyle(width: 200, height: 8),
                ),
                const SizedBox(height: 8),
                const CountdownText(
                  to: Duration(minutes: 3),
                  formatter: CountdownFormat.ms,
                ),
              ],
            ),
          ),
        ),

        // 2 — Group callbacks
        DemoCard(
          title: 'Group callbacks',
          description:
              'onGroupReady fires when the first task starts; onAllComplete fires when the last task finishes.',
          code: runnable(r'''
class _Demo extends StatefulWidget {
  const _Demo();
  @override
  State<_Demo> createState() => _DemoState();
}

class _DemoState extends State<_Demo> {
  String _status = 'waiting';

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CountdownProvider(
          plugin: defaultCountdown,
          onGroupReady: () { WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) setState(() => _status = 'active'); }); },
          onAllComplete: () { WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) setState(() => _status = 'all done'); }); },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              CountdownText(
                to: Duration(seconds: 8),
                formatter: CountdownFormat.ms,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              CountdownText(
                to: Duration(seconds: 12),
                formatter: CountdownFormat.ms,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.circle, size: 10),
            const SizedBox(width: 6),
            Text(
              'Group: $_status',
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      ],
    );
  }
}
'''),
          child: _GroupCallbacksDemo(),
        ),
      ],
    );

// ── StatefulWidget demos ──────────────────────────────────────────────────────

// Module-level singleton so Countman.use() is called once with the same
// instance; creating a new Countdown on every initState would fail on reset
// because Countman.use() silently ignores duplicate names, leaving the new
// instance without an attached context.
final _msPlugin = Countdown(name: 'ms_demo', interval: 1000 ~/ 60);

class _MsBuilderDemo extends StatefulWidget {
  const _MsBuilderDemo();

  @override
  State<_MsBuilderDemo> createState() => _MsBuilderDemoState();
}

class _MsBuilderDemoState extends State<_MsBuilderDemo> {
  @override
  void initState() {
    super.initState();
    Countman.use(_msPlugin);
  }

  @override
  Widget build(BuildContext context) {
    return CountdownBuilder(
      duration: const Duration(seconds: 10),
      plugin: _msPlugin,
      builder: (_, parts, __) => Text(
        CountdownFormat.msMillis(parts),
        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _ControllerBuilderDemo extends StatefulWidget {
  const _ControllerBuilderDemo();

  @override
  State<_ControllerBuilderDemo> createState() => _ControllerBuilderDemoState();
}

class _ControllerBuilderDemoState extends State<_ControllerBuilderDemo> {
  final _ctrl = CountdownController();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CountdownBuilder(
          duration: const Duration(minutes: 2),
          controller: _ctrl,
          builder: (_, parts, __) {
            final m = parts.totalMinutes.toString().padLeft(2, '0');
            final s = parts.seconds.toString().padLeft(2, '0');
            return Text(
              '$m:$s',
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            );
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            ElevatedButton(
              onPressed: _ctrl.pause,
              child: const Text('Pause'),
            ),
            ElevatedButton(
              onPressed: _ctrl.resume,
              child: const Text('Resume'),
            ),
            ElevatedButton(
              onPressed: _ctrl.reset,
              child: const Text('Reset'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ThresholdDemo extends StatefulWidget {
  const _ThresholdDemo();

  @override
  State<_ThresholdDemo> createState() => _ThresholdDemoState();
}

class _ThresholdDemoState extends State<_ThresholdDemo> {
  bool _urgent = false;

  @override
  Widget build(BuildContext context) {
    return CountdownBuilder(
      duration: const Duration(seconds: 30),
      threshold: const Duration(seconds: 10),
      onThreshold: () { if (mounted) setState(() => _urgent = true); },
      builder: (_, parts, __) {
        final m = parts.totalMinutes.toString().padLeft(2, '0');
        final s = parts.seconds.toString().padLeft(2, '0');
        return Text(
          '$m:$s',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: _urgent ? Colors.red : null,
          ),
        );
      },
    );
  }
}

class _OnCompleteDemo extends StatefulWidget {
  const _OnCompleteDemo();

  @override
  State<_OnCompleteDemo> createState() => _OnCompleteDemoState();
}

class _OnCompleteDemoState extends State<_OnCompleteDemo> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        CountdownBuilder(
          duration: const Duration(seconds: 10),
          onComplete: () { if (mounted) setState(() => _done = true); },
          builder: (_, parts, __) {
            final s = parts.totalSeconds.toString().padLeft(2, '0');
            return Text(
              '00:$s',
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            );
          },
        ),
        if (_done)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Done!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }
}

class _ClockBox extends StatelessWidget {
  const _ClockBox({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value.toString().padLeft(2, '0'),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}

class _ThresholdTextDemo extends StatefulWidget {
  const _ThresholdTextDemo();

  @override
  State<_ThresholdTextDemo> createState() => _ThresholdTextDemoState();
}

class _ThresholdTextDemoState extends State<_ThresholdTextDemo> {
  bool _urgent = false;

  @override
  Widget build(BuildContext context) {
    return CountdownText(
      to: const Duration(seconds: 20),
      formatter: CountdownFormat.ms,
      threshold: const Duration(seconds: 5),
      onThreshold: () { if (mounted) setState(() => _urgent = true); },
      style: CountdownTextStyle(textStyle: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: _urgent ? Colors.red : null,
        letterSpacing: _urgent ? 2 : 0,
      )),
    );
  }
}

class _RingControllerDemo extends StatefulWidget {
  const _RingControllerDemo();

  @override
  State<_RingControllerDemo> createState() => _RingControllerDemoState();
}

class _RingControllerDemoState extends State<_RingControllerDemo> {
  final _ctrl = CountdownController();
  bool _paused = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CountdownRing(
          to: const Duration(minutes: 2),
          style: const CountdownRingStyle(size: 100),
          controller: _ctrl,
          center: const CountdownText(
            to: Duration(minutes: 2),
            formatter: CountdownFormat.ms,
            style: CountdownTextStyle(textStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: () {
                if (_paused) {
                  _ctrl.resume();
                } else {
                  _ctrl.pause();
                }
                setState(() => _paused = !_paused);
              },
              child: Text(_paused ? 'Resume' : 'Pause'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () {
                _ctrl.reset();
                setState(() => _paused = false);
              },
              child: const Text('Reset'),
            ),
          ],
        ),
      ],
    );
  }
}

class _GroupCallbacksDemo extends StatefulWidget {
  const _GroupCallbacksDemo();

  @override
  State<_GroupCallbacksDemo> createState() => _GroupCallbacksDemoState();
}

class _GroupCallbacksDemoState extends State<_GroupCallbacksDemo> {
  String _status = 'waiting';

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CountdownProvider(
          plugin: defaultCountdown,
          onGroupReady: () { WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) setState(() => _status = 'active'); }); },
          onAllComplete: () { WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) setState(() => _status = 'all done'); }); },
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CountdownText(
                to: Duration(seconds: 8),
                formatter: CountdownFormat.ms,
                style: CountdownTextStyle(textStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              SizedBox(height: 8),
              CountdownText(
                to: Duration(seconds: 12),
                formatter: CountdownFormat.ms,
                style: CountdownTextStyle(textStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.circle,
              size: 10,
              color: _status == 'active'
                  ? Colors.green
                  : _status == 'all done'
                      ? Colors.grey
                      : Colors.orange,
            ),
            const SizedBox(width: 6),
            Text(
              'Group: $_status',
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      ],
    );
  }
}

// ── CountdownDial section ─────────────────────────────────────────────────────

Widget _dialSection() => DemoSection(
      title: 'CountdownDial',
      children: [
        DemoCard(
          title: 'Basic',
          description: '60-second dial, clockwise',
          code: runnable(r'''
class _Demo extends StatelessWidget {
  const _Demo();
  @override
  Widget build(BuildContext context) => CountdownDial(
    to: const Duration(seconds: 60),
    size: 100,
  );
}'''),
          child: const CountdownDial(
            to: Duration(seconds: 60),
            style: CountdownDialStyle(size: 100),
          ),
        ),

        DemoCard(
          title: 'With center text',
          description: 'Builder shows remaining seconds in center',
          code: runnable(r'''
class _Demo extends StatelessWidget {
  const _Demo();
  @override
  Widget build(BuildContext context) => CountdownDial(
    to: const Duration(minutes: 3),
    size: 100,
    builder: (_, rem) => Text(
      rem.inSeconds.toString(),
      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
    ),
  );
}'''),
          child: CountdownDial(
            to: const Duration(minutes: 3),
            style: const CountdownDialStyle(size: 100),
            builder: (_, rem) => Text(
              rem.inSeconds.toString(),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
        ),

        DemoCard(
          title: 'Counter-clockwise',
          description: 'clockwise: false',
          code: runnable(r'''
class _Demo extends StatelessWidget {
  const _Demo();
  @override
  Widget build(BuildContext context) => CountdownDial(
    to: const Duration(seconds: 60),
    size: 100,
    clockwise: false,
  );
}'''),
          child: const CountdownDial(
            to: Duration(seconds: 60),
            style: CountdownDialStyle(
              size: 100,
              clockwise: false,
            ),
          ),
        ),

        DemoCard(
          title: 'No ticks',
          description: 'ticks: null hides the outer tick ring',
          code: runnable(r'''
class _Demo extends StatelessWidget {
  const _Demo();
  @override
  Widget build(BuildContext context) => CountdownDial(
    to: const Duration(seconds: 45),
    size: 100,
    ticks: null,
  );
}'''),
          child: const CountdownDial(
            to: Duration(seconds: 45),
            style: CountdownDialStyle(
              size: 100,
              showTicks: false,
            ),
          ),
        ),
      ],
    );
