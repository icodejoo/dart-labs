// ignore_for_file: invalid_use_of_internal_member

import 'package:countman/countman.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/manual_clock.dart';

/// 保留 State，只切换 TickerMode 或插件配置。
Widget _wrap(bool enabled, Widget child) => MaterialApp(
  home: TickerMode(enabled: enabled, child: child),
);

void main() {
  late ManualCountmanClock clock;
  setUp(() => clock = installManualClock());
  tearDown(() {
    Countman.muteWhenHidden = true;
    Countman.destroy();
  });

  testWidgets('方案 A：恢复时跳到真实推进位置，隐藏迁移保留动画时间轴', (t) async {
    final first = Counter(name: 'first');
    final second = Counter(name: 'second');
    final controller = CounterValueController();
    var updates = 0;
    var completes = 0;
    Widget child(Counter p) => CounterBuilder(
      to: 100,
      curve: Curves.linear,
      plugin: p,
      controller: controller,
      onUpdate: (_) => updates++,
      onComplete: (_) => completes++,
      builder: (_, v, __) => Text(v.toStringAsFixed(0)),
    );
    await t.pumpWidget(_wrap(true, child(first)));
    await t.pump();
    clock.advance(const Duration(milliseconds: 200));
    await t.pump(const Duration(milliseconds: 200));
    expect(controller.value, closeTo(20, 0.1));
    await t.pumpWidget(_wrap(false, child(first)));
    await t.pump();
    final before = updates;
    clock.advance(const Duration(milliseconds: 500));
    await t.pump(const Duration(milliseconds: 500));
    expect(updates, before);
    expect(Countman.isSleeping, isTrue);
    await t.pumpWidget(_wrap(false, child(second)));
    await t.pump();
    expect(first.activeTaskCount, 0);
    expect(second.taskById(0)!.muted, isTrue);
    await t.pumpWidget(_wrap(true, child(second)));
    await t.pump();
    expect(controller.value, closeTo(70, 0.1));
    expect(controller.runState, CountmanRunState.running);
    clock.advance(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 300));
    expect(completes, 1);
    expect(controller.value, 100);
  });

  testWidgets('隐藏新任务只休眠到终点，不投递 onUpdate，完成恰好一次', (t) async {
    final plugin = Counter(name: 'hidden');
    var updates = 0;
    var starts = 0;
    var completes = 0;
    final child = CounterBuilder(
      to: 100,
      plugin: plugin,
      onUpdate: (_) => updates++,
      onStart: () => starts++,
      onComplete: (_) => completes++,
      builder: (_, v, __) => Text('$v'),
    );
    await t.pumpWidget(_wrap(false, child));
    expect(plugin.taskById(0)!.muted, isTrue);
    await t.pump();
    expect(starts, 1);
    expect(Countman.isSleeping, isTrue);
    expect(t.binding.transientCallbackCount, 0);
    clock.advance(const Duration(seconds: 2));
    await t.pump(const Duration(seconds: 2));
    expect(completes, 1);
    expect(updates, 0);
    expect(Countman.isRunning, isFalse);
    await t.pumpWidget(_wrap(true, child));
    await t.pump();
    expect(find.text('100.0'), findsOneWidget);
    expect(completes, 1);
  });

  testWidgets('隐藏与用户暂停叠加，取消静音不恢复，暂停时长不计入动画', (t) async {
    final controller = CounterValueController();
    final child = CounterBuilder(
      to: 100,
      curve: Curves.linear,
      controller: controller,
      builder: (_, v, __) => Text('$v'),
    );
    await t.pumpWidget(_wrap(false, child));
    await t.pump();
    clock.advance(const Duration(milliseconds: 300));
    controller.pause();
    await t.pump();
    clock.advance(const Duration(seconds: 2));
    await t.pump(const Duration(seconds: 2));
    await t.pumpWidget(_wrap(true, child));
    await t.pump();
    expect(controller.isPaused, isTrue);
    expect(controller.runState, CountmanRunState.paused);
    controller.resume();
    await t.pump();
    expect(controller.value, closeTo(30, 0.1));
    expect(controller.isDone, isFalse);
  });

  testWidgets('AnimatedCounter 两条路径与回弹/变色任务全部休眠并落到终值', (t) async {
    final plugin = Counter(name: 'animated');
    var completes = 0;
    final child = Column(
      children: [
        AnimatedCounter(
          value: 123,
          plugin: plugin,
          timeline: const CounterTimeline(bounceOvershoot: 0.1),
          style: const AnimatedCounterStyle(increasingColor: Colors.red),
          onAnimationEnd: () => completes++,
        ),
        AnimatedCounterBuilder(
          value: 456,
          plugin: plugin,
          digitBuilder: (_, d, s) => Text('$d', style: s),
          onAnimationEnd: () => completes++,
        ),
      ],
    );
    await t.pumpWidget(_wrap(false, child));
    await t.pump();
    await t.pump();
    expect(Countman.isSleeping, isTrue);
    expect(t.binding.transientCallbackCount, 0);
    clock.advance(const Duration(seconds: 5));
    await t.pump(const Duration(seconds: 5));
    expect(completes, 2);
    expect(plugin.activeTaskCount, 0);
    await t.pumpWidget(_wrap(true, child));
    await t.pump();
    expect(completes, 2);
    expect(t.takeException(), isNull);
  });

  testWidgets('AnimatedCounter 隐藏期间暂停保留真实进度，恢复可见性不恢复播放', (t) async {
    final plugin = Counter(name: 'paused-animated');
    final controller = AnimatedCounterController(initialValue: 100);
    var completes = 0;
    final child = AnimatedCounter(
      plugin: plugin,
      controller: controller,
      timeline: const CounterTimeline(duration: Duration(seconds: 1)),
      onAnimationEnd: () => completes++,
    );
    await t.pumpWidget(_wrap(false, child));
    await t.pump();
    await t.pump();
    clock.advance(const Duration(milliseconds: 300));
    controller.pause();
    await t.pump();
    clock.advance(const Duration(seconds: 2));
    await t.pump(const Duration(seconds: 2));
    await t.pumpWidget(_wrap(true, child));
    await t.pump();
    expect(controller.runState, CountmanRunState.paused);
    expect(completes, 0);
    controller.resume();
    expect(plugin.taskById(1)!.from, closeTo(0.3, 0.001));
    await t.pump();
    clock.advance(const Duration(milliseconds: 700));
    await t.pump(const Duration(milliseconds: 700));
    expect(completes, 1);
    expect(controller.runState, CountmanRunState.completed);
  });
}
