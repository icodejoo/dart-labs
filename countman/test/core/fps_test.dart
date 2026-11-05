// ignore_for_file: invalid_use_of_internal_member

import 'package:countman/countman.dart';
import 'package:countman/src/core/fps.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/manual_clock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ManualCountmanClock clock;
  setUp(() {
    clock = installManualClock();
    debugRefreshRateHz = 60;
  });
  tearDown(() {
    Countman.destroy();
    Countman.fps = null;
    debugRefreshRateHz = null;
  });

  test('实例 > 插件 > 全局，null 逐级回退', () {
    Countman.fps = 5;
    final plugin = Elapsed(interval: 0, fps: 10)
      ..onAttach(CountmanContext(requestFrame: () {}));
    final inherited = Elapsed(name: 'global', interval: 0)
      ..onAttach(CountmanContext(requestFrame: () {}));
    addTearDown(plugin.dispose);
    addTearDown(inherited.dispose);
    expect(plugin.fps, 10);
    final h = plugin.add(const ElapsedOptions(fps: 20));
    expect(plugin.tick(Duration.zero, Duration.zero), 41667);
    h.fps = null;
    expect(plugin.tick(Duration.zero, Duration.zero), 91667);
    inherited.add(const ElapsedOptions());
    expect(inherited.tick(Duration.zero, Duration.zero), 191667);
    Countman.fps = null;
    expect(inherited.tick(Duration.zero, Duration.zero), 0);
    // Counter 与 Countdown 的同一回退链也经过真实 tick 验证。
    Countman.fps = 5;
    final counter = Counter(fps: 10)..onAttach(CountmanContext(requestFrame: () {}));
    final countdown = Countdown(interval: 0, fps: 10)
      ..onAttach(CountmanContext(requestFrame: () {}));
    addTearDown(counter.dispose);
    addTearDown(countdown.dispose);
    final c = counter.add(const CounterOptions(to: 1, fps: 20));
    final d = countdown.add(const CountdownOptions(duration: Duration(seconds: 2), fps: 20));
    expect(counter.tick(Duration.zero, Duration.zero), 41667);
    expect(countdown.tick(Duration.zero, Duration.zero), 41667);
    c.fps = null;
    d.fps = null;
    expect(counter.tick(Duration.zero, Duration.zero), 91667);
    expect(countdown.tick(Duration.zero, Duration.zero), 91667);
  });

  test('刷新率覆盖可复位，非法刷新率回退 60Hz，屏幕附近的上限等同不限', () {
    for (final hz in [0.0, -1.0, double.nan, double.infinity]) {
      debugRefreshRateHz = hz;
      expect(vsyncPeriodMicros(), 16667);
    }
    debugRefreshRateHz = 120;
    expect(vsyncPeriodMicros(), 8333);
    final plugin = Elapsed(interval: 0)
      ..onAttach(CountmanContext(requestFrame: () {}));
    addTearDown(plugin.dispose);
    final handle = plugin.add(const ElapsedOptions(fps: 60));
    expect(plugin.tick(Duration.zero, Duration.zero), 12501);
    // period <= vsyncPeriod * 1.05 时，不再过滤任何屏幕帧。
    for (final fps in [115.0, 120.0, 240.0]) {
      handle.fps = fps;
      expect(plugin.tick(Duration.zero, Duration.zero), 0);
    }
    debugRefreshRateHz = null;
    expect(debugRefreshRateHz, isNull);
    expect(vsyncPeriodMicros(refresh: true), greaterThan(0));
  });

  for (final separatePlugins in [false, true]) {
    for (final reverse in [false, true]) {
      testWidgets('最早限帧等待走 Timer，不被较晚的普通桶唤醒改成轮询 '
          'separate=$separatePlugins reverse=$reverse', (t) async {
        final limited = Elapsed(name: 'limited', interval: 1000);
        final ordinary = separatePlugins
            ? Elapsed(name: 'ordinary', interval: 1000) : limited;
        void addLimited() => limited.add(ElapsedOptions(
            fps: 30, initial: const Duration(microseconds: 999999)));
        void addOrdinary() => ordinary.add(const ElapsedOptions());
        if (reverse) {
          addOrdinary();
          addLimited();
        } else {
          addLimited();
          addOrdinary();
        }
        await t.pump();
        clock.advance(const Duration(milliseconds: 17));
        Countman.start(); // 模拟其它动画带来的提前帧。
        await t.pump(const Duration(milliseconds: 17));
        // 离限帧请求点还剩 8ms；普通任务的桶边界远在约 1 秒后。
        expect(Countman.isSleeping, isTrue);
        expect(t.binding.hasScheduledFrame, isFalse);
        Countman.destroy();
      });
    }
  }

  testWidgets('全局运行时修改打断休眠，下一帧立即采用新上限', (t) async {
    Countman.fps = 1;
    var updates = 0;
    final plugin = Elapsed(interval: 0);
    plugin.add(ElapsedOptions(onUpdate: (_) => updates++));
    await t.pump();
    expect(updates, 1);
    expect(Countman.isSleeping, isTrue);
    clock.advance(const Duration(milliseconds: 16));
    Countman.fps = null;
    expect(Countman.isSleeping, isFalse);
    await t.pump(const Duration(milliseconds: 16));
    expect(updates, 2);
    Countman.fps = 10;
    clock.advance(const Duration(milliseconds: 16));
    await t.pump(const Duration(milliseconds: 16));
    expect(Countman.isSleeping, isTrue);
    Countman.fps = null;
    await t.pump();
    Countman.destroy();
  });

  testWidgets('Builder 动态改上限保留锚点、进度与 onStart 次数', (t) async {
    var starts = 0;
    var value = 0.0;
    Widget widget(double? fps) => CounterBuilder(to: 100,
      fps: fps, curve: Curves.linear,
      onStart: () => starts++, onUpdate: (v) => value = v,
      builder: (_, __, ___) => const SizedBox());
    await t.pumpWidget(widget(10));
    await t.pump();
    clock.advance(const Duration(milliseconds: 500));
    await t.pump(const Duration(milliseconds: 500));
    expect(value, 50);
    await t.pumpWidget(widget(30));
    expect(value, 50);
    expect(starts, 1);
    clock.advance(const Duration(milliseconds: 500));
    await t.pump(const Duration(milliseconds: 500));
    expect(value, 100);
  });

  test('非法值 debug 断言；覆盖全局、插件、Options 与组件参数', () {
    for (final fps in [0.0, -1.0, double.nan, double.infinity, double.negativeInfinity]) {
      expect(() => Countman.fps = fps, throwsAssertionError);
      expect(() => Counter(fps: fps), throwsAssertionError);
      expect(() => Countdown(fps: fps), throwsAssertionError);
      expect(() => Elapsed(fps: fps), throwsAssertionError);
      expect(() => CounterOptions(to: 1, fps: fps), throwsAssertionError);
      expect(() => CountdownOptions(duration: const Duration(seconds: 1), fps: fps), throwsAssertionError);
      expect(() => ElapsedOptions(fps: fps), throwsAssertionError);
      expect(() => TextCounter(to: 1, fps: fps), throwsAssertionError);
      expect(() => CardCountdown(to: const Duration(seconds: 1), fps: fps), throwsAssertionError);
      expect(() => AnimatedCounter(value: 1, fps: fps), throwsAssertionError);
    }
  });
}
