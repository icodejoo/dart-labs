import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:countman/countman.dart';

void main() {
  // Safety net for plain test() — no pending frame callbacks there.
  tearDown(Countman.destroy);

  // ── use() ──────────────────────────────────────────────────────────

  group('use()', () {
    test('registers a plugin', () {
      Countman.use(_FakePlugin('a'));
      expect(Countman.pluginCount, 1);
    });

    test('deduplicates by name', () {
      Countman.use(_FakePlugin('a'));
      Countman.use(_FakePlugin('a'));
      expect(Countman.pluginCount, 1);
    });

    test('allows different names', () {
      Countman.use(_FakePlugin('a'));
      Countman.use(_FakePlugin('b'));
      expect(Countman.pluginCount, 2);
    });
  });

  // ── onAttach ───────────────────────────────────────────────────────

  test('use() calls onAttach with a context', () {
    final p = _FakePlugin('a');
    Countman.use(p);
    expect(p.attachedCtx, isNotNull);
  });

  test('ctx.requestFrame starts the ticker', () {
    final p = _FakePlugin('a');
    Countman.use(p);
    expect(Countman.isRunning, isFalse);
    p.attachedCtx!.requestFrame();
    expect(Countman.isRunning, isTrue);
    Countman.destroy();
  });

  // ── start / stop ───────────────────────────────────────────────────
  // testWidgets' animation-leak check runs before addTearDown, so we must
  // explicitly stop the ticker inside the test body before it exits.

  testWidgets('start() sets isRunning', (tester) async {
    Countman.use(_FakePlugin('a'));
    Countman.start();
    expect(Countman.isRunning, isTrue);
    Countman.destroy(); // must come before test body exits
  });

  testWidgets('stop() clears isRunning', (tester) async {
    Countman.use(_FakePlugin('a'));
    Countman.start();
    Countman.stop();
    expect(Countman.isRunning, isFalse);
  });

  testWidgets('start() is idempotent — tick fires exactly once', (tester) async {
    final p = _FakePlugin('a');
    Countman.use(p);
    Countman.start();
    Countman.start();
    await tester.pump();
    expect(p.tickCount, 1);
    Countman.destroy();
  });

  // ── tick ───────────────────────────────────────────────────────────

  testWidgets('tick() is called once per pump', (tester) async {
    final p = _FakePlugin('a');
    Countman.use(p);
    Countman.start();

    await tester.pump();
    expect(p.tickCount, 1);

    await tester.pump();
    expect(p.tickCount, 2);

    Countman.destroy();
  });

  testWidgets('dt is zero on the first frame', (tester) async {
    Duration? capturedDt;
    final p = _FakePlugin('a', onTick: (_, dt) => capturedDt = dt);
    Countman.use(p);
    Countman.start();

    await tester.pump(const Duration(milliseconds: 16));
    Countman.destroy();

    expect(capturedDt, Duration.zero);
  });

  testWidgets('dt is non-zero after the first frame', (tester) async {
    final dts = <Duration>[];
    final p = _FakePlugin('a', onTick: (_, dt) => dts.add(dt));
    Countman.use(p);
    Countman.start();

    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    Countman.destroy();

    expect(dts.length, 2);
    expect(dts[0], Duration.zero);
    expect(dts[1].inMilliseconds, greaterThan(0));
  });

  // ── auto-stop ──────────────────────────────────────────────────────

  testWidgets('auto-stops when all plugins return false', (tester) async {
    final p = _FakePlugin('a', busy: false);
    Countman.use(p);
    Countman.start();

    await tester.pump(); // fires once → false → stops
    final countAfter = p.tickCount;

    await tester.pump(); // must NOT fire again (already stopped)
    expect(p.tickCount, countAfter);
    expect(Countman.isRunning, isFalse);
    // no explicit destroy needed — ticker already idle
  });

  testWidgets('continues while at least one plugin is busy', (tester) async {
    Countman.use(_FakePlugin('idle', busy: false));
    Countman.use(_FakePlugin('busy'));
    Countman.start();

    await tester.pump();
    await tester.pump();
    expect(Countman.isRunning, isTrue);
    Countman.destroy();
  });

  // ── error isolation ────────────────────────────────────────────────

  testWidgets('error in one plugin does not stop others', (tester) async {
    final good = _FakePlugin('good');
    Countman.use(_ThrowingPlugin('bad'));
    Countman.use(good);
    Countman.start();

    final errors = <FlutterErrorDetails>[];
    final prev = FlutterError.onError;
    FlutterError.onError = errors.add;

    await tester.pump();

    FlutterError.onError = prev;
    Countman.destroy();

    expect(good.tickCount, 1);
    expect(errors, hasLength(1));
  });

  // ── destroy ────────────────────────────────────────────────────────

  testWidgets('destroy() disposes all plugins and stops loop', (tester) async {
    final p = _FakePlugin('a');
    Countman.use(p);
    Countman.start();
    await tester.pump();

    Countman.destroy();

    expect(p.disposed, isTrue);
    expect(Countman.isRunning, isFalse);
    expect(Countman.pluginCount, 0);
  });

  testWidgets('destroy() stops future ticks', (tester) async {
    final p = _FakePlugin('a');
    Countman.use(p);
    Countman.start();
    await tester.pump();

    Countman.destroy();
    final countAfterDestroy = p.tickCount;

    await tester.pump();
    expect(p.tickCount, countAfterDestroy);
  });
}

// ── helpers ───────────────────────────────────────────────────────────

class _FakePlugin implements CountmanPlugin {
  _FakePlugin(this.name, {this.busy = true, void Function(Duration, Duration)? onTick})
      : _onTick = onTick;

  @override
  final String name;
  final bool busy;
  final void Function(Duration, Duration)? _onTick;

  int tickCount = 0;
  bool disposed = false;
  CountmanContext? attachedCtx;

  @override
  void onAttach(CountmanContext ctx) => attachedCtx = ctx;

  @override
  bool tick(Duration elapsed, Duration dt) {
    tickCount++;
    _onTick?.call(elapsed, dt);
    return busy;
  }

  @override
  void dispose() => disposed = true;
}

class _ThrowingPlugin implements CountmanPlugin {
  _ThrowingPlugin(this.name);

  @override
  final String name;

  @override
  void onAttach(CountmanContext ctx) {}

  @override
  bool tick(Duration elapsed, Duration dt) => throw Exception('plugin error');

  @override
  void dispose() {}
}
