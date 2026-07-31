import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/live/timeshift.dart';
import 'package:videoman/src/core/options/options.dart';
import 'package:videoman/src/core/state/state.dart';

void main() {
  group('DESIGN section 6.2 openness contract — every row needs default + knob + injection', () {
    test('timeshift mode: off by default, seekMode knob', () {
      expect(const VmLiveConfig().seekMode, VmLiveSeekMode.off);
      expect(const VmLiveConfig(seekMode: VmLiveSeekMode.dvr).seekMode,
          VmLiveSeekMode.dvr);
      expect(const VmLiveConfig(seekMode: VmLiveSeekMode.timeshift).seekMode,
          VmLiveSeekMode.timeshift);
    });

    test('timeshift url: no default, urlBuilder injection', () {
      expect(const VmLiveConfig().urlBuilder, isNull,
          reason: 'videoman must never guess a server timeshift parameter');
      final c = VmLiveConfig(urlBuilder: (u, b, t) => '$u!${b.inSeconds}');
      expect(c.urlBuilder!('x', const Duration(seconds: 3), DateTime(2026)), 'x!3');
    });

    test('dvr window: duration default, dvrWindow knob, windowResolver injection', () {
      const withDuration = VmState(duration: Duration(minutes: 4));
      expect(resolveWindow(withDuration, const VmLiveConfig()),
          const Duration(minutes: 4));
      expect(
        resolveWindow(withDuration,
            const VmLiveConfig(dvrWindow: Duration(minutes: 1))),
        const Duration(minutes: 1),
      );
      expect(
        resolveWindow(
          withDuration,
          VmLiveConfig(windowResolver: (_) => const Duration(minutes: 9)),
        ),
        const Duration(minutes: 9),
      );
    });

    test('edge threshold: 10s default, edgeThreshold knob', () {
      expect(const VmLiveConfig().edgeThreshold, const Duration(seconds: 10));
      expect(
        const VmLiveConfig(edgeThreshold: Duration(seconds: 30)).edgeThreshold,
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
      expect(const VmLiveConfig(seekMode: VmLiveSeekMode.dvr).effectiveBackToLive,
          VmBackToLive.seekEnd);
      expect(
          const VmLiveConfig(seekMode: VmLiveSeekMode.timeshift).effectiveBackToLive,
          VmBackToLive.reopen);
      expect(
        const VmLiveConfig(
          seekMode: VmLiveSeekMode.timeshift,
          backToLive: VmBackToLive.seekEnd,
        ).effectiveBackToLive,
        VmBackToLive.seekEnd,
      );
    });

    test('auto back-to-live on stall: off by default, autoBackToLiveOnStall knob', () {
      expect(const VmLiveConfig().autoBackToLiveOnStall, isFalse);
      expect(
        const VmLiveConfig(autoBackToLiveOnStall: true).autoBackToLiveOnStall,
        isTrue,
      );
    });

    test('the whole section is replaceable through VmOptions.copyWith', () {
      const o = VmOptions();
      final n = o.copyWith(
          live: const VmLiveConfig(seekMode: VmLiveSeekMode.dvr));
      expect(n.live.seekMode, VmLiveSeekMode.dvr);
      expect(n.gesture, o.gesture);
      expect(n.theme, o.theme);
    });

    test('live copy and colours stay externalised (VmStrings / VmTheme)', () {
      const s = VmStrings(live: 'ON AIR', timeshift: 'REPLAY', backToLive: 'GO LIVE');
      expect(s.live, 'ON AIR');
      expect(s.timeshift, 'REPLAY');
      expect(s.backToLive, 'GO LIVE');
      expect(const VmTheme().timeshiftBadgeColor,
          isNot(const VmTheme().accentColor),
          reason: 'the timeshifted badge must be visually distinct from LIVE');
    });
  });
}
