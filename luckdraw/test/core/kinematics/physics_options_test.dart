import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/src/core/kinematics/physics_options.dart';

/// 验证物理模式参数的默认值、副本、相等性与范围校验。
void main() {
  test('物理参数默认值与设计一致且默认通过校验', () {
    const p = LuckyPhysics();
    expect(p.gravity, 9);
    expect(p.restitution, 0.3);
    expect(p.friction, 0.25);
    expect(p.linearDamping, 0.2);
    expect(p.stirArms, 2);
    expect(p.stirRatio, 0.3);
    expect(p.dropIn, isTrue);
    expect(p.guideLead, const Duration(milliseconds: 350));
    expect(p.seed, 1);
    expect(p.maxBodies, 128);
    expect(p.reduceMotion, LuckyPhysicsReduceMotion.system);
    p.validate();
  });

  test('物理参数副本逐字段替换且未指定字段保持原值', () {
    const base = LuckyPhysics();
    expect(base.copyWith(), base);
    expect(base.copyWith(gravity: 1).gravity, 1);
    expect(base.copyWith(restitution: 0.9).restitution, 0.9);
    expect(base.copyWith(friction: 0.5).friction, 0.5);
    expect(base.copyWith(linearDamping: 0.7).linearDamping, 0.7);
    expect(base.copyWith(stirArms: 3).stirArms, 3);
    expect(base.copyWith(stirRatio: 0.6).stirRatio, 0.6);
    expect(base.copyWith(dropIn: false).dropIn, isFalse);
    expect(base.copyWith(guideLead: Duration.zero).guideLead, Duration.zero);
    expect(base.copyWith(seed: 9).seed, 9);
    expect(base.copyWith(maxBodies: 8).maxBodies, 8);
    expect(
        base
            .copyWith(reduceMotion: LuckyPhysicsReduceMotion.always)
            .reduceMotion,
        LuckyPhysicsReduceMotion.always);
  });

  test('物理参数相等性与哈希覆盖每个字段', () {
    const base = LuckyPhysics();
    final variants = [
      base.copyWith(gravity: 1),
      base.copyWith(restitution: 0.9),
      base.copyWith(friction: 0.5),
      base.copyWith(linearDamping: 0.7),
      base.copyWith(stirArms: 3),
      base.copyWith(stirRatio: 0.6),
      base.copyWith(dropIn: false),
      base.copyWith(guideLead: Duration.zero),
      base.copyWith(seed: 9),
      base.copyWith(maxBodies: 8),
      base.copyWith(reduceMotion: LuckyPhysicsReduceMotion.never),
    ];
    for (final v in variants) {
      expect(v, isNot(base));
      expect(v.hashCode, isNot(base.hashCode));
    }
    expect(const LuckyPhysics(), const LuckyPhysics());
    expect(const LuckyPhysics().hashCode, const LuckyPhysics().hashCode);
    expect(base == Object(), isFalse);
  });

  test('物理参数越界时校验抛出 ArgumentError', () {
    final bad = [
      const LuckyPhysics(gravity: -1),
      const LuckyPhysics(gravity: double.nan),
      const LuckyPhysics(friction: -0.1),
      const LuckyPhysics(linearDamping: double.infinity),
      const LuckyPhysics(stirRatio: -1),
      const LuckyPhysics(restitution: 1.1),
      const LuckyPhysics(restitution: -0.1),
      const LuckyPhysics(restitution: double.nan),
      const LuckyPhysics(stirArms: -1),
      const LuckyPhysics(guideLead: Duration(milliseconds: -1)),
      const LuckyPhysics(maxBodies: 0),
    ];
    for (final p in bad) {
      expect(p.validate, throwsArgumentError, reason: '$p');
    }
    const LuckyPhysics(stirArms: 0, restitution: 1, guideLead: Duration.zero)
        .validate();
  });
}
