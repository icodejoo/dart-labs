import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/luckdraw.dart';

/// 验证全部枚举值，避免遗漏状态。
void main() {
  group('LuckyPhase', () {
    test('isMoving is true only for moving phases', () {
      for (final phase in LuckyPhase.values) {
        expect(
            phase.isMoving,
            const {
              LuckyPhase.idleSpinning,
              LuckyPhase.accelerating,
              LuckyPhase.cruising,
              LuckyPhase.decelerating
            }.contains(phase));
      }
    });
    test('canPlay is true for idle settled and idleSpinning', () {
      for (final phase in LuckyPhase.values) {
        final expected = const {
          LuckyPhase.idle,
          LuckyPhase.settled,
          LuckyPhase.idleSpinning
        }.contains(phase);
        expect(phase.canPlay, expected);
        // ignore: deprecated_member_use_from_same_package
        expect(phase.acceptsStart, expected);
      }
    });
    test('canStop is true only for accelerating and cruising', () {
      for (final phase in LuckyPhase.values) {
        expect(
            phase.canStop,
            const {LuckyPhase.accelerating, LuckyPhase.cruising}
                .contains(phase));
      }
    });
    test('canCancel covers moving phases except decelerating', () {
      for (final phase in LuckyPhase.values) {
        expect(
            phase.canCancel,
            const {
              LuckyPhase.idleSpinning,
              LuckyPhase.accelerating,
              LuckyPhase.cruising
            }.contains(phase));
      }
    });
  });
}