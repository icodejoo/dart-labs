import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/report/session.dart';
import 'package:mova/src/core/report/stats_probe.dart';

void main() {
  group('resolveSessionEnd — four-way split, fatal wins over completed', () {
    test('fatal beats completed: failed even if playback also reached the end', () {
      expect(
        resolveSessionEnd(fatalSeen: true, completed: true, firstFrame: true),
        MovaSessionEnd.failed,
      );
    });

    test('completed with no fatal error -> ended', () {
      expect(
        resolveSessionEnd(fatalSeen: false, completed: true, firstFrame: true),
        MovaSessionEnd.ended,
      );
    });

    test('not completed, first frame landed, no fatal -> stopped', () {
      expect(
        resolveSessionEnd(fatalSeen: false, completed: false, firstFrame: true),
        MovaSessionEnd.stopped,
      );
    });

    test('first frame never landed, no fatal -> abandoned', () {
      expect(
        resolveSessionEnd(fatalSeen: false, completed: false, firstFrame: false),
        MovaSessionEnd.abandoned,
      );
    });

    test('fatal with no first frame is still failed, not abandoned', () {
      expect(
        resolveSessionEnd(fatalSeen: true, completed: false, firstFrame: false),
        MovaSessionEnd.failed,
      );
    });
  });

  group(
    'resolveSessionEndNative — same four-way split, corroborated by the '
    'native MPV_EVENT_END_FILE reason (2026-09-29 update)',
    () {
      test('nativeReason: null falls back to exactly resolveSessionEnd', () {
        for (final fatalSeen in [true, false]) {
          for (final completed in [true, false]) {
            for (final firstFrame in [true, false]) {
              expect(
                resolveSessionEndNative(
                  nativeReason: null,
                  fatalSeen: fatalSeen,
                  completed: completed,
                  firstFrame: firstFrame,
                ),
                resolveSessionEnd(fatalSeen: fatalSeen, completed: completed, firstFrame: firstFrame),
              );
            }
          }
        }
      });

      test('completed stays authoritative for ended even with a native STOP reason', () {
        expect(
          resolveSessionEndNative(
            nativeReason: MovaEndFileReason.stop,
            fatalSeen: false,
            completed: true,
            firstFrame: true,
          ),
          MovaSessionEnd.ended,
        );
      });

      test('a native ERROR reason alone is enough for failed, even if fatalSeen was missed', () {
        expect(
          resolveSessionEndNative(
            nativeReason: MovaEndFileReason.error,
            fatalSeen: false,
            completed: false,
            firstFrame: true,
          ),
          MovaSessionEnd.failed,
        );
      });

      test('a native STOP reason with first frame landed -> stopped', () {
        expect(
          resolveSessionEndNative(
            nativeReason: MovaEndFileReason.stop,
            fatalSeen: false,
            completed: false,
            firstFrame: true,
          ),
          MovaSessionEnd.stopped,
        );
      });

      test('a native QUIT reason with no first frame -> abandoned', () {
        expect(
          resolveSessionEndNative(
            nativeReason: MovaEndFileReason.quit,
            fatalSeen: false,
            completed: false,
            firstFrame: false,
          ),
          MovaSessionEnd.abandoned,
        );
      });
    },
  );

  group('MovaSessionTally', () {
    test('watchedMs only accrues while playing and not stalled', () {
      final tally = MovaSessionTally();
      final t0 = DateTime(2026, 1, 1);
      tally.tick(t0); // seeds _lastTick, no-op
      tally.setPlaying(true);
      tally.tick(t0.add(const Duration(seconds: 1)));
      expect(tally.watchedMs, 1000);
      tally.setStalled(true);
      tally.tick(t0.add(const Duration(seconds: 2)));
      expect(tally.watchedMs, 1000, reason: 'stalled time must not count as watched');
      expect(tally.stallMs, 1000);
    });

    test('rebufferRate is 0 when the denominator is 0 (never throws)', () {
      final tally = MovaSessionTally();
      expect(tally.rebufferRate, 0);
    });

    test('rebufferRate is stallMs / (watchedMs + stallMs)', () {
      final tally = MovaSessionTally();
      tally.addStall(const Duration(milliseconds: 500));
      final t0 = DateTime(2026, 1, 1);
      tally.tick(t0);
      tally.setPlaying(true);
      tally.tick(t0.add(const Duration(milliseconds: 500)));
      expect(tally.rebufferRate, closeTo(0.5, 0.001));
    });

    test('completionPercent is null when duration is unknown (e.g. live)', () {
      final tally = MovaSessionTally();
      tally.recordPosition(const Duration(seconds: 10));
      expect(tally.completionPercent, isNull);
    });

    test('completionPercent is maxPositionMs / durationMs * 100', () {
      final tally = MovaSessionTally();
      tally.setDuration(const Duration(seconds: 100));
      tally.recordPosition(const Duration(seconds: 25));
      expect(tally.completionPercent, closeTo(25.0, 0.001));
    });
  });
}
