import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/testing.dart';
import 'package:luckdraw/wheel.dart';

import 'wheel_test_support.dart';

/// 验证类型化控制器和异步停止契约。
void main() {
  group('WheelController', () {
    test('playUntil stops with the async index after minSpinDuration',
        () async {
      final host = WheelTestHost();
      final controller = wheelTestController(host);
      final target = Completer<int?>();
      final result = controller.playUntil(() => target.future,
          minSpinDuration: const Duration(milliseconds: 160));
      host.clock.advanceFrames(5);
      target.complete(3);
      await Future<void>.value();
      expect(controller.frame.targetIndex, -1);
      controller.pause();
      host.clock.advance(const Duration(seconds: 10));
      expect(controller.frame.targetIndex, -1);
      controller.resume();
      host.clock.advanceFrames(6);
      expect(controller.frame.targetIndex, -1);
      host.clock.advanceFrames(1);
      expect(controller.frame.targetIndex, 3);
      wheelAdvanceTo(controller, host.clock, LuckyPhase.settled);
      expect((await result).index, 3);
    });
    test('playUntil with a null index cancels', () async {
      final host = WheelTestHost();
      final controller = wheelTestController(host);
      final pending = controller.playUntil(() => null);
      expect((await pending).cancelled, isTrue);
      expect(host.results.single.cancelled, isTrue);
      expect(controller.phase.value, LuckyPhase.idle);
    });
    test('playUntil propagates resolver errors after cancelling', () async {
      final host = WheelTestHost();
      final controller = wheelTestController(host);
      final error = StateError('服务端失败');
      await expectLater(
          controller.playUntil(() => throw error), throwsA(same(error)));
      expect(controller.phase.value, LuckyPhase.idle);
      expect(host.results.single.cancelled, isTrue);
    });
    test(
        'phase listenable and phaseChanges stream emit every transition in order',
        () async {
      final host = WheelTestHost();
      final controller = wheelTestController(host);
      final values = <LuckyPhase>[];
      final stream = <LuckyPhase>[];
      controller.phase.addListener(() => values.add(controller.phase.value));
      final subscription = controller.phaseChanges.listen(stream.add);
      controller.play();
      wheelAdvanceTo(controller, host.clock, LuckyPhase.cruising);
      controller.stop(2);
      wheelAdvanceTo(controller, host.clock, LuckyPhase.settled);
      expect(values, [
        LuckyPhase.accelerating,
        LuckyPhase.cruising,
        LuckyPhase.decelerating,
        LuckyPhase.settled
      ]);
      expect(stream, values);
      expect(host.phases, values);
      await subscription.cancel();
    });
    test('controller works headless with a ManualLuckyClock (#342)', () {
      final clock = ManualLuckyClock();
      final controller = WheelController(random: SequenceRandom([0.5]));
      controller.attachHeadless(clock: clock, config: wheelTestConfig());
      expect(controller.play(), isTrue);
      expect(clock.isTicking, isTrue);
      expect(controller.stopAt(2, extraRevolutions: 1), isTrue);
      wheelAdvanceTo(controller, clock, LuckyPhase.settled);
      expect(controller.lastResult!.index, 2);
      expect(clock.isTicking, isFalse);
      controller.dispose();
      clock.dispose();
    });
    test('settled result index equals the sector under the pointer (#448)', () {
      for (var target = 0; target < 6; target++) {
        final host = WheelTestHost();
        final controller = wheelTestController(host);
        controller.play();
        controller.stop(target);
        wheelAdvanceTo(controller, host.clock, LuckyPhase.settled);
        expect(controller.frame.pointerIndex, target);
        expect(controller.lastResult!.index, target);
      }
    });
    test('a controller attached to two views asserts', () {
      final host = WheelTestHost();
      final controller = wheelTestController(host);
      final another = WheelTestHost();
      expect(() => controller.attach(another), throwsStateError);
      expect(controller.isAttached, isTrue);
      another.clock.dispose();
    });
    test(
        'custom maxFrameDelta is applied before and after configuration changes',
        () {
      final host = WheelTestHost();
      final controller = wheelTestController(host,
          config: wheelTestConfig(
              motion: kWheelTestMotion.copyWith(
                  maxFrameDelta: const Duration(milliseconds: 8))));
      controller.play();
      host.clock.advanceFrames(2, step: const Duration(seconds: 1));
      final expected =
          LuckyEasings.quad.easeIn(8, 0, 20, 64) * 8 / kLuckyReferenceFrameMs;
      expect(controller.rotateDeg, expected);
      controller.configure(
          wheelTestConfig(
              motion: kWheelTestMotion.copyWith(
                  maxFrameDelta: const Duration(milliseconds: 4))),
          null);
      host.clock.advance(const Duration(seconds: 1));
      expect(
          controller.rotateDeg,
          expected +
              LuckyEasings.quad.easeIn(12, 0, 20, 64) *
                  4 /
                  kLuckyReferenceFrameMs);
    });
    test('default random construction and disposal finish pending playUntil',
        () async {
      final controller = WheelController();
      final clock = ManualLuckyClock();
      controller.attachHeadless(clock: clock, config: wheelTestConfig());
      final future = controller.playUntil(() => Completer<int?>().future);
      controller.dispose();
      expect((await future).cancelled, isTrue);
      expect(clock.isTicking, isFalse);
      clock.dispose();
    });
  });
}
