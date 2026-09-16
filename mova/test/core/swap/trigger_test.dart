import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/swap/trigger.dart';

void main() {
  group('MovaLeadWarm', () {
    const t = MovaLeadWarm(lead: Duration(seconds: 2), minDuration: Duration(seconds: 5));

    test('remaining greater than lead does not warm yet', () {
      expect(t.shouldWarm(const MovaWarmCue(remaining: Duration(seconds: 3), total: Duration(seconds: 10))),
          isFalse);
    });

    test('remaining exactly equal to lead warms (boundary inclusive)', () {
      expect(t.shouldWarm(const MovaWarmCue(remaining: Duration(seconds: 2), total: Duration(seconds: 10))),
          isTrue);
    });

    test('remaining less than lead warms', () {
      expect(t.shouldWarm(const MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10))),
          isTrue);
    });

    test('remaining at or below zero never warms (too late)', () {
      expect(t.shouldWarm(const MovaWarmCue(remaining: Duration.zero, total: Duration(seconds: 10))), isFalse);
      expect(
          t.shouldWarm(const MovaWarmCue(remaining: Duration(seconds: -1), total: Duration(seconds: 10))),
          isFalse);
    });

    test('a clip shorter than minDuration never warms', () {
      expect(t.shouldWarm(const MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 3))),
          isFalse);
    });

    test('unknown total does not block warming, judged from remaining alone', () {
      expect(t.shouldWarm(const MovaWarmCue(remaining: Duration(seconds: 1))), isTrue);
    });

    test('unknown remaining never warms', () {
      expect(t.shouldWarm(const MovaWarmCue(total: Duration(seconds: 10))), isFalse);
    });

    test('instance holds no state across calls', () {
      expect(t.shouldWarm(const MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10))),
          isTrue);
      expect(t.shouldWarm(const MovaWarmCue(remaining: Duration(seconds: 3), total: Duration(seconds: 10))),
          isFalse);
      expect(t.shouldWarm(const MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10))),
          isTrue);
    });
  });

  group('MovaEagerWarm', () {
    test('always returns true, including for an empty cue', () {
      const t = MovaEagerWarm();
      expect(t.shouldWarm(const MovaWarmCue()), isTrue);
      expect(t.shouldWarm(const MovaWarmCue(remaining: Duration(seconds: 100))), isTrue);
    });
  });
}
