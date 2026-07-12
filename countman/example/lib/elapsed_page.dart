import 'package:flutter/material.dart';
import 'package:countman/countman.dart';
import 'demo_card.dart';

class ElapsedPage extends StatefulWidget {
  const ElapsedPage({super.key});
  @override
  State<ElapsedPage> createState() => _ElapsedPageState();
}

class _ElapsedPageState extends State<ElapsedPage> {
  int _resetKey = 0;

  @override
  Widget build(BuildContext context) {
    // canPop:false intercepts back before Flutter starts deactivating the tree.
    // Sequence:
    //   1. Countman.destroy() — marks all Elapsed plugin tasks as cancelled.
    //   2. addPostFrameCallback — waits for the current frame to flush so any
    //      already-queued frame callbacks run as no-ops (plugin is cancelled).
    //   3. Navigator.pop() — starts the route transition after the frame is clean.
    // This prevents the `_dependents.isEmpty` assertion: no frame callback can
    // trigger a rebuild that re-adds an element to CountmanScope._dependents
    // between destroy() and the InheritedElement.unmount() check.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          Countman.destroy();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) Navigator.of(context).pop();
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Elapsed'),
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
          // ── TextElapsed ──────────────────────────────────────────────────
          DemoSection(title: 'TextElapsed', children: [
            DemoCard(
              title: 'Basic stopwatch',
              description: 'Counts up from 0 when mounted.',
              code: runnable('''
class _Demo extends StatelessWidget {
  const _Demo();
  @override
  Widget build(BuildContext context) {
    return TextElapsed(
      style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
    );
  }
}
'''),
              child: const TextElapsed(
                style: TextElapsedStyle(textStyle: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              ),
            ),

            DemoCard(
              title: 'Auto format',
              description:
                  'CountdownFormat.auto: shows tenths below 10 s, mm:ss up to 1 h, then HH:mm:ss.',
              code: runnable('''
class _Demo extends StatelessWidget {
  const _Demo();
  @override
  Widget build(BuildContext context) {
    return TextElapsed(
      formatter: CountdownFormat.auto,
      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
    );
  }
}
'''),
              child: const TextElapsed(
                formatter: CountdownFormat.auto,
                style: TextElapsedStyle(textStyle: TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
              ),
            ),

            DemoCard(
              title: 'MM:SS format',
              description: 'CountdownFormat.ms — minutes may exceed 59.',
              code: runnable('''
class _Demo extends StatelessWidget {
  const _Demo();
  @override
  Widget build(BuildContext context) {
    return TextElapsed(
      formatter: CountdownFormat.ms,
      style: TextStyle(fontSize: 28, fontFeatures: [FontFeature.tabularFigures()]),
    );
  }
}
'''),
              child: const TextElapsed(
                formatter: CountdownFormat.ms,
                style: TextElapsedStyle(textStyle: TextStyle(fontSize: 28)),
              ),
            ),

            DemoCard(
              title: 'Tenths format',
              description:
                  'CountdownFormat.msTenths — sub-second precision. Use Elapsed(interval: 100).',
              code: runnable('''
// Use a 100 ms interval so the tenths digit updates smoothly.
final _plugin = Elapsed(name: 'tenths', interval: 100);

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
    return TextElapsed(
      plugin: _plugin,
      formatter: CountdownFormat.msTenths,
      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
    );
  }
}
'''),
              child: _TenthsDemo(),
            ),

            DemoCard(
              title: 'Custom formatter',
              description: 'Formatter showing "Xh Ym Zs" from TimeParts fields.',
              code: runnable('''
class _Demo extends StatelessWidget {
  const _Demo();

  static String _fmt(TimeParts t) {
    if (t.totalHours >= 1) {
      return '\${t.totalHours}h \${t.minutes}m \${t.seconds}s';
    }
    if (t.totalMinutes >= 1) return '\${t.totalMinutes}m \${t.seconds}s';
    return '\${t.seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    return TextElapsed(
      formatter: _fmt,
      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500),
    );
  }
}
'''),
              child: const _CustomFormatterDemo(),
            ),

            DemoCard(
              title: 'Pause / Resume',
              description:
                  'ElapsedController.pause() and .resume() freeze and unfreeze the counter.',
              code: runnable('''
class _Demo extends StatefulWidget {
  const _Demo();
  @override
  State<_Demo> createState() => _DemoState();
}
class _DemoState extends State<_Demo> {
  final _ctrl = ElapsedController();

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      TextElapsed(
        controller: _ctrl,
        style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 12),
      Row(mainAxisSize: MainAxisSize.min, children: [
        FilledButton.tonal(
          onPressed: _ctrl.pause,
          child: const Text('Pause'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _ctrl.resume,
          child: const Text('Resume'),
        ),
      ]),
    ]);
  }
}
'''),
              child: const _PauseResumeDemo(),
            ),

            DemoCard(
              title: 'Threshold callback',
              description:
                  'onThreshold fires once at 10 s; the text turns amber.',
              code: runnable('''
class _Demo extends StatefulWidget {
  const _Demo();
  @override
  State<_Demo> createState() => _DemoState();
}
class _DemoState extends State<_Demo> {
  Color _color = Colors.black87;

  @override
  Widget build(BuildContext context) {
    return TextElapsed(
      threshold: const Duration(seconds: 10),
      onThreshold: () => setState(() => _color = Colors.amber),
      style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: _color),
    );
  }
}
'''),
              child: const _ThresholdDemo(),
            ),

            DemoCard(
              title: 'Reset on tap',
              description:
                  'Tap to create a fresh ElapsedController, restarting elapsed from zero.',
              code: runnable('''
class _Demo extends StatefulWidget {
  const _Demo();
  @override
  State<_Demo> createState() => _DemoState();
}
class _DemoState extends State<_Demo> {
  ElapsedController _ctrl = ElapsedController();

  void _reset() => setState(() => _ctrl = ElapsedController());

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _reset,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextElapsed(
          controller: _ctrl,
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text('tap to reset',
            style: TextStyle(fontSize: 11, color: Colors.grey)),
      ]),
    );
  }
}
'''),
              child: const _ResetOnTapDemo(),
            ),

            DemoCard(
              title: 'Precise sub-second',
              description:
                  'precise: true drives on the shared frame-rate group; '
                  'CountdownFormat.msMillis shows milliseconds — no manual Elapsed(interval:) needed.',
              code: runnable('''
class _Demo extends StatelessWidget {
  const _Demo();
  @override
  Widget build(BuildContext context) {
    return TextElapsed(
      precise: true,
      formatter: CountdownFormat.msMillis,
      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
    );
  }
}
'''),
              child: const TextElapsed(
                precise: true,
                formatter: CountdownFormat.msMillis,
                style: TextElapsedStyle(textStyle: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              ),
            ),

            DemoCard(
              title: 'onTick side effect',
              description:
                  'onTick updates an external label via setState — a side effect that '
                  'does not rebuild the TextElapsed itself.',
              code: runnable('''
class _Demo extends StatefulWidget {
  const _Demo();
  @override
  State<_Demo> createState() => _DemoState();
}
class _DemoState extends State<_Demo> {
  int _ticks = 0;

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      TextElapsed(
        onTick: (parts) => setState(() => _ticks++),
        style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 6),
      Text('ticks: \$_ticks', style: const TextStyle(fontSize: 13)),
    ]);
  }
}
'''),
              child: const _OnTickDemo(),
            ),
          ]),

          // ── ElapsedProvider ──────────────────────────────────────────────
          DemoSection(title: 'ElapsedProvider', children: [
            DemoCard(
              title: 'Cascaded style',
              description:
                  'ElapsedProvider.textStyle flows down to all child TextElapsed widgets.',
              code: runnable('''
class _Demo extends StatelessWidget {
  const _Demo();
  @override
  Widget build(BuildContext context) {
    return ElapsedProvider(
      textStyle: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: Colors.deepPurple,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('A', style: TextStyle(fontSize: 11, color: Colors.grey)),
          TextElapsed(),
        ]),
        const SizedBox(width: 20),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('B', style: TextStyle(fontSize: 11, color: Colors.grey)),
          TextElapsed(),
        ]),
        const SizedBox(width: 20),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('C', style: TextStyle(fontSize: 11, color: Colors.grey)),
          TextElapsed(),
        ]),
      ]),
    );
  }
}
'''),
              child: ElapsedProvider(
                textStyle: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.deepPurple,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _LabeledElapsed('A'),
                    const SizedBox(width: 20),
                    _LabeledElapsed('B'),
                    const SizedBox(width: 20),
                    _LabeledElapsed('C'),
                  ],
                ),
              ),
            ),

            DemoCard(
              title: 'Group callbacks',
              description:
                  'onGroupReady fires when the first task starts; onAllComplete when all tasks cancel.',
              code: runnable('''
class _Demo extends StatefulWidget {
  const _Demo();
  @override
  State<_Demo> createState() => _DemoState();
}
class _DemoState extends State<_Demo> {
  String _status = 'idle';

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      ElapsedProvider(
        plugin: defaultElapsed, // explicit plugin avoids same-name conflict in Countman.use
        onGroupReady: () { WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) setState(() => _status = 'running'); }); },
        onAllComplete: () { WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) setState(() => _status = 'idle'); }); },
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _LabeledElapsed('timer 1'),
          const SizedBox(width: 20),
          _LabeledElapsed('timer 2'),
        ]),
      ),
      const SizedBox(height: 10),
      Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.circle, size: 8, color: Colors.green),
        const SizedBox(width: 4),
        Text('group: \$_status',
            style: const TextStyle(fontSize: 13)),
      ]),
    ]);
  }
}

class _LabeledElapsed extends StatelessWidget {
  const _LabeledElapsed(this.label);
  final String label;
  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      const TextElapsed(
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
    ]);
  }
}
'''),
              child: const _GroupCallbacksDemo(),
            ),
          ]),
        ],
          ),      // ListView
        ),        // KeyedSubtree
        ),        // PageSectionCounter
      ),          // Scaffold
    );            // PopScope
  }
}

