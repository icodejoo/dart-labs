// ignore_for_file: invalid_use_of_internal_member

import 'package:countman/countman.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/manual_clock.dart';

/// 保持子组件位置不变，只切换祖先的静音信号。
Widget _wrap(bool enabled, Widget child) => MaterialApp(
  home: TickerMode(enabled: enabled, child: child),
);

/// 获取卡片画笔以检查模型和动画进度。
FlipCardPainter _painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((w) => w.painter)
    .whereType<FlipCardPainter>()
    .single;

void main() {
  late ManualCountmanClock clock;

  setUp(() => clock = installManualClock());
  tearDown(() {
    Countman.muteWhenHidden = true;
    Countman.destroy();
  });

  testWidgets('隐藏新任务不投递更新，precise 也只为阈值与完成休眠', (t) async {
    final plugin = Countdown(name: 'hidden', interval: 0);
    final controller = CountdownController();
    var updates = 0;
    var completes = 0;
    var thresholds = 0;
    var starts = 0;
    var pauses = 0;
    var resumes = 0;
    final child = Column(
      children: [
        CountdownBuilder(
          duration: const Duration(seconds: 5),
          plugin: plugin,
          controller: controller,
          onTick: (_) => updates++,
          onStart: () => starts++,
          onPause: () => pauses++,
          onResume: () => resumes++,
          threshold: const Duration(seconds: 3),
          onThreshold: () => thresholds++,
          onComplete: () => completes++,
          builder: (_, p, __) => Text('builder:${p.inSeconds}'),
        ),
        TextCountdown(
          to: const Duration(seconds: 5),
          plugin: plugin,
          onTick: (_) => updates++,
          onComplete: () => completes++,
        ),
      ],
    );
    await t.pumpWidget(_wrap(false, child));
    expect(plugin.task(0)!.muted, isTrue); // 入队即静音。
    await t.pump();
    expect(starts, 1);
    expect(updates, 0);
    expect(controller.runState, CountmanRunState.running);
    expect(Countman.isRunning, isTrue);
    expect(Countman.isSleeping, isTrue);
    expect(t.binding.transientCallbackCount, 0);
    clock.advance(const Duration(seconds: 2));
    await t.pump(const Duration(seconds: 2));
    expect(thresholds, 1);
    expect(updates, 0);
    expect(Countman.isSleeping, isTrue);
    clock.advance(const Duration(seconds: 3));
    await t.pump(const Duration(seconds: 3));
    expect(completes, 2);
    expect(updates, 0);
    expect(Countman.isRunning, isFalse);
    expect(controller.runState, CountmanRunState.completed);
    await t.pumpWidget(_wrap(true, child));
    await t.pump();
    expect(find.text('builder:0'), findsOneWidget);
    expect(completes, 2);
    expect(starts, 1);
    expect(pauses, 0);
    expect(resumes, 0);
  });

  testWidgets('恢复强制刷新同一显示桶，迁移后仍静音并保留暂停', (t) async {
    final first = Countdown(name: 'first', interval: 10000);
    final second = Countdown(name: 'second', interval: 10000);
    final controller = CountdownController();
    var updates = 0;
    var pauses = 0;
    var resumes = 0;
    Widget child(Countdown p) => CountdownBuilder(
      duration: const Duration(seconds: 9),
      plugin: p,
      controller: controller,
      onTick: (_) => updates++,
      onPause: () => pauses++,
      onResume: () => resumes++,
      builder: (_, p, __) => Text('${p.inMilliseconds}'),
    );
    await t.pumpWidget(_wrap(true, child(first)));
    await t.pump();
    await t.pumpWidget(_wrap(false, child(first)));
    await t.pump();
    final before = updates;
    clock.advance(const Duration(milliseconds: 200));
    await t.pump(const Duration(milliseconds: 200));
    await t.pumpWidget(_wrap(false, child(second)));
    await t.pump();
    expect(first.activeTaskCount, 0);
    expect(second.task(0)!.muted, isTrue);
    expect(updates, before);
    await t.pumpWidget(_wrap(true, child(second)));
    await t.pump();
    expect(find.text('8800'), findsOneWidget);
    expect(updates, before + 1);
    expect(controller.runState, CountmanRunState.running);
    expect(pauses, 0);
    expect(resumes, 0);
    controller.pause();
    await t.pumpWidget(_wrap(false, child(second)));
    clock.advance(const Duration(seconds: 1));
    await t.pumpWidget(_wrap(true, child(second)));
    await t.pump();
    expect(controller.isPaused, isTrue);
    expect(controller.runState, CountmanRunState.paused);
    expect(pauses, 1);
    expect(resumes, 0);
  });

  testWidgets('关闭全局开关保持隐藏时逐帧更新', (t) async {
    Countman.muteWhenHidden = false;
    var updates = 0;
    var counters = 0;
    var elapsed = 0;
    var cards = 0;
    await t.pumpWidget(
      _wrap(
        false,
        Column(
          children: [
            TextCountdown(
              to: const Duration(seconds: 5),
              precise: true,
              onTick: (_) => updates++,
            ),
            CounterBuilder(
              to: 10,
              onUpdate: (_) => counters++,
              builder: (_, __, ___) => const SizedBox(),
            ),
            ElapsedBuilder(
              precise: true,
              onTick: (_) => elapsed++,
              builder: (_, __, ___) => const SizedBox(),
            ),
            CardCountdown(
              to: const Duration(seconds: 5),
              onTick: (_) => cards++,
            ),
          ],
        ),
      ),
    );
    await t.pump();
    final before = updates;
    final counterBefore = counters;
    final elapsedBefore = elapsed;
    final cardBefore = cards;
    clock.advance(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 100));
    expect(updates, greaterThan(before));
    expect(counters, greaterThan(counterBefore));
    expect(elapsed, greaterThan(elapsedBefore));
    expect(cards, greaterThan(cardBefore));
    expect(Countman.isSleeping, isFalse);
    expect(t.binding.transientCallbackCount, greaterThan(0));
  });

  testWidgets('被路由覆盖自动静音，返回恢复显示且不暂停逻辑时间', (t) async {
    final navigator = GlobalKey<NavigatorState>();
    var updates = 0;
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: TextCountdown(
          to: const Duration(seconds: 5),
          precise: true,
          onTick: (_) => updates++,
          formatter: (p) => '${p.inMilliseconds}',
        ),
      ),
    );
    await t.pump();
    navigator.currentState!.push<void>(
      MaterialPageRoute(builder: (_) => const SizedBox()),
    );
    await t.pumpAndSettle();
    final before = updates;
    clock.advance(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
    expect(updates, before);
    expect(Countman.isSleeping, isTrue);
    navigator.currentState!.pop();
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.pump();
    expect(find.text('4000'), findsOneWidget);
    expect(updates, greaterThan(before));
  });

  testWidgets('重新挂到另一 notifier 后只跟随当前祖先，静音中销毁解除监听', (t) async {
    final key = GlobalKey();
    var updates = 0;
    final child = ElapsedBuilder(
      key: key,
      precise: true,
      onTick: (_) => updates++,
      builder: (_, __, ___) => const SizedBox(),
    );
    Widget tree(bool moved, bool oldEnabled, bool enabled) => MaterialApp(
      home: Column(
        children: [
          TickerMode(
            enabled: oldEnabled,
            child: moved ? const SizedBox() : child,
          ),
          TickerMode(enabled: enabled, child: moved ? child : const SizedBox()),
        ],
      ),
    );
    await t.pumpWidget(tree(false, false, true));
    await t.pump();
    expect(updates, 0);
    await t.pumpWidget(tree(true, false, true));
    await t.pump();
    expect(updates, 1);
    await t.pumpWidget(tree(true, false, false));
    await t.pump();
    final before = updates;
    await t.pumpWidget(tree(true, true, false));
    await t.pump();
    expect(updates, before);
    expect(Countman.isRunning, isFalse);
    await t.pumpWidget(const SizedBox());
    await t.pump();
    expect(t.takeException(), isNull);
  });

  testWidgets('卡片隐藏清零半程翻牌，恢复立即落定当前模型，静音销毁无泄漏', (t) async {
    var updates = 0;
    final child = CardCountdown(
      to: const Duration(seconds: 10, milliseconds: 500),
      onTick: (_) => updates++,
      style: const CardCountdownStyle(transitionType: CountdownType.slide),
    );
    await t.pumpWidget(_wrap(true, child));
    await t.pump();
    clock.advance(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
    clock.advance(const Duration(milliseconds: 150));
    await t.pump(const Duration(milliseconds: 150));
    expect(_painter(t).model.target, isNotNull);
    expect(_painter(t).controller.value, greaterThan(0));
    await t.pumpWidget(_wrap(false, child));
    await t.pump();
    expect(_painter(t).controller.value, 0);
    expect(_painter(t).model.target, isNull);
    final before = updates;
    clock.advance(const Duration(seconds: 3));
    await t.pump(const Duration(seconds: 3));
    expect(updates, before);
    expect(Countman.isSleeping, isTrue);
    await t.pumpWidget(_wrap(true, child));
    await t.pump();
    expect(_painter(t).model.committed.last, 6);
    expect(_painter(t).controller.value, 0);
    expect(_painter(t).model.target, isNull);
    await t.pumpWidget(_wrap(false, child));
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump();
    expect(Countman.isRunning, isFalse);
    expect(t.takeException(), isNull);
  });
}
