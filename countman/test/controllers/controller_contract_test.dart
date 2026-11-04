// 展示组件内部绑定协议的契约测试需要直接调用内部接口。
// ignore_for_file: invalid_use_of_internal_member

import 'package:countman/countman.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 各类动画共用的测试时长。
const _duration = Duration(seconds: 10);

/// 计数任务的初始目标。
const _initialTarget = 100.0;

/// 控制器更新后的目标值。
const _updatedTarget = 500.0;

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
    await tester.pump();
    wall = wall.add(duration);
    monotonic += duration;
    await tester.pump(duration);
  }

  test('三个 controller 的 attach/detach 归属及旧式无参解绑兼容', () {
    final counterPlugin = Counter();
    final countdownPlugin = Countdown();
    final elapsedPlugin = Elapsed();
    final context = CountmanContext(requestFrame: () {});
    counterPlugin.onAttach(context);
    countdownPlugin.onAttach(context);
    elapsedPlugin.onAttach(context);
    final counter = CounterValueController();
    final countdown = CountdownController();
    final elapsed = ElapsedController();
    final oldCounter = counterPlugin.add(CounterOptions(to: _initialTarget));
    final newCounter = counterPlugin.add(CounterOptions(to: 200));
    final oldCountdown =
        countdownPlugin.add(CountdownOptions(duration: _duration));
    final newCountdown =
        countdownPlugin.add(CountdownOptions(duration: _duration));
    final oldElapsed = elapsedPlugin.add(ElapsedOptions());
    final newElapsed = elapsedPlugin.add(ElapsedOptions());
    counter.attach(oldCounter);
    counter.attach(newCounter);
    countdown.attach(oldCountdown);
    countdown.attach(newCountdown);
    elapsed.attach(oldElapsed);
    elapsed.attach(newElapsed);
    counter.detach(oldCounter);
    countdown.detach(oldCountdown);
    elapsed.detach(oldElapsed);
    counter.pause();
    countdown.pause();
    elapsed.pause();
    expect(newCounter.isPaused, isTrue);
    expect(newCountdown.isPaused, isTrue);
    expect(newElapsed.isPaused, isTrue);
    expect(oldCounter.isPaused, isFalse);
    expect(oldCountdown.isPaused, isFalse);
    expect(oldElapsed.isPaused, isFalse);
    counter.detach();
    countdown.detach();
    elapsed.detach();
    counter.resume();
    countdown.resume();
    elapsed.resume();
    expect(newCounter.isPaused, isTrue);
    expect(newCountdown.isPaused, isTrue);
    expect(newElapsed.isPaused, isTrue);
    expect(counter.isDone, isTrue);
    expect(countdown.isDone, isTrue);
  });

  test('relaunch 仅用于已结束任务，按原参数转发且解绑后清除', () {
    final counterPlugin = Counter();
    final countdownPlugin = Countdown();
    final elapsedPlugin = Elapsed();
    final context = CountmanContext(requestFrame: () {});
    counterPlugin.onAttach(context);
    countdownPlugin.onAttach(context);
    elapsedPlugin.onAttach(context);
    final counter = CounterValueController();
    final countdown = CountdownController();
    final elapsed = ElapsedController();
    final ch = counterPlugin.add(CounterOptions(to: _initialTarget));
    final dh = countdownPlugin.add(CountdownOptions(duration: _duration));
    final eh = elapsedPlugin.add(ElapsedOptions());
    var counterCalls = 0;
    var countdownCalls = 0;
    var elapsedCalls = 0;
    counter.attach(ch, relaunch: ({required to, duration, curve}) {
      counterCalls++;
      expect(to, _updatedTarget);
      expect(duration, _step);
      expect(curve, Curves.linear);
    });
    countdown.attach(dh, relaunch: ({duration}) {
      countdownCalls++;
      expect(duration, _step);
    });
    elapsed.attach(eh, relaunch: () => elapsedCalls++);
    counter.update(to: _updatedTarget, duration: _step, curve: Curves.linear);
    countdown.reset(duration: _step);
    elapsed.reset();
    expect([counterCalls, countdownCalls, elapsedCalls], [0, 0, 0]);
    expect(eh.isDone, isFalse);
    ch.cancel();
    dh.cancel();
    eh.cancel();
    expect(eh.isDone, isTrue);
    counter.update(to: _updatedTarget, duration: _step, curve: Curves.linear);
    countdown.reset(duration: _step);
    elapsed.reset();
    expect([counterCalls, countdownCalls, elapsedCalls], [1, 1, 1]);
    counter.detach(ch);
    countdown.detach(dh);
    elapsed.detach(eh);
    counter.update(to: _updatedTarget);
    countdown.reset();
    elapsed.reset();
    expect([counterCalls, countdownCalls, elapsedCalls], [1, 1, 1]);
  });

  for (final kind in ['counter', 'countdown', 'elapsed', 'card']) {
    testWidgets('$kind 换 key 后新绑定仍可控制', (tester) async {
      final counter = CounterValueController();
      final countdown = CountdownController();
      final elapsed = ElapsedController();

      /// 构造不同 key 的同类展示组件。
      Widget display(int key) => switch (kind) {
            'counter' => CounterBuilder(
                key: ValueKey(key),
                to: _initialTarget,
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
        counter.update(to: _updatedTarget);
        await tester.pump();
        await advance(tester, _duration);
        expect(counter.value, _updatedTarget);
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
                to: _initialTarget,
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
        counter.update(to: _updatedTarget);
        counter.resume();
        await tester.pump();
        await advance(tester, _duration);
        expect(counter.value, _updatedTarget);
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
    controller.animateTo(_initialTarget);
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
                to: _initialTarget,
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
        expect(displayed, _initialTarget);
      }
    });
  }

  testWidgets('Counter 完成后 update 从显示值重启并到达 500', (tester) async {
    final c = CounterValueController();
    await tester.pumpWidget(_host(CounterBuilder(
        to: _initialTarget, duration: _step, controller: c, builder: _number)));
    await advance(tester, _step);
    expect(c.isDone, isTrue);
    c.update(to: _updatedTarget, duration: _step, curve: Curves.linear);
    expect(c.isDone, isFalse);
    expect(c.value, _initialTarget);
    await tester.pump();
    await advance(tester, _step);
    expect(c.value, _updatedTarget);
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

  for (final skipEntrance in [false, true]) {
    testWidgets('animateOnce 显式 update 仍播放，跳过入场=$skipEntrance', (tester) async {
      final c = CounterValueController();
      var ready = 0;
      var starts = 0;
      var cancels = 0;

      /// 保留 provider 的注册表，重新挂载同一业务标识。
      Widget display(bool visible, int key) => _host(CounterProvider(
            animateOnce: true,
            child: visible
                ? CounterBuilder(
                    key: ValueKey(key),
                    onceId: 'once',
                    to: _initialTarget,
                    duration: _step,
                    controller: c,
                    builder: _number,
                    onReady: () => ready++,
                    onStart: () => starts++,
                    onCancel: () => cancels++,
                  )
                : const SizedBox(),
          ));

      await tester.pumpWidget(display(true, 1));
      await advance(tester, _step);
      if (skipEntrance) {
        await tester.pumpWidget(display(false, 1));
        final lifecycle = [ready, starts, cancels];
        await tester.pumpWidget(display(true, 2));
        expect([ready, starts, cancels], lifecycle);
      }
      expect(c.value, _initialTarget);
      expect(c.isDone, isTrue);
      c.update(to: _updatedTarget, duration: _duration, curve: Curves.linear);
      await advance(tester, _step);
      expect(c.value, closeTo(180, 0.001));
      expect(c.isAnimating, isTrue);
      await advance(tester, _duration - _step);
      expect(c.value, _updatedTarget);
    });
  }

  testWidgets('Card 只换 controller 保留剩余时间和暂停状态', (tester) async {
    final old = CountdownController();
    final current = CountdownController();
    await tester
        .pumpWidget(_host(CardCountdown(to: _duration, controller: old)));
    await advance(tester, _step);
    old.pause();
    final remaining = old.remaining;
    await tester
        .pumpWidget(_host(CardCountdown(to: _duration, controller: current)));
    expect(current.remaining, remaining);
    expect(current.isPaused, isTrue);
    await advance(tester, _step);
    expect(current.remaining, remaining);
    old.reset();
    expect(current.isPaused, isTrue);
  });

  testWidgets('Card 重启立即同步小时列和卡片模型', (tester) async {
    final c = CountdownController();
    await tester.pumpWidget(_host(CardCountdown(to: _step, controller: c)));
    await advance(tester, _step);
    c.reset(duration: const Duration(hours: 2));
    await tester.pump();
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((widget) => widget.painter)
        .whereType<FlipCardPainter>()
        .single;
    expect(painter.model.committed, [0, 2, 0, 0, 0, 0]);
    expect(painter.model.target, isNull);
    expect(painter.geom.unitLabelCenters, hasLength(3));
    expect(c.remaining, const Duration(hours: 2));
    c.cancel();
    c.reset(duration: _step);
    await tester.pump();
    final nextPainter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((widget) => widget.painter)
        .whereType<FlipCardPainter>()
        .single;
    expect(nextPainter.model.committed, [0, 0, 0, 2]);
    expect(nextPainter.geom.unitLabelCenters, hasLength(2));
  });

  for (final card in [false, true]) {
    testWidgets('${card ? 'Card' : 'Countdown'} relaunch 时长优先级及当前截止时间',
        (tester) async {
      final c = CountdownController();
      final deadline = wall.add(_duration);
      await tester.pumpWidget(_host(card
          ? CardCountdown(to: deadline, controller: c)
          : CountdownBuilder(to: deadline, controller: c, builder: _time)));
      await advance(tester, _step);
      c.cancel();
      c.reset();
      await tester.pump();
      expect(c.remaining, _duration - _step);
      c.cancel();
      await tester.pumpWidget(_host(card
          ? CardCountdown(to: deadline, duration: _step, controller: c)
          : CountdownBuilder(
              to: deadline, duration: _step, controller: c, builder: _time)));
      c.cancel();
      c.reset();
      await tester.pump();
      // CardCountdown 的 duration 是翻牌动画时长，不参与重启时长的回退。
      expect(c.remaining, card ? _duration - _step : _step);
      c.cancel();
      c.reset(duration: _duration);
      await tester.pump();
      expect(c.remaining, _duration);
    });
  }

  testWidgets('animateOnce 跳过入场绑定控制器时不误触发分组回调', (tester) async {
    var ready = 0;
    var drained = 0;
    final c = CounterValueController();
    Widget page(bool show) => _host(CounterProvider(
          animateOnce: true,
          onGroupReady: () => ready++,
          onAllComplete: () => drained++,
          child: show
              ? TextCounter(
                  key: const ValueKey('row-1'),
                  to: _initialTarget,
                  duration: _step,
                  controller: c)
              : const SizedBox(),
        ));
    await tester.pumpWidget(page(true));
    await advance(tester, _step);
    await tester.pump();
    expect((ready, drained), (1, 1));
    // 移出再移入：同一 id 跳过入场，只绑定控制器，不应产生任何分组事件。
    await tester.pumpWidget(page(false));
    await tester.pumpWidget(page(true));
    await tester.pump();
    expect((ready, drained), (1, 1));
    expect(c.value, _initialTarget);
    // 显式命令仍能从显示值重启动画。
    c.update(to: _updatedTarget);
    await advance(tester, _step);
    await tester.pump();
    expect(c.value, _updatedTarget);
  });

  testWidgets('Counter 只换 onComplete 后调用新回调', (tester) async {
    var oldCalls = 0;
    var newCalls = 0;
    await tester.pumpWidget(_host(CounterBuilder(
        to: _initialTarget,
        duration: _duration,
        builder: _number,
        onComplete: (_) => oldCalls++)));
    await tester.pumpWidget(_host(CounterBuilder(
        to: _initialTarget,
        duration: _duration,
        builder: _number,
        onComplete: (_) => newCalls++)));
    await advance(tester, _duration);
    expect(oldCalls, 0);
    expect(newCalls, 1);
  });
}
