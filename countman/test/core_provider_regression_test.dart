import 'package:countman/countman.dart';
import 'package:flutter_test/flutter_test.dart';

// 本批回归覆盖回调重入、帧唤醒与任务终态，直接驱动可控帧。
Counter localCounter() =>
    Counter()..onAttach(CountmanContext(requestFrame: () {}));
void frame(Counter p, [int ms = 100]) =>
    p.tick(Duration(milliseconds: ms), Duration(milliseconds: ms));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Countman.destroy);

  for (final target in ['earlier', 'new', 'drained']) {
    regressionWidgetTest('#1 wake task added to $target plugin',
        (tester) async {
      final a = Counter(name: 'a');
      Countman.use(a);
      final b = Counter(name: 'b');
      var updates = 0;
      void add() => (target == 'new' ? Counter(name: 'new') : a)
          .add(CounterOptions(to: 1, onUpdate: (_) => updates++));
      if (target == 'drained') b.onQueueDrained = add;
      b.add(CounterOptions(
          to: 1,
          duration: Duration.zero,
          onComplete: target == 'drained' ? null : (_) => add()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 10));
      expect(updates, greaterThan(0));
    });
  }

  regressionWidgetTest('#2 destroy during tick stops the old traversal',
      (tester) async {
    final a = Counter(name: 'a');
    a.add(CounterOptions(to: 1, onUpdate: (_) => Countman.destroy()));
    final b = Counter(name: 'b');
    var updates = 0;
    b.add(CounterOptions(to: 1, onUpdate: (_) => updates++));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(updates, 0);
  });

  test('#3 cancel callback may cancel itself exactly once', () {
    final p = localCounter();
    late CounterHandle h;
    var calls = 0;
    h = p.add(CounterOptions(
        to: 1,
        onCancel: () {
          calls++;
          if (calls < 3) h.cancel();
        }));
    h.cancel();
    expect(calls, 1);
    expect(p.activeTaskCount, 0);
  });

  test('#3 dispose detaches tasks before notifying cancellation', () {
    final p = localCounter();
    late CounterHandle b;
    var calls = 0;
    p.add(CounterOptions(to: 1, onCancel: () => b.cancel()));
    b = p.add(CounterOptions(to: 2, onCancel: () => calls++));
    expect(p.dispose, returnsNormally);
    expect(calls, 1);
  });

  for (final action in ['cancel', 'pause', 'retarget']) {
    test('#4 final counter update may $action', () {
      final p = localCounter();
      late CounterHandle h;
      var complete = 0;
      h = p.add(CounterOptions(
          to: 1,
          duration: Duration.zero,
          onUpdate: (v) {
            if (v != 1) return;
            switch (action) {
              case 'cancel':
                h.cancel();
              case 'pause':
                h.pause();
              case 'retarget':
                h.update(to: 2);
            }
          },
          onComplete: (_) => complete++));
      frame(p, 0);
      frame(p);
      expect(complete, 0);
      expect(h.isDone, action == 'cancel');
    });
  }

  test('#4 initial update cancellation suppresses start', () {
    final p = localCounter();
    late CounterHandle h;
    var starts = 0;
    h = p.add(CounterOptions(
        to: 1, onUpdate: (_) => h.cancel(), onStart: () => starts++));
    frame(p);
    expect(starts, 0);
  });

  for (final action in ['cancel', 'pause', 'reset']) {
    test('#4 threshold may $action before countdown completion', () {
      var now = DateTime(2024);
      countdownClock = () => now;
      addTearDown(() => countdownClock = DateTime.now);
      final p = Countdown(interval: 0)
        ..onAttach(CountmanContext(requestFrame: () {}));
      late CountdownHandle h;
      var updates = 0;
      var completes = 0;
      h = p.add(CountdownOptions(
          duration: const Duration(seconds: 1),
          threshold: Duration.zero,
          onThreshold: () {
            switch (action) {
              case 'cancel':
                h.cancel();
              case 'pause':
                h.pause();
              case 'reset':
                h.reset();
            }
          },
          onUpdate: (_) => updates++,
          onComplete: () => completes++));
      p.tick(Duration.zero, Duration.zero);
      now = now.add(const Duration(seconds: 2));
      p.tick(const Duration(seconds: 2), const Duration(seconds: 2));
      expect(updates, 1);
      expect(completes, 0);
    });
  }

  test('#4 final countdown update can cancel completion', () {
    var now = DateTime(2024);
    countdownClock = () => now;
    addTearDown(() => countdownClock = DateTime.now);
    final p = Countdown(interval: 0)
      ..onAttach(CountmanContext(requestFrame: () {}));
    late CountdownHandle h;
    var complete = 0;
    h = p.add(CountdownOptions(
        duration: const Duration(seconds: 1),
        onUpdate: (v) {
          if (v.value == Duration.zero) h.cancel();
        },
        onComplete: () => complete++));
    p.tick(Duration.zero, Duration.zero);
    now = now.add(const Duration(seconds: 2));
    p.tick(const Duration(seconds: 2), const Duration(seconds: 2));
    expect(complete, 0);
  });

  test('#5 empty and disposed queues release their cached snapshot', () {
    final p = localCounter();
    final h = p.add(const CounterOptions(to: 1));
    frame(p, 0);
    expect(p.debugSnapshotTaskCount, 1);
    h.cancel();
    expect(p.debugSnapshotTaskCount, 0);
    p.add(const CounterOptions(to: 2));
    frame(p);
    p.dispose();
    expect(p.debugSnapshotTaskCount, 0);
  });

  test('#3 nested cancellation drains a group exactly once', () {
    // 取消回调移除最后一个兄弟任务时，外层不能重复派发排空事件。
    final p = localCounter();
    late CounterHandle b;
    var drained = 0;
    p.onQueueDrained = () => drained++;
    final a = p.add(CounterOptions(to: 1, onCancel: () => b.cancel()));
    b = p.add(const CounterOptions(to: 2));
    a.cancel();
    expect(drained, 1);
  });

  test('#4 pause in initial update defers start until resume', () {
    // 初值回调暂停时，首次启动事件应留给恢复后的活动帧。
    final p = localCounter();
    late CounterHandle h;
    var updates = 0;
    var starts = 0;
    h = p.add(CounterOptions(
        to: 1,
        onUpdate: (_) {
          if (updates++ == 0) h.pause();
        },
        onStart: () => starts++));
    frame(p, 0);
    expect(starts, 0);
    h.resume();
    frame(p);
    expect(starts, 1);
  });

  test('#15 cancelled pending tasks never enter the live map', () {
    final p = localCounter();
    var drained = 0;
    p.onQueueDrained = () => drained++;
    p.add(CounterOptions(
        to: 1,
        duration: Duration.zero,
        onComplete: (_) {
          p.add(const CounterOptions(to: 2)).cancel();
        }));
    frame(p, 0);
    frame(p);
    expect(p.activeTaskCount, 0);
    expect(drained, 1);
  });
}

// 外部借用组在测试结束时显式停帧，避免测试框架先于 tearDown 检查调度残留。
void regressionWidgetTest(String name, WidgetTesterCallback callback) {
  testWidgets(name, (tester) async {
    try {
      await callback(tester);
    } finally {
      Countman.stop();
    }
  });
}
