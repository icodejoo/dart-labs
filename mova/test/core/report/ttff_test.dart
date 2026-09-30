import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/report/ttff.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 0, 0, 0);

  group('MovaTtffTracker', () {
    test('autoPlay: false never arms — no landing is ever reported', () {
      final tracker = MovaTtffTracker();
      tracker.arm(t0, autoPlay: false);
      expect(tracker.isArmed, isFalse);
      expect(tracker.onBuffering(false, t0.add(const Duration(milliseconds: 500))), isNull);
      expect(tracker.landed, isFalse);
    });

    test('lands exactly once on the first buffering->false edge', () {
      final tracker = MovaTtffTracker();
      tracker.arm(t0, autoPlay: true);
      expect(tracker.onBuffering(true, t0.add(const Duration(milliseconds: 50))), isNull);
      final landed = tracker.onBuffering(false, t0.add(const Duration(milliseconds: 300)));
      expect(landed, const Duration(milliseconds: 300));
      expect(tracker.landed, isTrue);
      // A later buffering flap (rebuffer) must not report a second landing.
      expect(tracker.onBuffering(true, t0.add(const Duration(seconds: 1))), isNull);
      expect(tracker.onBuffering(false, t0.add(const Duration(seconds: 2))), isNull);
    });

    test('ttffMs equals the injected time delta', () {
      final tracker = MovaTtffTracker();
      tracker.arm(t0, autoPlay: true);
      tracker.onBuffering(true, t0.add(const Duration(milliseconds: 10)));
      final landed = tracker.onBuffering(false, t0.add(const Duration(milliseconds: 733)));
      expect(landed!.inMilliseconds, 733);
    });

    test('initial buffering=false (no preceding true) is not a landing', () {
      final tracker = MovaTtffTracker();
      tracker.arm(t0, autoPlay: true);
      expect(tracker.onBuffering(false, t0.add(const Duration(milliseconds: 40))), isNull);
      expect(tracker.landed, isFalse);
    });

    test('a fresh arm forgets a previously seen buffering=true', () {
      final tracker = MovaTtffTracker();
      tracker.arm(t0, autoPlay: true);
      tracker.onBuffering(true, t0);
      tracker.arm(t0, autoPlay: true);
      expect(tracker.onBuffering(false, t0.add(const Duration(milliseconds: 40))), isNull);
    });

    test('onProgress needs two increasing samples > 0, then never lands again', () {
      final tracker = MovaTtffTracker();
      tracker.arm(t0, autoPlay: true);
      expect(tracker.onProgress(Duration.zero, t0.add(const Duration(milliseconds: 20))), isNull);
      expect(tracker.onProgress(Duration.zero, t0.add(const Duration(milliseconds: 40))), isNull);
      expect(tracker.onProgress(const Duration(milliseconds: 30), t0.add(const Duration(milliseconds: 60))),
          const Duration(milliseconds: 60));
      expect(tracker.onProgress(const Duration(seconds: 1), t0.add(const Duration(seconds: 2))), isNull);
    });

    test('onProgress ignores a lone stale position left over from the previous media', () {
      final tracker = MovaTtffTracker();
      tracker.arm(t0, autoPlay: true);
      expect(tracker.onProgress(const Duration(seconds: 8), t0.add(const Duration(milliseconds: 5))), isNull);
      // 真实新源从 0 起步，比残留值小——不能落地。
      expect(tracker.onProgress(const Duration(milliseconds: 100), t0.add(const Duration(milliseconds: 300))), isNull);
      expect(tracker.landed, isFalse);
    });

    test('wasArmed is true after arming with autoPlay, even before landing', () {
      final tracker = MovaTtffTracker();
      tracker.arm(t0, autoPlay: true);
      expect(tracker.wasArmed, isTrue);
      expect(tracker.landed, isFalse);
    });

    test('onNativeRestart lands the same as onBuffering, just via a different signal', () {
      final tracker = MovaTtffTracker();
      tracker.arm(t0, autoPlay: true);
      final landed = tracker.onNativeRestart(t0.add(const Duration(milliseconds: 240)));
      expect(landed, const Duration(milliseconds: 240));
      expect(tracker.landed, isTrue);
      // A later restart (post-seek) must not report a second landing.
      expect(tracker.onNativeRestart(t0.add(const Duration(seconds: 5))), isNull);
    });

    test('whichever signal lands first wins — the other becomes a no-op', () {
      final tracker = MovaTtffTracker();
      tracker.arm(t0, autoPlay: true);
      // Native restart lands first.
      expect(tracker.onNativeRestart(t0.add(const Duration(milliseconds: 100))), isNotNull);
      // The buffering-edge fallback fires slightly later for the same frame —
      // must not double-report.
      expect(tracker.onBuffering(false, t0.add(const Duration(milliseconds: 110))), isNull);
    });

    test('autoPlay: false means onNativeRestart never lands either', () {
      final tracker = MovaTtffTracker();
      tracker.arm(t0, autoPlay: false);
      expect(tracker.onNativeRestart(t0.add(const Duration(milliseconds: 500))), isNull);
      expect(tracker.landed, isFalse);
    });

    test('reset() clears armed/landed state so a new arm starts fresh', () {
      final tracker = MovaTtffTracker();
      tracker.arm(t0, autoPlay: true);
      tracker.onBuffering(true, t0.add(const Duration(milliseconds: 20)));
      tracker.onBuffering(false, t0.add(const Duration(milliseconds: 100)));
      expect(tracker.landed, isTrue);
      tracker.reset();
      expect(tracker.wasArmed, isFalse);
      expect(tracker.landed, isFalse);
      tracker.arm(t0, autoPlay: true);
      expect(tracker.isArmed, isTrue);
    });
  });
}
