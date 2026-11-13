import 'dart:async';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:mova/mova.dart';
import 'cp0_harness.dart';

/// Default player, no manual quality selection and no native event pump.
Future<void> runAutoTier(Cp0Harness h) async {
  for (final mode in ['limited', 'unlimited']) {
    for (var run = 0; run < (mode == 'limited' ? h.runs : 1); run++) {
      final a = createMova();
      await h.mount(a);
      final cursor = h.records.length;
      final uri =
          'http://127.0.0.1:18192/$mode/master.m3u8'
          '?t=${DateTime.now().microsecondsSinceEpoch}';
      // Elapsed time is monotonic and anchored before open, including startup.
      final startUs = h.clock.elapsedMicroseconds;
      final opening = h.call('open.auto', uri, () => a.open(MovaSource(uri)));
      final samples = <Map<String, Object?>>[];
      for (final second in List.generate(91, (index) => index)) {
        final remaining =
            startUs + second * 1000000 - h.clock.elapsedMicroseconds;
        if (remaining > 0) {
          await Future<void>.delayed(Duration(microseconds: remaining));
        }
        final player =
            (a.renderHandle as VideoController).player.platform as NativePlayer;
        final properties = <String, Object?>{};
        for (final key in [
          'path',
          'time-pos',
          'hls-bitrate',
          'video-params',
          'video-params/w',
          'video-params/h',
          'vid',
          'track-list',
          'demuxer-cache-state',
          'paused-for-cache',
          'cache-buffering-state',
        ]) {
          try {
            properties[key] = await player
                .getProperty(key)
                .timeout(const Duration(seconds: 3));
          } catch (e) {
            properties[key] = {'error': '$e'};
          }
        }
        final sample = <String, Object?>{
          'mode': mode,
          'run': run,
          'scheduledSeconds': second,
          'sinceOpenUs': h.clock.elapsedMicroseconds - startUs,
          'properties': properties,
          'state': h.snapshot(),
        };
        samples.add(sample);
        h.mark('AUTOTIER_SAMPLE', sample);
      }
      await opening.timeout(const Duration(seconds: 10));
      h.check('$mode.$run', {
        'uri': uri,
        'samples': samples,
        'events': h.records
            .skip(cursor)
            .where((r) => r['kind'] == 'EVENT')
            .toList(),
        'defaultMova': true,
        'manualQualityCommands': 0,
      });
      await h.release();
    }
  }
}
