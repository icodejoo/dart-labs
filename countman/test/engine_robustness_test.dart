import 'package:countman/src/core/ticker.dart';
import 'package:countman/src/core/types.dart';
import 'package:countman/src/core/start_scheduler.dart';
import 'package:countman/src/counter/plugin.dart';
import 'package:countman/src/counter/types.dart';
import 'package:countman/src/count_down/plugin.dart';
import 'package:countman/src/count_down/types.dart';
import 'package:countman/src/elapsed/plugin.dart';
import 'package:countman/src/elapsed/types.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证异常隔离、逐帧完成和启动取消契约。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const frame = Duration(milliseconds: 16);
  final errors = <FlutterErrorDetails>[];
  late FlutterExceptionHandler? previous;
  setUp(() {
    previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    errors.clear();
  });
  tearDown(() {
    Countman.destroy();
    StartScheduler.instance.clear();
    StartScheduler.instance.defaultBatchSize = 0;
    FlutterError.onError = previous;
  });
  test('更新异常不饿死兄弟，完成异常仍排空', () {
    final p = Counter(name: 'isolation');
    p.onAttach(CountmanContext(requestFrame: () {}));
    var completed = false;
    p.add(CounterOptions(
        to: 1, duration: frame, onUpdate: (_) => throw StateError('update')));
    p.add(CounterOptions(
        to: 1,
        duration: frame,
        onComplete: (_) {
          completed = true;
          throw StateError('complete');
        }));
    for (var i = 0; i < 4; i++) {
      p.tick(frame * i, frame);
    }
    expect(completed, isTrue);
    expect(errors, isNotEmpty);
    p.dispose();
    final q = Counter(name: 'drained');
    q.onAttach(CountmanContext(requestFrame: () {}));
    var drained = false;
    q.onQueueDrained = () => drained = true;
    q.add(CounterOptions(
        to: 1,
        duration: frame,
        onComplete: (_) => throw StateError('complete')));
    q.tick(Duration.zero, Duration.zero);
    q.tick(frame, frame);
    expect(q.activeTaskCount, 0);
    expect(drained, isTrue);
  });
  test('destroy 隔离同组及跨插件取消异常', () {
    var cancelled = 0;
    final p = Counter(name: 'first');
    p.add(CounterOptions(to: 1, onCancel: () => throw StateError('cancel')));
    p.add(CounterOptions(to: 1, onCancel: () => cancelled++));
    Counter(name: 'second')
        .add(CounterOptions(to: 1, onCancel: () => cancelled++));
    Countman.destroy();
    expect(cancelled, 2);
    expect(errors.single.library, 'countman');
  });
  testWidgets('批启动异常和批内取消不丢后续启动', (tester) async {
    final handler = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = handler);
    final s = StartScheduler.instance;
    s.defaultBatchSize = 3;
    final cancelled = Object();
    final calls = <int>[];
    s.enqueue(() {
      s.cancel(cancelled);
      throw StateError('start');
    }, tag: Object());
    s.enqueue(() => calls.add(2), tag: cancelled);
    s.enqueue(() => calls.add(3), tag: Object());
    s.enqueue(() => calls.add(4), tag: Object());
    await tester.pump();
    await tester.pump(frame);
    expect(calls, [3, 4]);
    expect(errors.single.library, 'countman');
  });
  test('完成和阈值逐帧检查，每帧每组只读取一次时钟', () {
    final old = countdownClock;
    var now = DateTime(2026);
    var reads = 0;
    countdownClock = () {
      reads++;
      return now;
    };
    addTearDown(() => countdownClock = old);
    final p = Countdown();
    p.onAttach(CountmanContext(requestFrame: () {}));
    final updates = <int>[];
    var complete = false;
    var threshold = false;
    p.add(CountdownOptions(
        duration: const Duration(milliseconds: 1500),
        threshold: const Duration(milliseconds: 250),
        onThreshold: () => threshold = true,
        onUpdate: (t) => updates.add(t.inMilliseconds),
        onComplete: () => complete = true));
    p.add(const CountdownOptions(duration: Duration(seconds: 3)));
    p.tick(Duration.zero, Duration.zero);
    for (var ms = 16; ms <= 1504; ms += 16) {
      now = DateTime(2026).add(Duration(milliseconds: ms));
      reads = 0;
      p.tick(Duration(milliseconds: ms), frame);
      expect(reads, 1);
      if (ms == 1264) expect(threshold, isTrue);
    }
    expect(complete, isTrue);
    expect(updates.last, 0);
  });
  test('零时长首帧完成，取消后同帧不能暂停或复活', () {
    final p = Countdown();
    p.onAttach(CountmanContext(requestFrame: () {}));
    var complete = false;
    p.add(CountdownOptions(
        duration: Duration.zero, onComplete: () => complete = true));
    p.tick(Duration.zero, Duration.zero);
    expect(complete, isTrue);
    final e = Elapsed();
    e.onAttach(CountmanContext(requestFrame: () {}));
    late ElapsedHandle handle;
    var pauses = 0;
    handle = e.add(ElapsedOptions(
        onPause: () => pauses++,
        onUpdate: (_) {
          handle.cancel();
          handle.pause();
          handle.resume();
          handle.reset();
        }));
    e.tick(Duration.zero, Duration.zero);
    expect(pauses, 0);
  });
}
