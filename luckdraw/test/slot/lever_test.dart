import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/slot.dart';
import 'package:luckdraw/src/slot/lever/lever_painter.dart';

import '../support/slot_fixtures.dart';

/// 提供有界方向环境。
Widget _host(Widget child) => Directionality(
    textDirection: TextDirection.ltr,
    child:
        MediaQuery(data: const MediaQueryData(), child: Center(child: child)));

/// 从拉杆头按下，越过手势竞争阈值后精确拖动。
Future<void> _drag(WidgetTester tester, double dy,
    {bool cancel = false}) async {
  final gesture =
      await tester.startGesture(tester.getCenter(find.bySemanticsLabel('拉杆')));
  await gesture.moveBy(const Offset(0, 20));
  await gesture.moveBy(Offset(0, dy));
  if (cancel) {
    await gesture.cancel();
  } else {
    await gesture.up();
  }
  await tester.pump();
}

/// 拉杆阈值、点按、运动状态与资源生命周期。
void main() {
  group('LuckyLeverSlotMachine', () {
    testWidgets('pulling past the threshold plays and calls onPull',
        (tester) async {
      final c = SlotController();
      addTearDown(c.dispose);
      var pulls = 0;
      await tester.pumpWidget(_host(LuckyLeverSlotMachine(
          config: slotTestConfig,
          controller: c,
          width: 300,
          height: 180,
          onPull: () => pulls++)));
      await _drag(tester, 90);
      expect(pulls, 1);
      expect(c.phase.value.isMoving, isTrue);
      final config =
          tester.widget<LuckySlotMachine>(find.byType(LuckySlotMachine)).config;
      expect(
          config.reels.map((r) => r.stopDelay.inMilliseconds), [0, 300, 600]);
      c.stop(1);
      await tester.pumpAndSettle();
      expect(c.lastResult!.indices, [1, 1, 1]);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('releasing below the threshold springs back without playing',
        (tester) async {
      final c = SlotController();
      addTearDown(c.dispose);
      var pulls = 0;
      await tester.pumpWidget(_host(LuckyLeverSlotMachine(
          config: slotTestConfig,
          controller: c,
          width: 300,
          height: 180,
          onPull: () => pulls++)));
      await _drag(tester, 30);
      await tester.pumpAndSettle();
      expect(pulls, 0);
      expect(c.phase.value, LuckyPhase.idle);
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<LeverPainter>()
          .single;
      expect(painter.progress.value, 0);
    });
    testWidgets(
        'tapping the lever knob is an accessible alternative to dragging',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final c = SlotController();
      addTearDown(c.dispose);
      var pulls = 0;
      await tester.pumpWidget(_host(LuckyLeverSlotMachine(
          config: slotTestConfig,
          controller: c,
          width: 300,
          height: 180,
          onPull: () => pulls++)));
      final knob = find.bySemanticsLabel('拉杆');
      expect(tester.getSemantics(knob),
          matchesSemantics(label: '拉杆', isButton: true, hasTapAction: true));
      await tester.tap(knob);
      expect(pulls, 1);
      expect(c.phase.value, LuckyPhase.accelerating);
      c.cancel();
      semantics.dispose();
    });
    testWidgets('pulling while moving calls onPull but does not play again',
        (tester) async {
      final c = SlotController();
      addTearDown(c.dispose);
      var pulls = 0;
      var starts = 0;
      await tester.pumpWidget(_host(LuckyLeverSlotMachine(
          config: slotTestConfig,
          controller: c,
          width: 300,
          height: 180,
          onPull: () => pulls++,
          onPhaseChanged: (phase) {
            if (phase == LuckyPhase.accelerating) starts++;
          })));
      c.play();
      await tester.pump();
      await tester.pump(slotTestStep * 3);
      await _drag(tester, 90);
      expect(pulls, 1);
      expect(starts, 1);
      expect(c.phase.value, LuckyPhase.cruising);
      c.cancel();
      await tester.pumpAndSettle();
    });
    testWidgets('lever spring-back animation stops its ticker when done',
        (tester) async {
      await tester.pumpWidget(_host(const LuckyLeverSlotMachine(
          config: slotTestConfig,
          width: 300,
          height: 180,
          lever: LeverOptions(autoPlay: false))));
      await _drag(tester, 90);
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<LeverPainter>()
          .single;
      expect(painter.progress.value, 0);
      final cancelled = await tester
          .startGesture(tester.getCenter(find.bySemanticsLabel('拉杆')));
      await cancelled.moveBy(const Offset(0, 1));
      await cancelled.cancel();
      await tester.pumpAndSettle();
      expect(painter.progress.value, 0);
      await _drag(tester, 90, cancel: true);
      await tester.pumpAndSettle();
      expect(painter.progress.value, 0);
      await _drag(tester, 90);
      await tester.pumpWidget(const SizedBox());
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });
    testWidgets(
        'reconfiguration preserves external ownership and resets winning highlights',
        (tester) async {
      final c = SlotController();
      final other = SlotController();
      addTearDown(c.dispose);
      addTearDown(other.dispose);
      final results = <SlotResult>[];
      final phases = <LuckyPhase>[];
      final config = slotTestConfig.copyWith(reels: [
        const SlotReel(),
        const SlotReel(stopDelay: Duration(milliseconds: 16)),
        const SlotReel()
      ], paylines: [
        const SlotPayline([0, 0, 0])
      ]);
      await tester.pumpWidget(_host(LuckyLeverSlotMachine(
          config: config,
          controller: c,
          width: 300,
          height: 180,
          lever: const LeverOptions(staggerStop: Duration.zero),
          onEnd: results.add,
          onPhaseChanged: phases.add)));
      final inner =
          tester.widget<LuckySlotMachine>(find.byType(LuckySlotMachine));
      expect(inner.config.reels[1].stopDelay.inMilliseconds, 16);
      c.play();
      c.stop(1);
      await tester.pumpAndSettle();
      expect(results.single.winningPaylines, [0]);
      expect(phases, contains(LuckyPhase.settled));
      c.play();
      await tester.pump();
      expect(
          tester
              .widget<LuckySlotMachine>(find.byType(LuckySlotMachine))
              .layers
              .whereType<SlotPaylineLayer>()
              .single
              .result,
          isNull);
      c.cancel();
      await tester.pumpWidget(_host(LuckyLeverSlotMachine(
          config: config,
          controller: other,
          lever: const LeverOptions(side: LeverSide.left))));
      expect(tester.getCenter(find.bySemanticsLabel('拉杆')).dx,
          lessThan(tester.getCenter(find.byType(LuckySlotMachine)).dx));
      await tester.pumpWidget(_host(LuckyLeverSlotMachine(
          config: config, lever: const LeverOptions(side: LeverSide.left))));
      await tester.pumpWidget(
          _host(LuckyLeverSlotMachine(config: config, controller: other)));
      await tester.pumpWidget(const SizedBox());
      expect(c.phase.value, LuckyPhase.idle);
      expect(other.phase.value, LuckyPhase.idle);
      expect(tester.takeException(), isNull);
    });
    test('options copy equality and painter invalidation follow all fields',
        () {
      const options = LeverOptions();
      final same = options.copyWith();
      expect(same, options);
      expect(same.hashCode, options.hashCode);
      final changed = options.copyWith(
          side: LeverSide.left,
          widthFactor: 0.3,
          pullThreshold: 0.5,
          springBack: Duration.zero,
          autoPlay: false,
          staggerStop: Duration.zero,
          knobColor: const Color(0xFF111111),
          shaftColor: const Color(0xFF222222));
      expect(changed, isNot(options));
      expect(changed.hashCode, isNot(options.hashCode));
      const progress = AlwaysStoppedAnimation<double>(0.5);
      final painter = LeverPainter(options, progress);
      expect(painter.shouldRepaint(LeverPainter(options, progress)), isFalse);
      expect(painter.shouldRepaint(LeverPainter(changed, progress)), isTrue);
    });
  });
}
