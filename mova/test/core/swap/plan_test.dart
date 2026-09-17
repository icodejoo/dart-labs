import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/swap/plan.dart';
import 'package:mova/src/core/swap/trigger.dart';
import 'package:mova/src/core/swap/warm.dart';

void main() {
  group('MovaWarmPlan', () {
    test('all-defaults plan reproduces 0.4.0 behaviour (no overrides, no hold)', () {
      const plan = MovaWarmPlan();
      expect(plan.trigger, isNull);
      expect(plan.policy, isNull);
      expect(plan.pauseWhenReady, isFalse);
    });

    test('every field can be set and read back', () {
      final policy = MovaBufferWarm(timeout: const Duration(seconds: 3));
      final plan = MovaWarmPlan(
        trigger: const MovaEagerWarm(),
        policy: policy,
        pauseWhenReady: true,
      );
      expect(plan.trigger, isA<MovaEagerWarm>());
      expect(plan.policy, same(policy));
      expect(plan.pauseWhenReady, isTrue);
    });

    test('is const-constructible, so it can be a const default argument', () {
      const plan = MovaWarmPlan(trigger: MovaEagerWarm(), pauseWhenReady: true);
      expect(identical(plan, const MovaWarmPlan(trigger: MovaEagerWarm(), pauseWhenReady: true)), isTrue);
    });

    test('trigger and policy are independent: setting one leaves the other null', () {
      const triggerOnly = MovaWarmPlan(trigger: MovaEagerWarm());
      expect(triggerOnly.trigger, isNotNull);
      expect(triggerOnly.policy, isNull);

      final policyOnly = MovaWarmPlan(policy: MovaBufferWarm());
      expect(policyOnly.trigger, isNull);
      expect(policyOnly.policy, isNotNull);
    });
  });
}
