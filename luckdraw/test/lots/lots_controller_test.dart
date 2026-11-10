import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/src/lots/control/lots_controller.dart';
import 'package:luckdraw/testing.dart';

import '../support/lots_fixtures.dart';

/// 验证选签和取消、异步命令。
void main() {
  group('LotsController', () {
    late LotsController c;
    late ManualLuckyClock clock;
    setUp(() {
      c = LotsController();
      clock = ManualLuckyClock();
      c.attachHeadless(clock: clock, config: lotsFixture, layout: lotsLayout());
    });
    tearDown(() {
      c.dispose();
      clock.dispose();
    });
    test('stop() without index uses the picker', () {
      expect(c.stop(), isFalse);
      c.play();
      expect(c.stop(), isTrue);
      clock.advanceFrames(80);
      expect(c.lastResult?.index, 1);
    });
    test('negative index cancels and sticks return to rest', () {
      c.play();
      clock.advanceFrames(10);
      expect(c.stop(-3), isTrue);
      expect(c.phase.value, LuckyPhase.idle);
      expect(c.frame.shakeDeg, 0);
      expect(c.frame.riseProgress, 0);
      expect(c.lastResult?.cancelled, isTrue);
    });
    test('playUntil waits for the async index', () async {
      final server = Completer<int?>();
      final result = c.playUntil(() => server.future);
      clock.advanceFrames(10);
      expect(c.lastResult, isNull);
      server.complete(2);
      await Future<void>.delayed(Duration.zero);
      clock.advanceFrames(80);
      expect((await result).index, 2);
    });
  });
}
