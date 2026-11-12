import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/number_wheel.dart';
import '../support/f2_lifecycle_fixtures.dart';
import '../support/number_wheel_fixtures.dart';

/// 数字盘偏移与缩放回归。
void main() {
  test('F2 number wheel queues moving offset changes until settlement', () {
    final motion = numberWheelMotion();
    cruiseNumberWheel(motion);
    motion.stop(1);
    motion.tick(120, 20);
    final config = numberWheelFixture.copyWith(
        options: numberWheelFixture.options.copyWith(offsetDegree: 120));
    expect(
        const NumberWheelGame().isStructuralChange(numberWheelFixture, config),
        isTrue);
    motion.configure(config, numberWheelLayout(config));
    expect(motion.config.options.offsetDegree,
        numberWheelFixture.options.offsetDegree);
    settleNumberWheel(motion);
    expect(motion.takeResult()!.index, 1);
    expect(motion.frame.ballPocket, 1);
    expect(motion.config.options.offsetDegree, 120);
  });
  test('F2 number wheel settled resize keeps the ball in its winning pocket',
      () {
    final motion = numberWheelMotion();
    cruiseNumberWheel(motion);
    motion.stop(1);
    settleNumberWheel(motion);
    final oldPsi = motion.frame.ballDeg - motion.frame.discDeg;
    final layout = numberWheelLayout(numberWheelFixture, const Size(400, 400));
    motion.configure(numberWheelFixture, layout);
    expect(motion.frame.ballRadius, layout.pocketRadius);
    expect(motion.frame.ballPocket, 1);
    expect(motion.frame.ballDeg - motion.frame.discDeg, oldPsi);
  });
  test('F2 number_wheel dispose freezes phase result and item callbacks', () {
    final host = F2LifecycleHost<LuckyResult<NumberWheelPocket>>();
    final controller = NumberWheelController()
      ..attach(host)
      ..configure(numberWheelFixture, numberWheelLayout());
    controller.play();
    host.clock.advanceFrames(10);
    expect(host.callbacks, greaterThan(0));
    final before = host.callbacks;
    controller.dispose();
    host.clock.advanceFrames(100);
    expect(host.callbacks, before);
    expect(host.clock.isTicking, isFalse);
    host.clock.dispose();
  });
  test(
      'F2 number wheel direct count shrink cancels an already decelerating draw',
      () {
    final m = numberWheelMotion();
    cruiseNumberWheel(m);
    m.stop(2);
    m.tick(120, 20);
    final next = numberWheelFixture
        .copyWith(pockets: [numberWheelFixture.pockets.first]);
    m.configure(next, numberWheelLayout(next));
    expect(m.phase, LuckyPhase.idle);
    expect(m.takeResult()!.cancelled, isTrue);
    expect(m.frame.targetIndex, -1);
  });
  test(
      'F2 number wheel idle start preserves angles and accelerates from idle speed',
      () {
    final m = numberWheelMotion()
      ..idleSpin()
      ..tick(20, 20);
    final ball = m.frame.ballDeg, disc = m.frame.discDeg;
    m.start();
    expect(m.frame.ballDeg, ball);
    expect(m.frame.discDeg, disc);
    m.tick(40, 20);
    final speed = (ball - m.frame.ballDeg) / (20 / (1000 / 60));
    expect(speed,
        greaterThanOrEqualTo(numberWheelFixture.options.motion.idleSpinSpeed));
    expect(speed, lessThan(numberWheelFixture.options.motion.speed));
  });
}
