import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/live/timeshift.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/state/state.dart';

void main() {
  group('DESIGN section 6.2 openness contract — every row needs default + knob + injection', () {
    test('timeshift mode: off by default, seekMode knob', () {
      expect(const MovaLiveOpts().seekMode, MovaLiveSeekMode.off);
      expect(const MovaLiveOpts(seekMode: MovaLiveSeekMode.dvr).seekMode,
          MovaLiveSeekMode.dvr);
      expect(const MovaLiveOpts(seekMode: MovaLiveSeekMode.timeshift).seekMode,
          MovaLiveSeekMode.timeshift);
    });

    test('timeshift url: no default, urlBuilder injection', () {
      expect(const MovaLiveOpts().urlBuilder, isNull,
          reason: 'mova must never guess a server timeshift parameter');
      final c = MovaLiveOpts(urlBuilder: (u, b, t) => '$u!${b.inSeconds}');
      expect(c.urlBuilder!('x', const Duration(seconds: 3), DateTime(2026)), 'x!3');
    });

    test('dvr window: duration default, dvrWindow knob, windowResolver injection', () {
      const withDuration = MovaState(duration: Duration(minutes: 4));
      expect(resolveWindow(withDuration, const MovaLiveOpts()),
          const Duration(minutes: 4));
      expect(
        resolveWindow(withDuration,
            const MovaLiveOpts(dvrWindow: Duration(minutes: 1))),
        const Duration(minutes: 1),
      );
      expect(
        resolveWindow(
          withDuration,
          MovaLiveOpts(windowResolver: (_) => const Duration(minutes: 9)),
        ),
        const Duration(minutes: 9),
      );
    });

    test('edge threshold: 10s default, edgeThreshold knob', () {
      expect(const MovaLiveOpts().edgeThreshold, const Duration(seconds: 10));
      expect(
        const MovaLiveOpts(edgeThreshold: Duration(seconds: 30)).edgeThreshold,
        const Duration(seconds: 30),
      );
      expect(
        behindOf(const Duration(seconds: 40), const Duration(seconds: 60),
            const Duration(seconds: 30)),
        isNull,
        reason: 'a wider threshold must widen what counts as the edge',
      );
    });

    test('back-to-live: derived default, backToLive knob', () {
      expect(const MovaLiveOpts(seekMode: MovaLiveSeekMode.dvr).effectiveBackToLive,
          MovaBackToLive.seekEnd);
      expect(
          const MovaLiveOpts(seekMode: MovaLiveSeekMode.timeshift).effectiveBackToLive,
          MovaBackToLive.reopen);
      expect(
        const MovaLiveOpts(
          seekMode: MovaLiveSeekMode.timeshift,
          backToLive: MovaBackToLive.seekEnd,
        ).effectiveBackToLive,
        MovaBackToLive.seekEnd,
      );
    });

    test('auto back-to-live on stall: off by default, autoBackToLiveOnStall knob', () {
      expect(const MovaLiveOpts().autoBackToLiveOnStall, isFalse);
      expect(
        const MovaLiveOpts(autoBackToLiveOnStall: true).autoBackToLiveOnStall,
        isTrue,
      );
    });

    test('the whole section is replaceable through MovaOpts.copyWith', () {
      const o = MovaOpts();
      final n = o.copyWith(
          live: const MovaLiveOpts(seekMode: MovaLiveSeekMode.dvr));
      expect(n.live.seekMode, MovaLiveSeekMode.dvr);
      expect(n.gesture, o.gesture);
      expect(n.theme, o.theme);
    });

    test('live copy and colours stay externalised (MovaStrs / MovaTheme)', () {
      const s = MovaStrs(live: 'ON AIR', timeshift: 'REPLAY', backToLive: 'GO LIVE');
      expect(s.live, 'ON AIR');
      expect(s.timeshift, 'REPLAY');
      expect(s.backToLive, 'GO LIVE');
      expect(const MovaTheme().timeshiftBadgeColor,
          isNot(const MovaTheme().accentColor),
          reason: 'the timeshifted badge must be visually distinct from LIVE');
    });
  });
}
