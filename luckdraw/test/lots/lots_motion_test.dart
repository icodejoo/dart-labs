import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/src/lots/motion/lots_motion.dart';

import '../support/lots_fixtures.dart';

/// 验证摇动幅度、升签与展示收尾。
void main() {
  group('LotsMotion', () {
    test('shake amplitude grows during acceleration and holds while cruising',
        () {
      final m = lotsMotion();
      m.start();
      m.tick(10, 10);
      final small = m.frame.shakeDeg.abs();
      m.tick(70, 60);
      expect(m.frame.shakeDeg.abs(), greaterThan(small));
      m.tick(100, 30);
      expect(m.phase, LuckyPhase.cruising);
      m.tick(120, 20);
      expect(m.frame.shakeDeg.abs(), lessThanOrEqualTo(12));
    });
    test('deceleration damps the shake to zero and lifts the target stick', () {
      final m = lotsMotion();
      cruiseLots(m);
      m.stop(1);
      m.tick(300, 200);
      expect(m.frame.shakeDeg, 0);
      expect(m.frame.stage, LotsStage.rising);
      m.tick(350, 50);
      expect(m.frame.riseProgress, greaterThan(0));
      expect(m.frame.targetSlot, 1);
      expect(m.phase, LuckyPhase.decelerating);
    });
    test('reveal shows the target stick text then settles', () {
      final m = lotsMotion();
      cruiseLots(m);
      m.stop(1);
      m.tick(450, 350);
      expect(m.frame.stage, LotsStage.revealing);
      expect(m.frame.revealProgress, greaterThan(0));
      expect(m.phase, LuckyPhase.decelerating);
      settleLots(m);
      expect(m.frame.stage, LotsStage.done);
      expect(m.takeResult()?.prize?.label, 'fortune');
      expect(m.takeResult(), isNull);
    });
    test('shake angle is written into the reused frame without allocation', () {
      final m = lotsMotion();
      final frame = m.frame;
      cruiseLots(m);
      for (var i = 0; i < 100; i++) {
        m.tick(i * 16, 16);
        expect(identical(m.frame, frame), isTrue);
        expect(frame.shakeDeg.isFinite, isTrue);
      }
    });
    test('a 10 minute frame gap keeps the angle finite and still settles', () {
      final m = lotsMotion();
      cruiseLots(m);
      m.stop(2);
      m.tick(600000, 600000);
      expect(m.phase, LuckyPhase.settled);
      expect(m.frame.shakeDeg.isFinite, isTrue);
      expect(m.frame.riseProgress, 1);
      expect(m.frame.revealProgress, 1);
      expect(m.tick(600100, 100), LuckyMotionEvents.none);
    });
  });
}
