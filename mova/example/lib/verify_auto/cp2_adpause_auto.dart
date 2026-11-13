import 'dart:async';
import 'package:mova/mova.dart';
import 'cp2_harness.dart';
import 'cp2_common.dart';
import 'cp2_criteria.dart';

Future<void> runAdpause(Cp2Harness h) async =>
    runCp2AdHold(h, background: false);
Future<void> runCp2AdHold(Cp2Harness h, {required bool background}) async {
  for (final guard in background ? [false, true] : [false]) {
    for (var run = 0; run < h.runs; run++) {
      final ad = cp2Source('ad');
      final opts = MovaOpts(
        cutover: cp2CutoverOpts,
        ads: MovaAdOpts(
          enabled: true,
          breaks: [
            MovaAdBreak(
              kind: MovaAdBreakKind.pre,
              source: ad,
              duration: const Duration(seconds: 6),
            ),
          ],
          onAdEvent: (e) => cp2AdEvent(h, e),
        ),
      );
      final api = cp2Cutover(h, opts);
      h.guarded = guard;
      await h.mount(api);
      final ads = MovaAds(api, cutover: api);
      final begin = h.records.length;
      try {
        await ads.load(cp2Source('long'));
        await cp2At(h, ad.uri);
        await h.waitPosition(1000);
        if (!background) await h.call('pause', null, api.pause);
        await h.until(() => background || !api.state.playing);
        final before = await h.native();
        final beforeUs = h.clock.elapsedMicroseconds;
        final pauseBegin = h.records.length;
        List<Map<String, dynamic>> samples = [];
        if (background) {
          samples = await cp2Background(h, 'home.$guard.$run', 30);
        } else {
          for (var i = 0; i < 40; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
            samples.add(await h.native());
          }
        }
        final pauseEnd = h.records.length;
        if (background && guard) await h.until(() => api.state.playing);
        final after = await h.native();
        final afterUs = h.clock.elapsedMicroseconds;
        final foreground = h.snapshot();
        final pausedCompleted = cp2AdRecords(
          h.records.sublist(pauseBegin, pauseEnd),
          ad.uri,
          type: 'completed',
        ).length;
        final frozen = cp2PausedSamples(samples, path: ad.uri);
        if (!guard || !background) {
          await h.call('play.manualResume', null, api.play);
        }
        await h.until(() => api.state.playing);
        // Match durationFromFirstFrame=true; only STATE playing edges freeze it.
        Map<String, Object?>? lastAd;
        await h.until(() async {
          final read = await h.native();
          if (read['path'] == ad.uri) lastAd = read;
          return cp2AdRecords(
            h.records.skip(begin),
            ad.uri,
            type: 'completed',
          ).isNotEmpty;
        });
        final rows = h.records.skip(begin).toList();
        final activeUs = cp2SlotActiveUs(rows, ad.uri);
        final beforeActiveUs = cp2SlotActiveUs(rows, ad.uri, untilUs: beforeUs);
        final afterActiveUs = cp2SlotActiveUs(rows, ad.uri, untilUs: afterUs);
        final slotError = activeUs == null ? null : activeUs / 1000 - 6000;
        final mediaPositionMs = lastAd?['timePosMs'] as int?;
        final drift = samples.isEmpty
            ? null
            : (samples.last['timePosMs'] as int) -
                  (samples.first['timePosMs'] as int);
        final semantics = background
            ? guard
                  ? foreground['playing'] == true &&
                        foreground['intent'] == true
                  : foreground['playing'] == false &&
                        foreground['intent'] == false
            : true;
        h.check(
          '${background
              ? guard
                    ? 'guard'
                    : 'plain'
              : 'pause'}.$run',
          {
            'before': before,
            'after': after,
            'backgroundSamples': samples,
            'foreground': foreground,
            'pausedCompleted': pausedCompleted,
            'nativePauseDriftMs': drift,
            'slotRemainingBeforeMs': beforeActiveUs == null
                ? null
                : 6000 - beforeActiveUs / 1000,
            'slotRemainingAfterMs': afterActiveUs == null
                ? null
                : 6000 - afterActiveUs / 1000,
            'slotActiveUs': activeUs,
            'slotErrorMs': slotError,
            'mediaPositionErrorMs': mediaPositionMs == null
                ? null
                : mediaPositionMs - 6000,
            'lastAd': lastAd,
            'ads': cp2AdRecords(rows, ad.uri).toList(),
          },
          missing:
              slotError == null ||
                  beforeActiveUs == null ||
                  afterActiveUs == null ||
                  samples.length < 2
              ? 'first frame, playing edges, completion or native samples unavailable'
              : null,
          pass:
              frozen &&
              drift != null &&
              drift.abs() <= 300 &&
              slotError != null &&
              slotError.abs() <= 300 &&
              pausedCompleted == 0 &&
              semantics,
        );
      } finally {
        await ads.dispose();
        await h.release();
      }
    }
  }
}
