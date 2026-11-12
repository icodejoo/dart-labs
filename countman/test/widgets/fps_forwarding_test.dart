// ignore_for_file: invalid_use_of_internal_member

import 'package:countman/countman.dart';
import 'package:countman/src/core/fps.dart';
import 'package:countman/src/widgets/card_progress.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/manual_clock.dart';

const _duration = Duration(seconds: 10);

final _counterWidgets = <String, Widget Function(Counter, double?)>{
  'TextCounter': (p, fps) => TextCounter(to: 100, plugin: p, fps: fps),
  'RingCounter': (p, fps) => RingCounter(to: 100, plugin: p, fps: fps),
  'BarCounter': (p, fps) => BarCounter(to: 100, plugin: p, fps: fps),
  'OdometerCounter': (p, fps) => OdometerCounter(
    to: 100,
    // 兼容层仍需将插件与限帧一起传到 AnimatedCounter。
    // ignore: deprecated_member_use_from_same_package
    plugin: p,
    fps: fps,
  ),
  'AnimatedCounter': (p, fps) =>
      AnimatedCounter(value: 100, plugin: p, fps: fps),
  'AnimatedCounterBuilder': (p, fps) =>
      AnimatedCounterBuilder(value: 100, plugin: p, fps: fps),
  'CounterBuilder': (p, fps) => CounterBuilder(
    to: 100,
    plugin: p,
    fps: fps,
    builder: (_, _, _) => const SizedBox(),
  ),
};

final _countdownWidgets = <String, Widget Function(Countdown, double?)>{
  'TextCountdown': (p, fps) =>
      TextCountdown(to: _duration, plugin: p, fps: fps),
  'RingCountdown': (p, fps) =>
      RingCountdown(to: _duration, plugin: p, fps: fps),
  'BarCountdown': (p, fps) =>
      BarCountdown(to: _duration, plugin: p, fps: fps),
  'DialCountdown': (p, fps) =>
      DialCountdown(to: _duration, plugin: p, fps: fps),
  'CountdownBuilder': (p, fps) => CountdownBuilder(
    duration: _duration,
    plugin: p,
    fps: fps,
    builder: (_, _, _) => const SizedBox(),
  ),
};

final _elapsedWidgets = <String, Widget Function(Elapsed, double?)>{
  'TextElapsed': (p, fps) => TextElapsed(plugin: p, fps: fps),
  'ElapsedBuilder': (p, fps) => ElapsedBuilder(
    plugin: p,
    fps: fps,
    builder: (_, _, _) => const SizedBox(),
  ),
};

Future<void> _mount(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: child),
    ),
  );
  // 入场动画在首帧后入队，再泵一帧让共享 ticker 启动任务。
  await tester.pump();
}

void _expectFps<T extends CountmanTask>(
  TaskQueuePlugin<T> plugin,
  T? task,
  double? instanceFps,
  double expectedFps,
) {
  expect(task, isNotNull);
  expect(task!.done, isFalse);
  expect(task.fps, instanceFps);
  // 直接调用引擎实际使用的解析函数，不依赖帧数或真实时间。
  expect(plugin.frameIntervalOf(task), (1000000 / expectedFps).round());
}

Future<void> _expectMigration<T extends CountmanTask>(
  WidgetTester tester,
  TaskQueuePlugin<T> first,
  TaskQueuePlugin<T> second,
  Widget Function(bool) build,
  T? Function(int) oldTask,
  T? Function(int) newTask,
) async {
  Countman.fps = 29;
  Countman.use(first);
  Countman.use(second);
  await _mount(tester, build(false));
  _expectFps(first, oldTask(0), 17, 17);
  expect(oldTask(0)!.started, isTrue);
  final finder = find.byWidgetPredicate(
    (w) => w is CounterBuilder || w is CountdownBuilder || w is ElapsedBuilder,
  );
  final element = tester.element(finder);

  await _mount(tester, build(true));
  expect(tester.element(finder), same(element));
  expect(first.activeTaskCount, 0);
  expect(oldTask(0), isNull);
  expect(second.activeTaskCount, 1);
  _expectFps(second, newTask(0), 17, 17);
  await tester.pumpWidget(const SizedBox());
}

