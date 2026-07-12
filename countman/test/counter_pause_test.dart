import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:countman/countman.dart';

// Tests for the Counter pause/resume + status API (review "found-but-skipped"
// fix #1: a paused counter task is skipped by the tick loop and lets the shared
// ticker idle, then resumes cleanly from its frozen value).
//
// Counter 暂停/恢复 + 状态 API 的测试（review "发现但跳过" 修复 #1：暂停任务被
// tick 循环跳过、让共享 ticker idle，恢复时从冻结值干净继续）。
void main() {
  testWidgets('CounterValueController pause freezes value, resume continues to completion',
      (tester) async {
    final ctrl = CounterValueController();
    final values = <double>[];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TextCounter(
          to: 100,
          duration: const Duration(seconds: 1),
          controller: ctrl,
          onUpdate: values.add,
        ),
      ),
    ));
    await tester.pump(); // initial render
    await tester.pump(const Duration(milliseconds: 300)); // advance ~30%

    expect(ctrl.isAnimating, isTrue);
    expect(ctrl.isPaused, isFalse);
    expect(ctrl.isDone, isFalse);

    // Pause → value freezes: no further onUpdate fires across pumps.
    ctrl.pause();
    expect(ctrl.isPaused, isTrue);
    expect(ctrl.isAnimating, isFalse);
    final countAtPause = values.length;
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(values.length, countAtPause, reason: 'paused counter must not emit updates');

    // Resume → advances again and completes at the target.
    ctrl.resume();
    expect(ctrl.isPaused, isFalse);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    expect(values.last, closeTo(100, 0.001));
    expect(ctrl.isDone, isTrue);
  });

  testWidgets('pause/resume are safe no-ops before attach / after done', (tester) async {
    final ctrl = CounterValueController();
    // Not attached yet — status getters report sensible defaults, calls no-op.
    expect(ctrl.isDone, isTrue);
    expect(ctrl.isAnimating, isFalse);
    ctrl.pause();
    ctrl.resume();
    expect(ctrl.isPaused, isFalse);
  });
}