// ── _TenthsDemo ───────────────────────────────────────────────────────────────

class _TenthsDemo extends StatefulWidget {
  const _TenthsDemo();
  @override
  State<_TenthsDemo> createState() => _TenthsDemoState();
}

class _TenthsDemoState extends State<_TenthsDemo> {
  late final Elapsed _plugin;

  @override
  void initState() {
    super.initState();
    _plugin = Elapsed(name: 'demo-elapsed-tenths', interval: 100);
    Countman.use(_plugin);
  }

  @override
  void dispose() {
    _plugin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextElapsed(
      plugin: _plugin,
      formatter: CountdownFormat.msTenths,
      style: TextElapsedStyle(textStyle: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
    );
  }
}

// ── _CustomFormatterDemo ──────────────────────────────────────────────────────

class _CustomFormatterDemo extends StatelessWidget {
  const _CustomFormatterDemo();

  static String _fmt(TimeParts t) {
    if (t.totalHours >= 1) {
      return '${t.totalHours}h ${t.minutes}m ${t.seconds}s';
    }
    if (t.totalMinutes >= 1) return '${t.totalMinutes}m ${t.seconds}s';
    return '${t.seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    return const TextElapsed(
      formatter: _fmt,
      style: TextElapsedStyle(textStyle: TextStyle(fontSize: 24, fontWeight: FontWeight.w500)),
    );
  }
}

