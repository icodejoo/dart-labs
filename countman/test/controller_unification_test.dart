// 0.3.0：三个 controller 的 runState / restart、配置入口收口（插件解析与迁移）、animate-once 收口。
// 时间全部由 ManualCountmanClock 与 tester.pump 共同推进，不依赖真实等待。

import 'package:countman/countman.dart';
import 'package:countman/src/widgets/animate_once.dart'
    show debugResetAnimateOnceWarnings;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/manual_clock.dart';

/// 计数类动画的测试时长。
const _counterDuration = Duration(seconds: 10);

/// 倒计时的测试总时长。
const _countdownTotal = Duration(seconds: 100);

/// 推进一小段时间，不使任务结束。
const _step = Duration(seconds: 2);

/// 足以让所有任务结束的时间。
const _beyondEnd = Duration(seconds: 200);

/// 为展示组件提供文字方向与 Material 环境。
Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

/// 记录控制器 runState 的变化序列。
List<CountmanRunState> _record(CountmanRunStateNotifier c) {
  final seen = <CountmanRunState>[];
  c.runStateListenable.addListener(() => seen.add(c.runState));
  return seen;
}

void main() {
  late ManualCountmanClock clock;

  setUp(() {
    clock = installManualClock();
  });

  tearDown(Countman.destroy);

  /// 同时推进手动时钟和共享帧调度；先补一帧让刚创建的任务渲染初值（首帧不消耗时间）。
  Future<void> advance(WidgetTester tester, Duration duration) async {
    await tester.pump();
    clock.advance(duration);
    await tester.pump(duration);
  }

  /// 新建绑定到手动时钟的倒计时插件。
  Countdown newCountdown([String name = 'cd']) =>
      Countdown(name: name, clock: clock);

  /// 新建绑定到手动时钟的正计时插件。
  Elapsed newElapsed([String name = 'el']) => Elapsed(name: name, clock: clock);

  group('CounterValueController runState / restart', () {
    testWidgets('转换序列：running → paused → running → completed → idle',
        (tester) async {
      final c = CounterValueController();
      final seen = _record(c);
      await tester.pumpWidget(_host(TextCounter(
        to: 100,
        duration: _counterDuration,
        controller: c,
      )));
      expect(c.runState, CountmanRunState.running);
      await advance(tester, _step);
      c.pause();
      expect(c.runState, CountmanRunState.paused);
      c.resume();
      expect(c.runState, CountmanRunState.running);
      await advance(tester, _beyondEnd);
      expect(c.runState, CountmanRunState.completed);
      // 结束后 update 请求组件重启：回到 running，再次完成。
      c.update(to: 200);
      expect(c.runState, CountmanRunState.running);
      await advance(tester, _beyondEnd);
      expect(c.runState, CountmanRunState.completed);
      // 运行中取消回到 idle。
      c.update(to: 300);
      await advance(tester, _step);
      c.cancel();
      expect(c.runState, CountmanRunState.idle);
      expect(seen, [
        CountmanRunState.running,
        CountmanRunState.paused,
        CountmanRunState.running,
        CountmanRunState.completed,
        CountmanRunState.running,
        CountmanRunState.completed,
        CountmanRunState.running,
        CountmanRunState.idle,
      ]);
      // 组件销毁后解绑，回到 idle（本就是 idle，不重复通知）。
      await tester.pumpWidget(const SizedBox());
      expect(c.runState, CountmanRunState.idle);
    });

    testWidgets('restart：运行中从头开始', (tester) async {
      final c = CounterValueController();
      await tester.pumpWidget(_host(TextCounter(
        to: 100,
        duration: _counterDuration,
        curve: Curves.linear,
        controller: c,
      )));
      await advance(tester, _step);
      await advance(tester, _step);
      expect(c.value, greaterThan(30));
      c.restart();
      expect(c.runState, CountmanRunState.running);
      await tester.pump();
      expect(c.value, 0);
      await advance(tester, _step);
      expect(c.value, closeTo(20, 1));
    });

    testWidgets('restart：暂停中恢复为 running，结束后可再次播放', (tester) async {
      final c = CounterValueController();
      var completed = 0;
      await tester.pumpWidget(_host(TextCounter(
        to: 100,
        duration: _counterDuration,
        controller: c,
        onComplete: (_) => completed++,
      )));
      await advance(tester, _step);
      c.pause();
      expect(c.runState, CountmanRunState.paused);
      c.restart();
      expect(c.runState, CountmanRunState.running);
      expect(c.isPaused, isFalse);
      await advance(tester, _beyondEnd);
      expect(completed, 1);
      expect(c.runState, CountmanRunState.completed);
      c.restart();
      expect(c.runState, CountmanRunState.running);
      await advance(tester, _beyondEnd);
      expect(completed, 2);
      expect(c.runState, CountmanRunState.completed);
    });

    test('未绑定时 restart 无操作，状态保持 idle', () {
      final c = CounterValueController();
      c.restart();
      expect(c.runState, CountmanRunState.idle);
    });

    testWidgets('dispose 后晚到的状态写入被忽略', (tester) async {
      final c = CounterValueController();
      await tester.pumpWidget(_host(TextCounter(to: 100, controller: c)));
      c.dispose();
      // 组件销毁时的 detach 写入 idle 不应抛异常。
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('CountdownController runState / restart', () {
    testWidgets('转换序列与 restart（运行中、暂停中、结束后）', (tester) async {
      final plugin = newCountdown();
      final c = CountdownController();
      final seen = _record(c);
      await tester.pumpWidget(_host(TextCountdown(
        to: _countdownTotal,
        plugin: plugin,
        controller: c,
      )));
      expect(c.runState, CountmanRunState.running);
      await advance(tester, _step);
      c.pause();
      expect(c.runState, CountmanRunState.paused);
      c.resume();
      expect(c.runState, CountmanRunState.running);
      // 运行中 restart：剩余时间回到组件配置的总时长。
      await advance(tester, _step);
      expect(c.remaining, lessThan(_countdownTotal));
      c.restart();
      expect(c.runState, CountmanRunState.running);
      expect(c.remaining, _countdownTotal);
      // 暂停中 restart：不再暂停。
      c.pause();
      c.restart();
      expect(c.runState, CountmanRunState.running);
      expect(c.isPaused, isFalse);
      // 结束后 restart 回到 running，再次完成。
      await advance(tester, _beyondEnd);
      expect(c.runState, CountmanRunState.completed);
      c.restart();
      expect(c.runState, CountmanRunState.running);
      expect(c.remaining, _countdownTotal);
      await advance(tester, _beyondEnd);
      expect(c.runState, CountmanRunState.completed);
      c.restart();
      c.cancel();
      expect(c.runState, CountmanRunState.idle);
      expect(seen.first, CountmanRunState.running);
      expect(seen.last, CountmanRunState.idle);
      expect(seen, contains(CountmanRunState.paused));
      expect(seen, contains(CountmanRunState.completed));
    });

    test('未绑定时 restart 无操作', () {
      final c = CountdownController();
      c.restart();
      expect(c.runState, CountmanRunState.idle);
    });

    testWidgets('reset 在存活任务上保持 running', (tester) async {
      final plugin = newCountdown();
      final c = CountdownController();
      await tester.pumpWidget(_host(TextCountdown(
        to: _countdownTotal,
        plugin: plugin,
        controller: c,
      )));
      await advance(tester, _step);
      c.pause();
      c.reset();
      expect(c.runState, CountmanRunState.running);
      expect(c.remaining, _countdownTotal);
    });
  });

  group('ElapsedController runState / restart', () {
    testWidgets('转换序列、limit 完成、restart 与圈速清空', (tester) async {
      final plugin = newElapsed();
      final c = ElapsedController();
      final seen = _record(c);
      await tester.pumpWidget(_host(TextElapsed(
        plugin: plugin,
        controller: c,
        limit: const Duration(seconds: 30),
      )));
      expect(c.runState, CountmanRunState.running);
      await advance(tester, _step);
      c.lap();
      expect(c.laps, hasLength(1));
      c.pause();
      expect(c.runState, CountmanRunState.paused);
      c.resume();
      expect(c.runState, CountmanRunState.running);
      // 运行中 restart：累计清零、圈速清空。
      c.restart();
      expect(c.runState, CountmanRunState.running);
      expect(c.laps, isEmpty);
      expect(c.elapsed, Duration.zero);
      // 暂停中 restart：不再暂停。
      await advance(tester, _step);
      c.pause();
      c.restart();
      expect(c.isPaused, isFalse);
      expect(c.runState, CountmanRunState.running);
      // 到达 limit 完成，完成后 restart 重新开始。
      await advance(tester, _beyondEnd);
      expect(c.runState, CountmanRunState.completed);
      c.restart();
      expect(c.runState, CountmanRunState.running);
      expect(c.elapsed, Duration.zero);
      c.cancel();
      expect(c.runState, CountmanRunState.idle);
      expect(seen.first, CountmanRunState.running);
      expect(seen.last, CountmanRunState.idle);
    });

    testWidgets('restart 重新读取 initial 起点，reset 总是从零', (tester) async {
      final plugin = newElapsed();
      final c = ElapsedController();
      await tester.pumpWidget(_host(TextElapsed(
        plugin: plugin,
        controller: c,
        initial: const Duration(seconds: 20),
      )));
      await advance(tester, _step);
      c.restart();
      expect(c.elapsed, const Duration(seconds: 20));
      c.reset();
      expect(c.elapsed, Duration.zero);
    });

    test('未绑定时 restart 无操作', () {
      final c = ElapsedController();
      c.restart();
      expect(c.runState, CountmanRunState.idle);
    });
  });

  group('CountdownBuilder 读取 CountdownProvider.plugin', () {
    testWidgets('CountdownBuilder 的任务进入 Provider 提供的分组', (tester) async {
      final plugin = newCountdown('provided');
      var ready = 0;
      final unsubscribe = plugin.addGroupListener(onReady: () => ready++);
      addTearDown(unsubscribe);
      await tester.pumpWidget(_host(CountdownProvider(
        plugin: plugin,
        child: CountdownBuilder(
          duration: _countdownTotal,
          builder: (_, __, ___) => const SizedBox(),
        ),
      )));
      expect(ready, 1);
    });

    testWidgets('CountdownProvider(onAllComplete) 对 CardCountdown 触发一次',
        (tester) async {
      var completed = 0;
      await tester.pumpWidget(_host(CountdownProvider(
        onAllComplete: () => completed++,
        child: const CardCountdown(to: Duration(seconds: 3)),
      )));
      expect(completed, 0);
      await advance(tester, const Duration(seconds: 5));
      await advance(tester, const Duration(seconds: 1));
      expect(completed, 1);
    });
  });

  group('插件变化时迁移任务并保留状态', () {
    testWidgets('倒计时：保留剩余时间，暂停态保留', (tester) async {
      final a = newCountdown('a');
      final b = newCountdown('b');
      final c = CountdownController();
      var cancels = 0;
      var pauses = 0;
      Widget build(Countdown plugin) => _host(CountdownProvider(
            plugin: plugin,
            child: TextCountdown(
              to: _countdownTotal,
              controller: c,
              onCancel: () => cancels++,
              onPause: () => pauses++,
            ),
          ));
      await tester.pumpWidget(build(a));
      await advance(tester, const Duration(seconds: 10));
      await tester.pumpWidget(build(b));
      expect(c.remaining, const Duration(seconds: 90));
      expect(c.runState, CountmanRunState.running);
      await advance(tester, const Duration(seconds: 5));
      expect(c.remaining, const Duration(seconds: 85));
      // 暂停后再换回 a：仍暂停，剩余不变，用户的 onCancel / onPause 不被重复触发。
      c.pause();
      expect(pauses, 1);
      await tester.pumpWidget(build(a));
      expect(c.isPaused, isTrue);
      expect(c.runState, CountmanRunState.paused);
      expect(c.remaining, const Duration(seconds: 85));
      expect(pauses, 1);
      expect(cancels, 0);
      c.resume();
      await advance(tester, const Duration(seconds: 5));
      expect(c.remaining, const Duration(seconds: 80));
    });

    testWidgets('倒计时：进度分母随迁移保持不变', (tester) async {
      final a = newCountdown('a');
      final b = newCountdown('b');
      double? progress;
      Widget build(Countdown plugin) => _host(CountdownProvider(
            plugin: plugin,
            child: CountdownBuilder(
              duration: _countdownTotal,
              builder: (_, parts, __) {
                progress = parts.progress;
                return const SizedBox();
              },
            ),
          ));
      await tester.pumpWidget(build(a));
      await advance(tester, const Duration(seconds: 50));
      await tester.pumpWidget(build(b));
      await tester.pump();
      expect(progress, closeTo(0.5, 0.02));
    });

    testWidgets('倒计时：已完成的任务换插件不会重新完成', (tester) async {
      final a = newCountdown('a');
      final b = newCountdown('b');
      var completed = 0;
      Widget build(Countdown plugin) => _host(CountdownProvider(
            plugin: plugin,
            child: TextCountdown(
              to: const Duration(seconds: 3),
              onComplete: () => completed++,
            ),
          ));
      await tester.pumpWidget(build(a));
      await advance(tester, const Duration(seconds: 5));
      await advance(tester, const Duration(seconds: 1));
      expect(completed, 1);
      await tester.pumpWidget(build(b));
      await advance(tester, const Duration(seconds: 5));
      expect(completed, 1);
    });

    testWidgets('正计时：保留已经过时长与圈速', (tester) async {
      final a = newElapsed('a');
      final b = newElapsed('b');
      final c = ElapsedController();
      Widget build(Elapsed plugin) => _host(ElapsedProvider(
            plugin: plugin,
            child: TextElapsed(controller: c),
          ));
      await tester.pumpWidget(build(a));
      await advance(tester, const Duration(seconds: 7));
      expect(c.lap(), const Duration(seconds: 7));
      await tester.pumpWidget(build(b));
      expect(c.elapsed, const Duration(seconds: 7));
      expect(c.laps, [const Duration(seconds: 7)]);
      await advance(tester, const Duration(seconds: 3));
      expect(c.elapsed, const Duration(seconds: 10));
      expect(c.lap(), const Duration(seconds: 3));
    });

    testWidgets('正计时：暂停态在迁移后保留', (tester) async {
      final a = newElapsed('a');
      final b = newElapsed('b');
      final c = ElapsedController();
      Widget build(Elapsed plugin) => _host(ElapsedProvider(
            plugin: plugin,
            child: TextElapsed(controller: c),
          ));
      await tester.pumpWidget(build(a));
      await advance(tester, const Duration(seconds: 4));
      c.pause();
      await tester.pumpWidget(build(b));
      expect(c.isPaused, isTrue);
      await advance(tester, const Duration(seconds: 4));
      expect(c.elapsed, const Duration(seconds: 4));
    });

    testWidgets('计数器：从当前显示值继续，暂停态保留', (tester) async {
      final a = Counter(name: 'a');
      final b = Counter(name: 'b');
      final c = CounterValueController();
      Widget build(Counter plugin) => _host(CounterProvider(
            plugin: plugin,
            child: CounterBuilder(
              to: 100,
              duration: _counterDuration,
              curve: Curves.linear,
              controller: c,
              builder: (_, __, ___) => const SizedBox(),
            ),
          ));
      await tester.pumpWidget(build(a));
      await advance(tester, _step);
      await advance(tester, _step);
      final before = c.value;
      expect(before, greaterThan(30));
      await tester.pumpWidget(build(b));
      expect(c.runState, CountmanRunState.running);
      await tester.pump();
      expect(c.value, closeTo(before, 0.5), reason: '迁移不跳变');
      await advance(tester, _step);
      expect(c.value, greaterThan(before));
      // 暂停后换回 a：保持暂停且数值不变。
      c.pause();
      final paused = c.value;
      await tester.pumpWidget(build(a));
      expect(c.isPaused, isTrue);
      expect(c.runState, CountmanRunState.paused);
      await advance(tester, _step);
      expect(c.value, paused);
    });

    testWidgets('CounterBuilder 读取 CounterProvider.plugin', (tester) async {
      final plugin = Counter(name: 'provided');
      var ready = 0;
      final unsubscribe = plugin.addGroupListener(onReady: () => ready++);
      addTearDown(unsubscribe);
      await tester.pumpWidget(_host(CounterProvider(
        plugin: plugin,
        child: CounterBuilder(
          to: 10,
          builder: (_, __, ___) => const SizedBox(),
        ),
      )));
      expect(ready, 1);
    });

    testWidgets('CounterBuilder 感知 MediaQuery 的减弱动画', (tester) async {
      double? shown;
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: CounterBuilder(
          to: 100,
          duration: _counterDuration,
          builder: (_, value, __) {
            shown = value;
            return const SizedBox();
          },
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(shown, 100);
    });
  });

  group('animate-once 收口', () {
    /// 捕获 body 期间的 debugPrint 输出；必须在测试体内恢复，否则会触发框架的
    /// “debug 变量被测试改动”断言。
    Future<List<String>> captureDebugPrint(Future<void> Function() body) async {
      final log = <String>[];
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) => log.add(message ?? '');
      debugResetAnimateOnceWarnings();
      try {
        await body();
      } finally {
        debugPrint = original;
      }
      return log;
    }

    testWidgets('无 key 的 TextCounter / RingCounter 在 animateOnce Provider 下不断言，正常动画',
        (tester) async {
      final text = CounterValueController();
      final ring = CounterValueController();
      await captureDebugPrint(() async {
        await tester.pumpWidget(_host(CounterProvider(
          animateOnce: true,
          child: Column(children: [
            TextCounter(to: 100, duration: _counterDuration, controller: text),
            RingCounter(to: 100, duration: _counterDuration, controller: ring),
          ]),
        )));
        await advance(tester, _step);
      });
      expect(tester.takeException(), isNull);
      expect(text.isAnimating, isTrue);
      expect(ring.isAnimating, isTrue);
      expect(text.value, inInclusiveRange(1, 99));
      expect(ring.value, inInclusiveRange(1, 99));
    });

    testWidgets('缺少稳定 id 时 debug 下只警告一次', (tester) async {
      final log = await captureDebugPrint(() async {
        await tester.pumpWidget(_host(CounterProvider(
          animateOnce: true,
          child: Column(children: const [
            TextCounter(to: 1),
            TextCounter(to: 2),
            RingCounter(to: 3),
          ]),
        )));
      });
      final warnings = log.where((m) => m.contains('animateOnce')).toList();
      expect(warnings.where((m) => m.contains('稳定 id')), hasLength(1));
    });

    testWidgets('没有 Provider 时开启 animateOnce：警告并退化为每次都动画',
        (tester) async {
      final c = CounterValueController();
      final log = await captureDebugPrint(() async {
        await tester.pumpWidget(_host(TextCounter(
          key: const ValueKey('row'),
          to: 100,
          duration: _counterDuration,
          animateOnce: true,
          controller: c,
        )));
        await advance(tester, _step);
      });
      expect(tester.takeException(), isNull);
      expect(c.isAnimating, isTrue);
      expect(log.where((m) => m.contains('CounterProvider')), hasLength(1));
    });

    testWidgets('有稳定 id 与 Provider 时行为不变：再次挂载直接显示终值',
        (tester) async {
      Widget page(bool show, CounterValueController c) => _host(CounterProvider(
            animateOnce: true,
            child: show
                ? TextCounter(
                    key: const ValueKey('row'),
                    to: 100,
                    duration: _counterDuration,
                    controller: c,
                  )
                : const SizedBox(),
          ));
      final first = CounterValueController();
      final second = CounterValueController();
      final log = await captureDebugPrint(() async {
        await tester.pumpWidget(page(true, first));
        await advance(tester, _step);
        expect(first.isAnimating, isTrue);
        await tester.pumpWidget(page(false, first));
        await tester.pumpWidget(page(true, second));
      });
      expect(second.value, 100);
      expect(second.runState, CountmanRunState.completed);
      expect(log, isEmpty);
    });
  });
}
