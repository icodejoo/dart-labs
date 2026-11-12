// ignore_for_file: invalid_use_of_internal_member

import 'package:countman/countman.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/manual_clock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ManualCountmanClock clock;
  setUp(() => clock = installManualClock());
  tearDown(Countman.destroy);

  testWidgets('全部静音且仅剩 1ms 时也休眠，不进入 20ms 连续排帧窗口', (t) async {
    var completes = 0;
    await t.pumpWidget(TickerMode(
      enabled: false,
      child: CounterBuilder(
        to: 1,
        duration: const Duration(milliseconds: 1),
        onComplete: (_) => completes++,
        builder: (_, __, ___) => const SizedBox(),
      ),
    ));
    await t.pump();
    expect(Countman.isSleeping, isTrue);
    expect(t.binding.transientCallbackCount, 0);
    clock.advance(const Duration(milliseconds: 1));
    await t.pump(const Duration(milliseconds: 1));
    expect(completes, 1);
    expect(Countman.isRunning, isFalse);
  });

  test('Clock 静音不 reanchor，恢复 dt=0 强刷同桶，onStart 仅一次', () {
    var requested = 0;
    final plugin = Countdown(name: 'clock', interval: 10000)
      ..onAttach(CountmanContext(requestFrame: () => requested++));
    var starts = 0;
    final values = <int>[];
    final handle = plugin.addMuted(
      CountdownOptions(
        duration: const Duration(seconds: 9),
        onStart: () => starts++,
        onUpdate: (p) => values.add(p.inMilliseconds),
      ),
      muted: true,
    );
    final task = plugin.task(0)!;
    final anchor = task.endMicros;
    expect(plugin.tick(Duration.zero, Duration.zero), 9000000);
    expect(starts, 1);
    expect(values, isEmpty);
    clock.advance(const Duration(milliseconds: 500));
    final revision = task.revision;
    final before = requested;
    handle.muted = false;
    expect(task.revision, revision + 1);
    expect(requested, before + 1);
    expect(task.endMicros, anchor);
    expect(task.lastBucket, -1);
    plugin.tick(Duration.zero, Duration.zero);
    expect(values, [8500]);
    handle.muted = true;
    expect(task.revision, revision + 2);
    expect(requested, before + 2);
    expect(plugin.tick(Duration.zero, Duration.zero), 8500000);
    expect(starts, 1);
    expect(values, [8500]);
  });

  test('静音无期限任务返回 idle，不得盖掉同组可见任务的下一帧', () {
    final plugin = Elapsed(name: 'mixed', interval: 0)
      ..onAttach(CountmanContext(requestFrame: () {}));
    plugin.add(ElapsedOptions());
    plugin.addMuted(ElapsedOptions(), muted: true);
    expect(plugin.tick(Duration.zero, Duration.zero), CountmanPlugin.nextFrame);
    expect(plugin.tick(Duration.zero, Duration.zero), CountmanPlugin.nextFrame);
  });

  test('onUpdate 内静音令旧版本的完成失效，下一帧静音完成一次', () {
    final plugin = Counter(name: 'revision')
      ..onAttach(CountmanContext(requestFrame: () {}));
    var completes = 0;
    var updates = 0;
    late CounterHandle handle;
    handle = plugin.add(
      CounterOptions(
        to: 1,
        duration: const Duration(milliseconds: 100),
        onUpdate: (v) {
          updates++;
          if (v == 1) handle.muted = true;
        },
        onComplete: (_) => completes++,
      ),
    );
    plugin.tick(Duration.zero, Duration.zero);
    expect(plugin.tick(Duration.zero, const Duration(milliseconds: 100)), 0);
    expect(completes, 0);
    plugin.tick(Duration.zero, Duration.zero);
    expect(updates, 2);
    expect(completes, 1);
    expect(plugin.activeTaskCount, 0);
  });

  test('静音任务完成抛错仍清理，不影响同组任务与 tick 内延迟入队', () {
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);
    final plugin = Countdown(name: 'errors', interval: 0)
      ..onAttach(CountmanContext(requestFrame: () {}));
    var completes = 0;
    var updates = 0;
    plugin.addMuted(
      CountdownOptions(
        duration: const Duration(seconds: 1),
        onComplete: () => throw StateError('hidden complete'),
      ),
      muted: true,
    );
    plugin.addMuted(
      CountdownOptions(
        duration: const Duration(seconds: 1),
        onComplete: () {
          completes++;
          plugin.addMuted(
            CountdownOptions(
              duration: const Duration(seconds: 1),
              onUpdate: (_) => updates++,
              onComplete: () => completes++,
            ),
            muted: true,
          );
        },
      ),
      muted: true,
    );
    plugin.tick(Duration.zero, Duration.zero);
    clock.advance(const Duration(seconds: 1));
    plugin.tick(Duration.zero, Duration.zero);
    expect(errors.single.exception, isStateError);
    expect(completes, 1);
    expect(plugin.activeTaskCount, 1);
    expect(plugin.task(2)!.muted, isTrue);
    plugin.tick(Duration.zero, Duration.zero);
    clock.advance(const Duration(seconds: 1));
    plugin.tick(Duration.zero, Duration.zero);
    expect(completes, 2);
    expect(updates, 0);
    expect(plugin.activeTaskCount, 0);
    expect(plugin.debugSnapshotTaskCount, 0);
  });

  test('Counter 取消静音早于首次 tick，保持 update/start/complete 顺序', () {
    final plugin = Counter(name: 'early')
      ..onAttach(CountmanContext(requestFrame: () {}));
    final events = <String>[];
    final handle = plugin.addMuted(
      CounterOptions(
        to: 10,
        onUpdate: (v) => events.add('update:$v'),
        onStart: () => events.add('start'),
        onComplete: (_) => events.add('complete'),
      ),
      muted: true,
    );
    clock.advance(const Duration(seconds: 2));
    handle.muted = false;
    plugin.tick(Duration.zero, Duration.zero);
    expect(events, ['update:10.0', 'start', 'complete']);
    plugin.tick(Duration.zero, Duration.zero);
    expect(events.length, 3);
  });
}
