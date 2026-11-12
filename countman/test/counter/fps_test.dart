// ignore_for_file: invalid_use_of_internal_member

import 'package:countman/countman.dart';
import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/manual_clock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ManualCountmanClock clock;
  setUp(() => clock = installManualClock());
  tearDown(() {
    Countman.destroy();
    Countman.fps = null;
  });

  testWidgets('16ms 帧步长下 30fps 约 30 次，休眠仍按真实时刻完成', (t) async {
    // 同一路径先测不限帧，再测限帧，避免逐帧任务阻止休眠。
    Future<int> run(double? fps) async {
      var updates = 0;
      var completes = 0;
      var value = 0.0;
      final start = clock.monotonicMicros();
      final handle = counter(CounterOptions(
        to: 100,
        fps: fps,
        curve: Curves.linear,
        onUpdate: (v) { updates++; value = v; },
        onComplete: (_) {
          completes++;
          expect(clock.monotonicMicros() - start, 1000000);
        },
      ));
      await t.pump();
      if (fps != null) expect(Countman.isSleeping, isTrue);
      for (var i = 0; i < 62; i++) {
        clock.advance(const Duration(milliseconds: 16));
        await t.pump(const Duration(milliseconds: 16));
      }
      clock.advance(const Duration(milliseconds: 8));
      await t.pump(const Duration(milliseconds: 8));
      expect(value, 100);
      expect(completes, 1);
      expect(handle.isDone, isTrue);
      await t.pump(const Duration(milliseconds: 16));
      expect(completes, 1);
      Countman.destroy();
      return updates;
    }
    expect(await run(null), inInclusiveRange(60, 66));
    expect(await run(30), inInclusiveRange(27, 33));
  });

  test('500ms 时限帧与 dt 路径数值一致；完成强制显示精确终值', () {
    final normal = Counter(name: 'normal')
      ..onAttach(CountmanContext(requestFrame: () {}));
    final limited = Counter(name: 'limited', fps: 30)
      ..onAttach(CountmanContext(requestFrame: () {}));
    addTearDown(normal.dispose);
    addTearDown(limited.dispose);
    var plain = 0.0;
    var capped = 0.0;
    var completes = 0;
    normal.add(CounterOptions(to: 100, curve: Curves.linear, onUpdate: (v) => plain = v));
    limited.add(CounterOptions(to: 100, curve: Curves.linear,
      onUpdate: (v) => capped = v, onComplete: (_) => completes++));
    normal.tick(Duration.zero, Duration.zero);
    limited.tick(Duration.zero, Duration.zero);
    clock.advance(const Duration(milliseconds: 500));
    normal.tick(Duration.zero, const Duration(milliseconds: 500));
    limited.tick(Duration.zero, Duration.zero); // 休眠后 dt 为零。
    expect(capped, closeTo(plain, 0.000001));
    expect(capped, 50);
    clock.advance(const Duration(milliseconds: 500));
    limited.tick(Duration.zero, Duration.zero);
    expect(capped, 100);
    expect(completes, 1);
    limited.tick(Duration.zero, Duration.zero);
    expect(completes, 1);
  });

  test('限帧暂停、恢复、重定向与迁移保留真实进度', () {
    final first = Counter(fps: 10)..onAttach(CountmanContext(requestFrame: () {}));
    final second = Counter(name: 'second', fps: 30)
      ..onAttach(CountmanContext(requestFrame: () {}));
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    var handle = first.add(const CounterOptions(to: 100, fps: 20, curve: Curves.linear));
    first.tick(Duration.zero, Duration.zero);
    clock.advance(const Duration(milliseconds: 250));
    handle.pause();
    expect(handle.currentValue, 25);
    clock.advance(const Duration(seconds: 1));
    handle.resume();
    clock.advance(const Duration(milliseconds: 250));
    handle = handle.migrateTo(second);
    second.tick(Duration.zero, Duration.zero);
    expect(handle.currentValue, 50);
    handle.update(to: 150, duration: const Duration(seconds: 1));
    second.tick(Duration.zero, Duration.zero);
    clock.advance(const Duration(milliseconds: 500));
    second.tick(Duration.zero, Duration.zero);
    expect(handle.currentValue, closeTo(100, 0.000001));
  });

  test('低帧率仍在终点唤醒；静音优先且恢复立即显示', () {
    final plugin = Counter(fps: 0.1)..onAttach(CountmanContext(requestFrame: () {}));
    addTearDown(plugin.dispose);
    final values = <double>[];
    final handle = plugin.add(CounterOptions(to: 100, curve: Curves.linear, onUpdate: values.add));
    expect(plugin.tick(Duration.zero, Duration.zero), 1000000);
    clock.advance(const Duration(milliseconds: 100));
    handle.muted = true;
    expect(plugin.tick(Duration.zero, Duration.zero), 900000);
    clock.advance(const Duration(milliseconds: 400));
    handle.muted = false;
    plugin.tick(Duration.zero, Duration.zero);
    expect(values, [0, 50]);
    clock.advance(const Duration(milliseconds: 500));
    plugin.tick(Duration.zero, Duration.zero);
    expect(values.last, 100);
  });
}
