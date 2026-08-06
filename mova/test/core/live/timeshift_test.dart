import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/live/timeshift.dart';
import 'package:mova/src/core/options/live_config.dart';
import 'package:mova/src/core/state/state.dart';

/// Ten seconds — the product's default "close enough to the edge" threshold.
///
/// 十秒——产品默认的"已足够接近边缘"阈值。
const _edge = Duration(seconds: 10);

void main() {
  group('resolveWindow', () {
    test('falls back to the kernel-reported duration', () {
      const s = MovaState(duration: Duration(minutes: 5));
      expect(resolveWindow(s, const MovaLiveConfig()), const Duration(minutes: 5));
    });

    test('an explicit dvrWindow wins over the duration', () {
      const s = MovaState(duration: Duration(minutes: 5));
      const cfg = MovaLiveConfig(dvrWindow: Duration(minutes: 2));
      expect(resolveWindow(s, cfg), const Duration(minutes: 2));
    });

    test('an injected windowResolver wins over everything', () {
      const s = MovaState(duration: Duration(minutes: 5));
      final cfg = MovaLiveConfig(
        dvrWindow: const Duration(minutes: 2),
        windowResolver: (_) => const Duration(hours: 1),
      );
      expect(resolveWindow(s, cfg), const Duration(hours: 1));
    });

    test('an unknown duration resolves to zero, not to a negative window', () {
      expect(resolveWindow(const MovaState(), const MovaLiveConfig()), Duration.zero);
    });
  });

  group('behindOf', () {
    test('inside the edge threshold counts as at the edge (null)', () {
      expect(behindOf(const Duration(seconds: 55), const Duration(seconds: 60), _edge),
          isNull);
      expect(behindOf(const Duration(seconds: 50), const Duration(seconds: 60), _edge),
          isNull, reason: 'exactly at the threshold is still the edge');
    });

    test('beyond the threshold reports how far behind', () {
      expect(behindOf(const Duration(seconds: 20), const Duration(seconds: 60), _edge),
          const Duration(seconds: 40));
    });

    test('a zero or unknown window is never behind', () {
      expect(behindOf(const Duration(seconds: 20), Duration.zero, _edge), isNull);
    });

    test('a position past the window end is not reported as negative', () {
      expect(behindOf(const Duration(seconds: 90), const Duration(seconds: 60), _edge),
          isNull);
    });
  });

  group('atLiveEdge', () {
    test('is the exact inverse of behindOf being null', () {
      expect(atLiveEdge(const Duration(seconds: 55), const Duration(seconds: 60), _edge),
          isTrue);
      expect(atLiveEdge(const Duration(seconds: 20), const Duration(seconds: 60), _edge),
          isFalse);
      expect(atLiveEdge(Duration.zero, Duration.zero, _edge), isTrue);
    });
  });
}