// ── _PauseResumeDemo ──────────────────────────────────────────────────────────

class _PauseResumeDemo extends StatefulWidget {
  const _PauseResumeDemo();
  @override
  State<_PauseResumeDemo> createState() => _PauseResumeDemoState();
}

class _PauseResumeDemoState extends State<_PauseResumeDemo> {
  final _ctrl = ElapsedController();
  bool _paused = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextElapsed(
          controller: _ctrl,
          style: TextElapsedStyle(textStyle: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.tonal(
              onPressed: _paused
                  ? null
                  : () {
                      _ctrl.pause();
                      setState(() => _paused = true);
                    },
              child: const Text('Pause'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: !_paused
                  ? null
                  : () {
                      _ctrl.resume();
                      setState(() => _paused = false);
                    },
              child: const Text('Resume'),
            ),
          ],
        ),
      ],
    );
  }
}

// ── _ThresholdDemo ────────────────────────────────────────────────────────────

class _ThresholdDemo extends StatefulWidget {
  const _ThresholdDemo();
  @override
  State<_ThresholdDemo> createState() => _ThresholdDemoState();
}

class _ThresholdDemoState extends State<_ThresholdDemo> {
  Color _color = Colors.black87;

  @override
  Widget build(BuildContext context) {
    return TextElapsed(
      threshold: const Duration(seconds: 10),
      onThreshold: () => setState(() => _color = Colors.amber),
      style: TextElapsedStyle(textStyle: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: _color)),
    );
  }
}

