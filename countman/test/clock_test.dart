import 'package:countman/countman.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/manual_clock.dart';

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
      expect(
        clock.monotonicMicros(),
        const Duration(minutes: 5).inMicroseconds,
      );
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
      expect(
        clock.monotonicMicros(),
        const Duration(minutes: 2).inMicroseconds,
      );
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

  group('引擎锚点：相对时长走单调钟，绝对截止走墙钟', () {
    late ManualCountmanClock clock;
    late Countdown countdowns;
    late Elapsed elapseds;

    setUp(() {
      clock = ManualCountmanClock(wallTime: DateTime.utc(2026));
      countdowns = Countdown(name: 'anchor-cd', interval: 0, clock: clock)
        ..onAttach(CountmanContext(requestFrame: () {}));
      elapseds = Elapsed(name: 'anchor-el', interval: 0, clock: clock)
        ..onAttach(CountmanContext(requestFrame: () {}));
    });

    test('相对倒计时不受 jumpWall 影响', () {
      final h = countdowns.add(
        const CountdownOptions(duration: Duration(minutes: 10)),
      );
      clock.advance(second);
      clock.jumpWall(const Duration(hours: 5));
      expect(h.remaining, const Duration(minutes: 10) - second);
      clock.jumpWall(const Duration(hours: -8));
      expect(h.remaining, const Duration(minutes: 10) - second);
    });

    test('绝对 deadline 倒计时跟随 jumpWall', () {
      final deadline = DateTime.utc(2026).add(const Duration(minutes: 10));
      final h = countdowns.add(CountdownOptions(deadline: deadline));
      expect(h.remaining, const Duration(minutes: 10));
      clock.jumpWall(const Duration(minutes: 4));
      expect(h.remaining, const Duration(minutes: 6));
      clock.jumpWall(const Duration(minutes: 7));
      expect(h.remaining, Duration.zero);
    });

    test('已过期的 deadline 首帧即完成', () {
      var done = false;
      countdowns.add(
        CountdownOptions(
          deadline: DateTime.utc(2025),
          onComplete: () => done = true,
        ),
      );
      countdowns.tick(Duration.zero, Duration.zero);
      expect(done, isTrue);
    });

    test('suspend 后相对倒计时与正计时都补上深睡时长', () {
      final cd = countdowns.add(
        const CountdownOptions(duration: Duration(hours: 1)),
      );
      final el = elapseds.add(const ElapsedOptions());
      clock.advance(second);
      clock.suspend(const Duration(minutes: 20));
      expect(
        cd.remaining,
        const Duration(hours: 1) - second - const Duration(minutes: 20),
      );
      expect(el.elapsed, second + const Duration(minutes: 20));
    });

    test('suspend 期间到期的相对倒计时在恢复后的首帧完成', () {
      var done = false;
      countdowns.add(
        CountdownOptions(
          duration: const Duration(minutes: 5),
          onComplete: () => done = true,
        ),
      );
      countdowns.tick(Duration.zero, Duration.zero);
      clock.suspend(const Duration(minutes: 10));
      countdowns.tick(
        const Duration(milliseconds: 16),
        const Duration(milliseconds: 16),
      );
      expect(done, isTrue);
    });

    test('暂停后恢复一律按单调钟重新锚定，恢复前的墙钟跳变不影响剩余', () {
      final deadline = DateTime.utc(2026).add(const Duration(minutes: 10));
      final h = countdowns.add(CountdownOptions(deadline: deadline));
      clock.advance(const Duration(minutes: 1));
      h.pause();
      expect(h.remaining, const Duration(minutes: 9));
      clock.jumpWall(const Duration(hours: 2));
      clock.advance(const Duration(minutes: 3));
      h.resume();
      expect(h.remaining, const Duration(minutes: 9));
      // 恢复后是相对计时：墙钟再跳变也不影响。
      clock.jumpWall(const Duration(hours: -5));
      clock.advance(const Duration(minutes: 1));
      expect(h.remaining, const Duration(minutes: 8));
    });

    test('reset 按单调钟锚定总时长', () {
      final deadline = DateTime.utc(2026).add(const Duration(minutes: 10));
      final h = countdowns.add(CountdownOptions(deadline: deadline));
      clock.advance(const Duration(minutes: 4));
      h.reset();
      clock.jumpWall(const Duration(hours: 1));
      expect(h.remaining, const Duration(minutes: 10));
    });

    test('CountdownOptions 必须且只能给 duration 与 deadline 之一', () {
      final d = DateTime.utc(2026);
      const duration = Duration(seconds: 1);
      expect(() => CountdownOptions(), throwsAssertionError);
      expect(
        () => CountdownOptions(duration: duration, deadline: d),
        throwsAssertionError,
      );
    });
  });

  group('组件锚点', () {
    tearDown(Countman.destroy);

    Widget host(Widget child) =>
        Directionality(textDirection: TextDirection.ltr, child: child);

    testWidgets('CountdownBuilder 的 DateTime 目标跟随 jumpWall，Duration 不受影响', (
      t,
    ) async {
      final clock = installManualClock(wallTime: DateTime.utc(2026));
      final relative = CountdownController();
      final absolute = CountdownController();
      await t.pumpWidget(
        host(
          Column(
            children: [
              CountdownBuilder(
                to: const Duration(minutes: 10),
                controller: relative,
                builder: (_, p, __) => const SizedBox(),
              ),
              CountdownBuilder(
                to: DateTime.utc(2026).add(const Duration(minutes: 10)),
                controller: absolute,
                builder: (_, p, __) => const SizedBox(),
              ),
            ],
          ),
        ),
      );
      await t.pump();
      clock.jumpWall(const Duration(minutes: 4));
      expect(relative.remaining, const Duration(minutes: 10));
      expect(absolute.remaining, const Duration(minutes: 6));
      Countman.destroy();
    });

    testWidgets('CardCountdown 的 DateTime 目标同样按墙钟锚定', (t) async {
      final clock = installManualClock(wallTime: DateTime.utc(2026));
      final controller = CountdownController();
      await t.pumpWidget(
        host(
          CardCountdown(
            to: DateTime.utc(2026).add(const Duration(minutes: 10)),
            controller: controller,
          ),
        ),
      );
      await t.pump();
      clock.jumpWall(const Duration(minutes: 4));
      expect(controller.remaining, const Duration(minutes: 6));
      Countman.destroy();
    });
  });

  test('CountmanClock.system 默认是 SystemClock', () {
    expect(CountmanClock.system, isA<SystemClock>());
  });
}
