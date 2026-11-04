import 'package:countman/countman.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证时钟抽象：手动时钟、偏移时钟与系统时钟的前台恢复校准。
void main() {
  const second = Duration(seconds: 1);

  group('ManualCountmanClock', () {
    test('advance 同时推进墙钟与单调钟', () {
      final clock = ManualCountmanClock(wallTime: DateTime.utc(2026));
      final wall = clock.wallMicros();
      clock.advance(const Duration(seconds: 3));
      expect(clock.wallMicros() - wall, 3 * Duration.microsecondsPerSecond);
      expect(clock.monotonicMicros(), 3 * Duration.microsecondsPerSecond);
    });

    test('jumpWall 只动墙钟，可正可负', () {
      final clock = ManualCountmanClock();
      clock.jumpWall(const Duration(hours: 1));
      expect(clock.wallMicros(), Duration.microsecondsPerHour);
      expect(clock.monotonicMicros(), 0);
      clock.jumpWall(const Duration(hours: -2));
      expect(clock.wallMicros(), -Duration.microsecondsPerHour);
    });

    test('suspend 只推进墙钟，恢复后把深睡时长补到单调钟', () {
      final clock = ManualCountmanClock();
      clock.advance(second);
      clock.suspend(const Duration(minutes: 5));
      expect(
        clock.monotonicMicros(),
        second.inMicroseconds + Duration.microsecondsPerMinute * 5,
      );
      expect(
        clock.wallMicros(),
        second.inMicroseconds + Duration.microsecondsPerMinute * 5,
      );
    });

    test('suspend 不超过一秒的差值视为采样误差，不补偿', () {
      final clock = ManualCountmanClock();
      clock.suspend(const Duration(milliseconds: 900));
      expect(clock.monotonicMicros(), 0);
    });

    test('多次 suspend 的补偿累加', () {
      final clock = ManualCountmanClock();
      clock.suspend(const Duration(minutes: 1));
      clock.advance(second);
      clock.suspend(const Duration(minutes: 2));
      expect(
        clock.monotonicMicros(),
        Duration.microsecondsPerMinute * 3 + second.inMicroseconds,
      );
    });
  });

  group('OffsetClock', () {
    test('墙钟加偏移，单调钟透传', () {
      final base = ManualCountmanClock();
      final clock = OffsetClock(base, const Duration(seconds: 2));
      base.advance(second);
      expect(clock.wallMicros(), 3 * Duration.microsecondsPerSecond);
      expect(clock.monotonicMicros(), Duration.microsecondsPerSecond);
    });

    test('负偏移与基础时钟的 suspend 同样生效', () {
      final base = ManualCountmanClock();
      final clock = OffsetClock(base, const Duration(seconds: -1));
      base.suspend(const Duration(minutes: 1));
      expect(clock.wallMicros(), Duration.microsecondsPerMinute - 1000000);
      expect(clock.monotonicMicros(), Duration.microsecondsPerMinute);
    });
  });

  group('SystemClock', () {
    late DateTime Function() originalWall;
    late Duration Function() originalMono;
    late DateTime wall;
    late Duration mono;

    setUp(() {
      originalWall = countdownClock;
      originalMono = elapsedClock;
      wall = DateTime.utc(2026);
      mono = Duration.zero;
      countdownClock = () => wall;
      elapsedClock = () => mono;
    });

    tearDown(() {
      countdownClock = originalWall;
      elapsedClock = originalMono;
    });

    /// 推进墙钟与单调钟；[wallOnly] 为 true 时只推进墙钟（深睡或手动改时间）。
    void tick(Duration d, {bool wallOnly = false}) {
      wall = wall.add(d);
      if (!wallOnly) mono += d;
    }

    testWidgets('读取底层注入的两个时间源', (tester) async {
      final clock = SystemClock();
      addTearDown(clock.dispose);
      expect(clock.wallMicros(), wall.microsecondsSinceEpoch);
      tick(second);
      expect(clock.monotonicMicros(), second.inMicroseconds);
    });

    testWidgets('进入后台期间墙钟多走的时长在 resumed 时补到单调钟', (tester) async {
      final clock = SystemClock();
      addTearDown(clock.dispose);
      clock.monotonicMicros(); // 触发懒注册
      tick(second);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tick(const Duration(minutes: 10), wallOnly: true);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(
        clock.monotonicMicros(),
        (second + const Duration(minutes: 10)).inMicroseconds,
      );
    });

    testWidgets('前台墙钟跳变一律不补偿', (tester) async {
      final clock = SystemClock();
      addTearDown(clock.dispose);
      clock.monotonicMicros();
      tick(const Duration(hours: 3), wallOnly: true);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(clock.monotonicMicros(), 0);
    });

    testWidgets('后台期间墙钟与单调钟同步走（桌面最小化）不补偿', (tester) async {
      final clock = SystemClock();
      addTearDown(clock.dispose);
      clock.monotonicMicros();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tick(const Duration(minutes: 5));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(clock.monotonicMicros(), const Duration(minutes: 5).inMicroseconds);
    });

    testWidgets('hidden 之后再 paused 不覆盖后台起点', (tester) async {
      final clock = SystemClock();
      addTearDown(clock.dispose);
      clock.monotonicMicros();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tick(const Duration(minutes: 1), wallOnly: true);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tick(const Duration(minutes: 1), wallOnly: true);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(clock.monotonicMicros(), const Duration(minutes: 2).inMicroseconds);
    });

    testWidgets('dispose 之后不再响应生命周期', (tester) async {
      final clock = SystemClock();
      clock.monotonicMicros();
      clock.dispose();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tick(const Duration(minutes: 5), wallOnly: true);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      // dispose 后再读取会重新注册，但此前的后台时长已经错过，不会补偿。
      expect(clock.monotonicMicros(), 0);
      clock.dispose();
    });
  });

  test('CountmanClock.system 默认是 SystemClock', () {
    expect(CountmanClock.system, isA<SystemClock>());
  });
}
