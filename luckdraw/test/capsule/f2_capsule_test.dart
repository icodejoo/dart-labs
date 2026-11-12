import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/capsule.dart';
import 'package:luckdraw/src/capsule/motion/capsule_motion.dart';
import '../support/capsule_fixtures.dart';
import '../support/f2_lifecycle_fixtures.dart';

/// 扭蛋机结算后配置回归。
void main() {
  test('F2 capsule settled shrink resets removed capsule and prize references',
      () {
    final motion = CapsuleMotion()
      ..configure(capsuleConfig, capsuleLayout())
      ..start();
    for (var i = 0; i < 60; i++) {
      motion.tick(i * 20, 20);
    }
    motion.requestStop(1);
    for (var i = 60; i < 600 && motion.phase != LuckyPhase.settled; i++) {
      motion.tick(i * 20, 20);
    }
    expect(motion.phase, LuckyPhase.settled);
    expect(motion.frame.targetPrize, 1);
    final config = capsuleConfig
        .copyWith(prizes: [capsuleConfig.prizes.first], capsulesPerPrize: 1);
    motion.configure(config, capsuleLayout(config));
    expect(motion.frame.x, hasLength(1));
    expect(motion.frame.droppedCapsule, -1);
    expect(motion.frame.targetPrize, -1);
    expect(motion.phase, LuckyPhase.idle);
    expect(motion.start(), isTrue);
  });
  test('F2 capsule dispose freezes phase result and item callbacks', () {
    final host = F2LifecycleHost<LuckyResult<CapsulePrize>>();
    final controller = CapsuleController()
      ..attach(host)
      ..configure(capsuleConfig, capsuleLayout());
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
  test('F2 capsule clearing all bodies before target selection cancels safely',
      () {
    final m = CapsuleMotion()
      ..configure(capsuleConfig, capsuleLayout())
      ..start();
    final next = capsuleConfig.copyWith(prizes: []);
    m.configure(next, capsuleLayout(next));
    expect(m.phase, LuckyPhase.idle);
    expect(m.takeResult()!.cancelled, isTrue);
  });
  test(
      'F2 capsule direct configure normalizes pending targets and cancels removed drops',
      () {
    final m = CapsuleMotion()
      ..configure(capsuleConfig, capsuleLayout())
      ..start();
    for (var i = 0; i < 60; i++) {
      m.tick(i * 20, 20);
    }
    m.requestStop(1);
    final next = capsuleConfig
        .copyWith(prizes: [capsuleConfig.prizes.first], capsulesPerPrize: 1);
    m.configure(next, capsuleLayout(next));
    m.tick(1200, 20);
    expect(m.frame.targetPrize, 0);
    expect(m.frame.droppedCapsule, 0);
    final empty = capsuleConfig.copyWith(prizes: []);
    m.configure(empty, capsuleLayout(empty));
    expect(m.phase, LuckyPhase.idle);
    expect(m.takeResult()!.cancelled, isTrue);
  });
}
