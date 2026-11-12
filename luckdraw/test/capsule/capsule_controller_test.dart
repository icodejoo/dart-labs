import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/capsule.dart';
import 'package:luckdraw/testing.dart';

import '../support/capsule_fixtures.dart';

/// 核对类型化命令与异步选奖。
void main() {
  late CapsuleController c;
  late ManualLuckyClock clock;
  setUp(() {
    clock = ManualLuckyClock();
    c = CapsuleController()
      ..attachHeadless(
          clock: clock, config: capsuleConfig, layout: capsuleLayout());
  });
  tearDown(() {
    c.dispose();
    clock.dispose();
  });
  group('CapsuleController', () {
    test('stop() without index uses the picker', () {
      expect(c.play(), isTrue);
      expect(c.stop(), isTrue);
      for (var i = 0; i < 300; i++) {
        clock.advance(const Duration(milliseconds: 20));
      }
      expect(c.lastResult?.index, isIn([0, 1]));
      expect(c.phase.value, LuckyPhase.settled);
    });
    test('negative index cancels and capsules return to rest', () {
      expect(c.play(), isTrue);
      clock.advance(const Duration(milliseconds: 100));
      expect(c.stop(-1), isTrue);
      expect(c.lastResult?.cancelled, isTrue);
      expect(c.phase.value, LuckyPhase.idle);
      for (var i = 0; i < c.frame.x.length; i++) {
        expect(c.frame.x[i], capsuleLayout().rest[i].dx);
        expect(c.frame.y[i], capsuleLayout().rest[i].dy);
      }
      expect(c.stop(), isFalse);
    });
    test('playUntil waits for the async index', () async {
      final index = Completer<int?>();
      final future = c.playUntil(() => index.future,
          minSpinDuration: const Duration(milliseconds: 1200));
      for (var i = 0; i < 50; i++) {
        clock.advance(const Duration(milliseconds: 20));
      }
      expect(c.phase.value, LuckyPhase.cruising);
      index.complete(1);
      await Future<void>.delayed(Duration.zero);
      expect(c.phase.value, LuckyPhase.cruising);
      for (var i = 0; i < 250; i++) {
        clock.advance(const Duration(milliseconds: 20));
      }
      expect((await future).index, 1);
      expect(c.lastResult?.prize, capsuleConfig.prizes[1]);
    });
  });
  test(
      'CapsuleController edges > stopAt ignores settled and playUntil null cancels',
      () async {
    expect(c.stopAt(1), isFalse);
    final future = c.playUntil(() => null);
    expect((await future).cancelled, isTrue);
    expect(c.stopAt(0), isFalse);
  });
  test(
      'CapsuleController edges > queued config changes the next picker without changing this result',
      () {
    c.play();
    c.stop(0);
    clock.advanceFrames(60, step: const Duration(milliseconds: 20));
    expect(c.phase.value, LuckyPhase.decelerating);
    final next = capsuleConfig
        .copyWith(prizes: [capsuleConfig.prizes[1].copyWith(weight: 0)]);
    c.configure(next, capsuleLayout(next), structural: true);
    clock.advanceFrames(300, step: const Duration(milliseconds: 20));
    expect(c.lastResult?.prize, capsuleConfig.prizes.first);
    expect(c.phase.value, LuckyPhase.settled);
    expect(c.play(), isTrue);
    expect(c.stop(), isTrue);
    expect(c.lastResult?.cancelled, isTrue);
    expect(c.frame.x.length, next.capsulesPerPrize);
  });
}
