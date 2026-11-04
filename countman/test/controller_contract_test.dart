import 'package:countman/countman.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 各类动画共用的测试时长。
const _duration = Duration(seconds: 10);

/// 用于推进动画而不使任务结束的时间片。
const _step = Duration(seconds: 2);

/// 为绘制组件提供文字方向。
Widget _host(Widget child) =>
    Directionality(textDirection: TextDirection.ltr, child: child);

/// 仅保留数值更新，避免测试依赖文字格式。
Widget _number(BuildContext context, double value, Widget? child) =>
    const SizedBox();

/// 仅保留计时更新，避免测试依赖文字格式。
Widget _time(BuildContext context, TimeParts parts, Widget? child) =>
    const SizedBox();

/// 验证展示组件绑定、换绑与任务重启的控制器契约。
void main() {
  late DateTime wall;
  late Duration monotonic;
  late DateTime Function() originalCountdownClock;
  late Duration Function() originalElapsedClock;

  setUp(() {
    wall = DateTime(2026);
    monotonic = Duration.zero;
    originalCountdownClock = countdownClock;
    originalElapsedClock = elapsedClock;
    countdownClock = () => wall;
    elapsedClock = () => monotonic;
  });

  tearDown(() {
    Countman.destroy();
    countdownClock = originalCountdownClock;
    elapsedClock = originalElapsedClock;
  });

  /// 同时推进假时钟和共享帧调度。
  Future<void> advance(WidgetTester tester, Duration duration) async {
    wall = wall.add(duration);
    monotonic += duration;
    await tester.pump(duration);
  }

  for (final kind in ['counter', 'countdown', 'elapsed', 'card']) {
    testWidgets('$kind 换 key 后新绑定仍可控制', (tester) async {
      final counter = CounterValueController();
      final countdown = CountdownController();
      final elapsed = ElapsedController();

      /// 构造不同 key 的同类展示组件。
      Widget display(int key) => switch (kind) {
            'counter' => CounterBuilder(
                key: ValueKey(key),
                to: 100,
                duration: _duration,
                controller: counter,
                builder: _number),
            'countdown' => CountdownBuilder(
                key: ValueKey(key),
                duration: _duration,
                precise: true,
                controller: countdown,
                builder: _time),
            'elapsed' => ElapsedBuilder(
                key: ValueKey(key),
                precise: true,
                controller: elapsed,
                builder: _time),
            _ => CardCountdown(
                key: ValueKey(key), to: _duration, controller: countdown),
          };

      await tester.pumpWidget(_host(display(1)));
      await tester.pumpWidget(_host(display(2)));
      await tester.pump();
      if (kind == 'counter') {
        counter.update(to: 500);
        await tester.pump();
        await advance(tester, _duration);
        expect(counter.value, 500);
      } else if (kind == 'elapsed') {
        elapsed.pause();
        expect(elapsed.isPaused, isTrue);
        elapsed.reset();
        await tester.pump();
        expect(elapsed.elapsed, Duration.zero);
        expect(elapsed.isPaused, isFalse);
        await advance(tester, _step);
        expect(elapsed.elapsed, _step);
      } else {
        countdown.pause();
        expect(countdown.isPaused, isTrue);
        countdown.reset(duration: _step);
        await tester.pump();
        expect(countdown.remaining, _step);
        expect(countdown.isPaused, isFalse);
      }
    });

    testWidgets('$kind 同帧从 A 转交 B 时旧组件解绑不影响 B', (tester) async {
      final counter = CounterValueController();
      final countdown = CountdownController();
      final elapsed = ElapsedController();

      /// B 排在 A 前，确保 B 先绑定、A 随后解绑。
      Widget display(String id, bool attached) => switch (kind) {
            'counter' => CounterBuilder(
                key: ValueKey(id),
                to: 100,
                duration: _duration,
                controller: attached ? counter : null,
                builder: _number),
            'countdown' => CountdownBuilder(
                key: ValueKey(id),
                duration: _duration,
                precise: true,
                controller: attached ? countdown : null,
                builder: _time),
            'elapsed' => ElapsedBuilder(
                key: ValueKey(id),
                precise: true,
                controller: attached ? elapsed : null,
                builder: _time),
            _ => CardCountdown(
                key: ValueKey(id),
                to: _duration,
                controller: attached ? countdown : null),
          };

      await tester.pumpWidget(_host(Column(children: [
        display('B', false),
        display('A', true),
      ])));
      await tester.pumpWidget(_host(Column(children: [
        display('B', true),
        display('A', false),
      ])));
      if (kind == 'counter') {
        counter.pause();
        expect(counter.isPaused, isTrue);
        counter.update(to: 500);
        counter.resume();
        await tester.pump();
        await advance(tester, _duration);
        expect(counter.value, 500);
      } else if (kind == 'elapsed') {
        elapsed.pause();
        expect(elapsed.isPaused, isTrue);
        elapsed.reset();
        await tester.pump();
        await advance(tester, _step);
        expect(elapsed.elapsed, _step);
      } else {
        countdown.pause();
        expect(countdown.isPaused, isTrue);
        countdown.reset(duration: _step);
        await tester.pump();
        expect(countdown.remaining, _step);
      }
    });
  }

  testWidgets('AnimatedCounter 换 key 后 pause/resume/restart 保留绑定',
      (tester) async {
    final controller = AnimatedCounterController();
    var pauses = 0;
    var resumes = 0;
    var starts = 0;

    /// 利用生命周期回调和状态同时验证新 State 的所有权。
    Widget display(int key) => _host(AnimatedCounter(
          key: ValueKey(key),
          controller: controller,
          initialValue: 0,
          duration: _duration,
          onPause: () => pauses++,
          onResume: () => resumes++,
          onAnimationStart: () => starts++,
        ));

    await tester.pumpWidget(display(1));
    await tester.pumpWidget(display(2));
    controller.animateTo(100);
    await tester.pump();
    await advance(tester, _step);
    expect(controller.status, AnimationStatus.forward);
    controller.pause();
    expect(pauses, 1);
    final frozen = controller.status;
    await advance(tester, _duration);
    expect(controller.status, frozen);
    controller.resume();
    expect(resumes, 1);
    await tester.pump();
    await advance(tester, _duration);
    expect(controller.status, AnimationStatus.completed);
    final beforeRestart = starts;
    controller.restart();
    expect(starts, beforeRestart + 1);
    await tester.pump();
    await advance(tester, _step);
    expect(controller.status, AnimationStatus.forward);
  });

  for (final kind in ['counter', 'countdown', 'elapsed']) {
    testWidgets('$kind 只换 controller 保留任务和生命周期', (tester) async {
      final counters = [CounterValueController(), CounterValueController()];
      final countdowns = [CountdownController(), CountdownController()];
      final elapsed = [ElapsedController(), ElapsedController()];
      var ready = 0;
      var starts = 0;
      var cancels = 0;
      double displayed = 0;

      /// 仅替换 controller，所有任务参数保持不变。
      Widget display(int index) => _host(switch (kind) {
            'counter' => CounterBuilder(
                to: 100,
                duration: _duration,
                curve: Curves.linear,
                controller: counters[index],
                onReady: () => ready++,
                onStart: () => starts++,
                onCancel: () => cancels++,
                builder: (context, value, child) {
                  displayed = value;
                  return const SizedBox();
                }),
            'countdown' => CountdownBuilder(
                duration: _duration,
                precise: true,
                controller: countdowns[index],
                builder: _time,
                onReady: () => ready++,
                onStart: () => starts++,
                onCancel: () => cancels++),
            _ => ElapsedBuilder(
                precise: true,
                controller: elapsed[index],
                builder: _time,
                onReady: () => ready++,
                onStart: () => starts++,
                onCancel: () => cancels++),
          });

      await tester.pumpWidget(display(0));
      await advance(tester, _step);
      if (kind == 'countdown') countdowns[0].pause();
      final remaining = countdowns[0].remaining;
      final elapsedBefore = elapsed[0].elapsed;
      final valueBefore = displayed;
      final lifecycle = [ready, starts, cancels];
      await tester.pumpWidget(display(1));
      await tester.pump();
      expect([ready, starts, cancels], lifecycle);
      if (kind == 'countdown') {
        expect(countdowns[1].remaining, remaining);
        expect(countdowns[1].isPaused, isTrue);
        await advance(tester, _step);
        expect(countdowns[1].remaining, remaining);
      } else if (kind == 'elapsed') {
        expect(elapsed[1].elapsed, elapsedBefore);
        await advance(tester, _step);
        expect(elapsed[1].elapsed, elapsedBefore + _step);
      } else {
        expect(counters[1].value, valueBefore);
        await advance(tester, _duration - _step);
        expect(displayed, 100);
      }
    });
  }

  testWidgets('Counter 完成后 update 从显示值重启并到达 500', (tester) async {
    final c = CounterValueController();
    await tester.pumpWidget(_host(CounterBuilder(
        to: 100, duration: _step, controller: c, builder: _number)));
    await advance(tester, _step);
    expect(c.isDone, isTrue);
    c.update(to: 500, duration: _step, curve: Curves.linear);
    expect(c.isDone, isFalse);
    expect(c.value, 100);
    await tester.pump();
    await advance(tester, _step);
    expect(c.value, 500);
  });

  for (final card in [false, true]) {
    testWidgets('${card ? 'Card' : 'Countdown'} 完成后 reset 重新开始',
        (tester) async {
      final c = CountdownController();
      await tester.pumpWidget(_host(card
          ? CardCountdown(to: _step, controller: c)
          : CountdownBuilder(
              duration: _step, precise: true, controller: c, builder: _time)));
      await advance(tester, _step);
      expect(c.isDone, isTrue);
      c.reset();
      await tester.pump();
      expect(c.isDone, isFalse);
      expect(c.remaining, _step);
      c.pause();
      expect(c.isPaused, isTrue);
      c.cancel();
      c.reset(duration: _duration);
      await tester.pump();
      expect(c.remaining, _duration);
      expect(c.isPaused, isFalse);
    });
  }

  testWidgets('Elapsed cancel 后 reset 从零重新开始', (tester) async {
    final c = ElapsedController();
    await tester.pumpWidget(
        _host(ElapsedBuilder(precise: true, controller: c, builder: _time)));
    await advance(tester, _step);
    c.cancel();
    c.reset();
    await tester.pump();
    expect(c.elapsed, Duration.zero);
    await advance(tester, _step);
    expect(c.elapsed, _step);
  });

  testWidgets('Counter 只换 onComplete 后调用新回调', (tester) async {
    var oldCalls = 0;
    var newCalls = 0;
    await tester.pumpWidget(_host(CounterBuilder(
        to: 100,
        duration: _duration,
        builder: _number,
        onComplete: (_) => oldCalls++)));
    await tester.pumpWidget(_host(CounterBuilder(
        to: 100,
        duration: _duration,
        builder: _number,
        onComplete: (_) => newCalls++)));
    await advance(tester, _duration);
    expect(oldCalls, 0);
    expect(newCalls, 1);
  });
}
