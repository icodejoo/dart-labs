import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/luckdraw.dart';

/// 验证默认配置、时长钳制和值语义。
void main() {
  group('LuckyMotionOptions', () {
    test('options differing only in speed are unequal in both directions', () {
      const original = LuckyMotionOptions();
      final changed = original.copyWith(speed: original.speed + 1);
      expect(original == changed, isFalse);
      expect(changed == original, isFalse);
      expect(original.copyWith(), original);
      expect(original.copyWith().hashCode, original.hashCode);
    });
    test(
        'options differing only in accelerationTime are unequal in both directions',
        () {
      const original = LuckyMotionOptions();
      final changed = original.copyWith(
          accelerationTime:
              original.accelerationTime + const Duration(milliseconds: 1));
      expect(original == changed, isFalse);
      expect(changed == original, isFalse);
      expect(original.copyWith(), original);
      expect(original.copyWith().hashCode, original.hashCode);
    });
    test(
        'options differing only in maxFrameDelta are unequal in both directions',
        () {
      const original = LuckyMotionOptions();
      final changed = original.copyWith(
          maxFrameDelta:
              original.maxFrameDelta + const Duration(milliseconds: 1));
      expect(original == changed, isFalse);
      expect(changed == original, isFalse);
      expect(original.copyWith(), original);
      expect(original.copyWith().hashCode, original.hashCode);
    });
    test(
        'options differing only in idleSpinSpeed are unequal in both directions',
        () {
      const original = LuckyMotionOptions();
      final changed =
          original.copyWith(idleSpinSpeed: original.idleSpinSpeed + 1);
      expect(original == changed, isFalse);
      expect(changed == original, isFalse);
      expect(original.copyWith(), original);
      expect(original.copyWith().hashCode, original.hashCode);
    });
    test('defaults match upstream defaultConfig', () {
      const options = LuckyMotionOptions();
      expect(options.speed, 20);
      expect(options.accelerationMs, 2500);
      expect(options.decelerationMs, 2500);
      expect(options.accelerationEasing, same(LuckyEasings.quad));
      expect(options.decelerationEasing, same(LuckyEasings.quad));
      expect(options.timebase, LuckyTimebase.time);
      expect(options.stopSolver, isA<MonotonicStopSolver>());
      expect(options.maxFrameDelta, const Duration(milliseconds: 100));
      expect(options.idleSpinSpeed, 2);
      expect(LuckyTimebase.values, [LuckyTimebase.time, LuckyTimebase.frame]);
    });
    test('asserts positive durations and runtime treats non-positive as 1ms',
        () {
      // const 构造不得调用 Duration 比较；配置断言归 T0.6 的 motion.configure。
      const zero = LuckyMotionOptions(
          accelerationTime: Duration.zero,
          decelerationTime: Duration(microseconds: -1));
      expect(zero.accelerationMs, 1);
      expect(zero.decelerationMs, 1);
      const fractional = LuckyMotionOptions(
          accelerationTime: Duration(microseconds: 1500),
          decelerationTime: Duration(microseconds: 2500));
      expect(fractional.accelerationMs, 1.5);
      expect(fractional.decelerationMs, 2.5);
    });
    test('equality and copyWith are value based', () {
      const original = LuckyMotionOptions();
      final copy = original.copyWith();
      expect(copy, original);
      expect(copy.hashCode, original.hashCode);
      final changed = original.copyWith(
          speed: 30,
          accelerationTime: const Duration(seconds: 1),
          decelerationTime: const Duration(seconds: 2),
          accelerationEasing: LuckyEasings.cubic,
          decelerationEasing: LuckyEasings.sine,
          timebase: LuckyTimebase.frame,
          stopSolver: const UpstreamStopSolver(),
          maxFrameDelta: const Duration(milliseconds: 50),
          idleSpinSpeed: 3);
      expect(changed, isNot(original));
      expect(changed.speed, 30);
      expect(changed.accelerationMs, 1000);
      expect(changed.decelerationMs, 2000);
      expect(changed.accelerationEasing, same(LuckyEasings.cubic));
      expect(changed.decelerationEasing, same(LuckyEasings.sine));
      expect(changed.timebase, LuckyTimebase.frame);
      expect(changed.stopSolver, isA<UpstreamStopSolver>());
      expect(changed.maxFrameDelta, const Duration(milliseconds: 50));
      expect(changed.idleSpinSpeed, 3);
      expect(changed.copyWith(), changed);
      expect(changed.copyWith().hashCode, changed.hashCode);
    });
  });
}