// ── _ResetOnTapDemo ───────────────────────────────────────────────────────────

class _ResetOnTapDemo extends StatefulWidget {
  const _ResetOnTapDemo();
  @override
  State<_ResetOnTapDemo> createState() => _ResetOnTapDemoState();
}

class _ResetOnTapDemoState extends State<_ResetOnTapDemo> {
  ElapsedController _ctrl = ElapsedController();

  void _reset() => setState(() => _ctrl = ElapsedController());

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _reset,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextElapsed(
            controller: _ctrl,
            style: TextElapsedStyle(textStyle: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 6),
          const Text(
            'tap to reset',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

// ── _OnTickDemo ───────────────────────────────────────────────────────────────

class _OnTickDemo extends StatefulWidget {
  const _OnTickDemo();
  @override
  State<_OnTickDemo> createState() => _OnTickDemoState();
}

class _OnTickDemoState extends State<_OnTickDemo> {
  // Tick counter kept outside the TextElapsed — mutated by onTick, shown below.
  //
  // 保存在 TextElapsed 之外的 tick 计数——由 onTick 修改并在下方显示。
  int _ticks = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextElapsed(
          onTick: (parts) => setState(() => _ticks++),
          style: TextElapsedStyle(textStyle: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 6),
        Text('ticks: $_ticks', style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}

// ── _LabeledElapsed ───────────────────────────────────────────────────────────

class _LabeledElapsed extends StatelessWidget {
  const _LabeledElapsed(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const TextElapsed(
          style: TextElapsedStyle(textStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

// ── _GroupCallbacksDemo ───────────────────────────────────────────────────────

class _GroupCallbacksDemo extends StatefulWidget {
  const _GroupCallbacksDemo();
  @override
  State<_GroupCallbacksDemo> createState() => _GroupCallbacksDemoState();
}

class _GroupCallbacksDemoState extends State<_GroupCallbacksDemo> {
  String _status = 'waiting…';

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElapsedProvider(
          plugin: defaultElapsed,
          onGroupReady: () { WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) setState(() => _status = 'group active'); }); },
          onAllComplete: () { WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) setState(() => _status = 'group idle'); }); },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              _LabeledElapsed('timer 1'),
              SizedBox(width: 20),
              _LabeledElapsed('timer 2'),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.circle, size: 8, color: Colors.green),
            const SizedBox(width: 4),
            Text(_status, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ],
    );
  }
}