void main() {
  late ManualCountmanClock clock;
  setUp(() {
    clock = installManualClock();
    debugRefreshRateHz = 60;
  });
  tearDown(() {
    Countman.fps = null;
    Countman.destroy();
    debugRefreshRateHz = null;
  });

  // 三个来源分别验证，实例场景同时放入不同的插件与全局值。
  for (final source in [
    (name: '实例覆盖插件与全局', instance: 17.0, plugin: 23.0, global: 29.0),
    (name: '只设插件级', instance: null, plugin: 23.0, global: null),
    (name: '只设全局', instance: null, plugin: null, global: 29.0),
  ]) {
    final expected = source.instance ?? source.plugin ?? source.global!;
    for (final entry in _counterWidgets.entries) {
      testWidgets('${entry.key} ${source.name}', (tester) async {
        Countman.fps = source.global;
        final plugin = Counter(name: 'forward-counter', fps: source.plugin);
        Countman.use(plugin);
        await _mount(tester, entry.value(plugin, source.instance));
        expect(plugin.activeTaskCount, 1);
        _expectFps(plugin, plugin.taskById(0), source.instance, expected);
        await tester.pumpWidget(const SizedBox());
      });
    }
    for (final entry in _countdownWidgets.entries) {
      testWidgets('${entry.key} ${source.name}', (tester) async {
        Countman.fps = source.global;
        final plugin = Countdown(
          name: 'forward-countdown',
          interval: 0,
          fps: source.plugin,
        );
        Countman.use(plugin);
        await _mount(tester, entry.value(plugin, source.instance));
        expect(plugin.activeTaskCount, 1);
        _expectFps(plugin, plugin.task(0), source.instance, expected);
        await tester.pumpWidget(const SizedBox());
      });
    }
    for (final entry in _elapsedWidgets.entries) {
      testWidgets('${entry.key} ${source.name}', (tester) async {
        Countman.fps = source.global;
        final plugin = Elapsed(
          name: 'forward-elapsed',
          interval: 0,
          fps: source.plugin,
        );
        Countman.use(plugin);
        await _mount(tester, entry.value(plugin, source.instance));
        expect(plugin.activeTaskCount, 1);
        _expectFps(plugin, plugin.task(0), source.instance, expected);
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('CardCountdown 共享进度限帧 ${source.name}', (tester) async {
      Countman.fps = source.global;
      final plugin = Countdown(name: 'forward-card', fps: source.plugin);
      final controller = CountdownController();
      Countman.use(plugin);
      await _mount(
        tester,
        CardCountdown(to: _duration, plugin: plugin, fps: source.instance,
          controller: controller),
      );
      final painter =
          tester.widget<CustomPaint>(find.byType(CustomPaint)).painter!
              as FlipCardPainter;
      var notifications = 0;
      void onRepaint() => notifications++;
      painter.addListener(onRepaint);
      try {
        controller.pause(); // 固定数字目标，只检查翻牌进度的限帧来源。
        final progress = painter.controller as CardProgress;
        progress.forward(from: 0.1);
        await tester.pump();
        final first = notifications;
        final period = (1000000 / expected).round();
        final until = period - vsyncPeriodMicros() ~/ 2;
        clock.advance(Duration(microseconds: until - 1));
        await tester.pump(Duration(microseconds: until - 1));
        expect(notifications, first);
        clock.advance(const Duration(microseconds: 1));
        await tester.pump(const Duration(microseconds: 1));
        expect(notifications, first + 1);
      } finally {
        painter.removeListener(onRepaint);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('CounterBuilder 活任务迁移保留实例 fps', (tester) async {
    final a = Counter(name: 'counter-a', fps: 23);
    final b = Counter(name: 'counter-b', fps: 31);
    await _expectMigration(
      tester,
      a,
      b,
      (next) => CounterBuilder(
        to: 100,
        duration: _duration,
        plugin: next ? b : a,
        fps: 17,
        builder: (_, _, _) => const SizedBox(),
      ),
      a.taskById,
      b.taskById,
    );
  });

  testWidgets('CountdownBuilder 活任务迁移保留实例 fps', (tester) async {
    final a = Countdown(name: 'countdown-a', interval: 0, fps: 23);
    final b = Countdown(name: 'countdown-b', interval: 0, fps: 31);
    await _expectMigration(
      tester,
      a,
      b,
      (next) => CountdownBuilder(
        duration: _duration,
        plugin: next ? b : a,
        fps: 17,
        builder: (_, _, _) => const SizedBox(),
      ),
      a.task,
      b.task,
    );
  });

  testWidgets('ElapsedBuilder 活任务迁移保留实例 fps', (tester) async {
    final a = Elapsed(name: 'elapsed-a', interval: 0, fps: 23);
    final b = Elapsed(name: 'elapsed-b', interval: 0, fps: 31);
    await _expectMigration(
      tester,
      a,
      b,
      (next) => ElapsedBuilder(
        plugin: next ? b : a,
        fps: 17,
        builder: (_, _, _) => const SizedBox(),
      ),
      a.task,
      b.task,
    );
  });
}
