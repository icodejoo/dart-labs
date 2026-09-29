import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/report/stall.dart';

void main() {
  final t0 = DateTime(2026, 1, 1);

  group('MovaEdgeStall', () {
    test('rising edge produces no stall; only the falling edge does', () {
      final policy = MovaEdgeStall(minStall: Duration.zero);
      expect(policy.onStall(true, t0), isNull);
      final stall = policy.onStall(false, t0.add(const Duration(milliseconds: 500)));
      expect(stall, isNotNull);
      expect(stall!.duration, const Duration(milliseconds: 500));
    });

    test('a stall shorter than minStall is swallowed as noise', () {
      final policy = MovaEdgeStall(minStall: const Duration(milliseconds: 200));
      policy.onStall(true, t0);
      final stall = policy.onStall(false, t0.add(const Duration(milliseconds: 50)));
      expect(stall, isNull);
    });

    test('a stall at or above minStall is reported', () {
      final policy = MovaEdgeStall(minStall: const Duration(milliseconds: 200));
      policy.onStall(true, t0);
      final stall = policy.onStall(false, t0.add(const Duration(milliseconds: 200)));
      expect(stall, isNotNull);
    });

    test('two consecutive stalls have independent, non-accumulating durations', () {
      final policy = MovaEdgeStall(minStall: Duration.zero);
      policy.onStall(true, t0);
      final first = policy.onStall(false, t0.add(const Duration(milliseconds: 100)));
      policy.onStall(true, t0.add(const Duration(seconds: 1)));
      final second = policy.onStall(
        false,
        t0.add(const Duration(seconds: 1, milliseconds: 400)),
      );
      expect(first!.duration, const Duration(milliseconds: 100));
      expect(second!.duration, const Duration(milliseconds: 400));
    });

    test('reset() drops the rising-edge memory', () {
      final policy = MovaEdgeStall(minStall: Duration.zero);
      policy.onStall(true, t0);
      policy.reset();
      // Falling edge with no matching rising edge after reset must not fire.
      final stall = policy.onStall(false, t0.add(const Duration(seconds: 1)));
      expect(stall, isNull);
    });

    test('repeated true observations without an intervening false are idempotent', () {
      final policy = MovaEdgeStall(minStall: Duration.zero);
      expect(policy.onStall(true, t0), isNull);
      expect(policy.onStall(true, t0.add(const Duration(milliseconds: 10))), isNull);
      final stall = policy.onStall(false, t0.add(const Duration(milliseconds: 500)));
      // Duration measured from the *first* rising edge, not the repeated one.
      expect(stall!.duration, const Duration(milliseconds: 500));
    });
  });
}
