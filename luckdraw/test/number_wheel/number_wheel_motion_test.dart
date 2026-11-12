import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';

import '../support/number_wheel_fixtures.dart';

/// 验证相对角停止和落袋曲线。
void main() {
  group('NumberWheelMotion', () {
    test('disc and ball spin in opposite directions while cruising', () {
      final m = numberWheelMotion();
      cruiseNumberWheel(m);
      final disc = m.frame.discDeg, ball = m.frame.ballDeg;
      m.tick(120, 20);
      expect(m.frame.discDeg, greaterThan(disc));
      expect(m.frame.ballDeg, lessThan(ball));
    });
    test(
        'ball relative angle uses the monotonic stop solver and never reverses',
        () {
      final m = numberWheelMotion();
      cruiseNumberWheel(m);
      m.stop(1);
      var relative = m.frame.ballDeg - m.frame.discDeg;
      for (var i = 0; i < 20; i++) {
        m.tick(i * 10, 10);
        final next = m.frame.ballDeg - m.frame.discDeg;
        expect(next, lessThanOrEqualTo(relative + 1e-9));
        relative = next;
      }
      expect(m.phase, LuckyPhase.settled);
    });
    test(
        'ball drops from the track to the pocket radius in the last phase of deceleration',
        () {
      final m = numberWheelMotion();
      cruiseNumberWheel(m);
      m.stop(1);
      m.tick(200, 100);
      expect(m.frame.ballRadius, numberWheelLayout().trackRadius);
      m.tick(260, 60);
      expect(m.frame.ballRadius, lessThan(numberWheelLayout().trackRadius));
      settleNumberWheel(m);
      expect(m.frame.ballRadius, numberWheelLayout().pocketRadius);
    });
    test('bounce is damped and deterministic', () {
      final a = numberWheelMotion(), b = numberWheelMotion();
      cruiseNumberWheel(a);
      cruiseNumberWheel(b);
      a.stop(2);
      b.stop(2);
      for (var i = 0; i < 20; i++) {
        a.tick(i * 10, 10);
        b.tick(i * 10, 10);
        expect(a.frame.ballRadius, b.frame.ballRadius);
      }
      expect(a.frame.ballRadius, numberWheelLayout().pocketRadius);
    });
    test('settled ball sits in the target pocket and moves with the disc', () {
      final m = numberWheelMotion();
      cruiseNumberWheel(m);
      m.stop(2);
      settleNumberWheel(m);
      expect((m.frame.ballDeg - m.frame.discDeg) % 360, closeTo(240, 1e-9));
      final relative = m.frame.ballDeg - m.frame.discDeg;
      expect(m.tick(1000, 100), LuckyMotionEvents.none);
      expect(m.frame.ballDeg - m.frame.discDeg, relative);
    });
    test('result number is the label of the target pocket', () {
      final m = numberWheelMotion();
      cruiseNumberWheel(m);
      m.stop(4);
      settleNumberWheel(m);
      expect(m.takeResult()?.prize?.number, 20);
      expect(m.takeResult(), isNull);
    });
    test('a 10 minute frame gap keeps angles finite and still settles', () {
      final m = numberWheelMotion();
      cruiseNumberWheel(m);
      m.stop(1);
      m.tick(600000, 600000);
      expect(m.phase, LuckyPhase.settled);
      expect(m.frame.ballDeg.isFinite && m.frame.discDeg.isFinite, isTrue);
    });
  });
}
