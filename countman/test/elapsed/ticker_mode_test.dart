// ignore_for_file: invalid_use_of_internal_member

import 'package:countman/countman.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/manual_clock.dart';

/// 保持 State，模拟路由的 TickerMode 可见性变化。
Widget _wrap(bool enabled, Widget child) => MaterialApp(
  home: TickerMode(enabled: enabled, child: child),
);

void main() {
  late ManualCountmanClock clock;
  setUp(() => clock = installManualClock());
  tearDown(Countman.destroy);

  testWidgets('无上限静音后 idle，迁移保留静音，恢复显示真实已过时间', (t) async {
    final first = Elapsed(name: 'first', interval: 0);
    final second = Elapsed(name: 'second', interval: 0);
    var updates = 0;
    Widget child(Elapsed p) => ElapsedBuilder(
      plugin: p,
      onTick: (_) => updates++,
      builder: (_, p, __) => Text('${p.inMilliseconds}'),
    );
    await t.pumpWidget(_wrap(false, child(first)));
    expect(first.task(0)!.muted, isTrue);
    await t.pump();
    expect(updates, 0);
    expect(Countman.isRunning, isFalse);
    expect(Countman.isSleeping, isFalse);
    clock.advance(const Duration(milliseconds: 1500));
    await t.pump(const Duration(milliseconds: 1500));
    await t.pumpWidget(_wrap(false, child(second)));
    await t.pump();
    expect(second.task(0)!.muted, isTrue);
    expect(first.activeTaskCount, 0);
    expect(updates, 0);
    expect(Countman.isRunning, isFalse);
    await t.pumpWidget(_wrap(true, child(second)));
    await t.pump();
    expect(find.text('1500'), findsOneWidget);
    expect(updates, 1);
  });

  testWidgets('静音 limit 与阈值仍按时触发，终值保留且不发 onTick', (t) async {
    var updates = 0;
    var thresholds = 0;
    var completes = 0;
    var pauses = 0;
    var resumes = 0;
    final controller = ElapsedController();
    final child = ElapsedBuilder(
      precise: true,
      limit: const Duration(seconds: 3),
      threshold: const Duration(seconds: 1),
      onTick: (_) => updates++,
      onThreshold: () => thresholds++,
      onComplete: () => completes++,
      onPause: () => pauses++,
      onResume: () => resumes++,
      controller: controller,
      builder: (_, p, __) => Text('${p.inSeconds}'),
    );
    await t.pumpWidget(_wrap(false, child));
    await t.pump();
    expect(Countman.isSleeping, isTrue);
    clock.advance(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
    expect(thresholds, 1);
    expect(completes, 0);
    expect(updates, 0);
    clock.advance(const Duration(seconds: 2));
    await t.pump(const Duration(seconds: 2));
    expect(completes, 1);
    expect(updates, 0);
    expect(controller.runState, CountmanRunState.completed);
    await t.pumpWidget(_wrap(true, child));
    await t.pump();
    expect(find.text('3'), findsOneWidget);
    expect(pauses, 0);
    expect(resumes, 0);
    expect(completes, 1);
  });
}
