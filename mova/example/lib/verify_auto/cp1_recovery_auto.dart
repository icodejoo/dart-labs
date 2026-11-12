// 未上机。真实 HLS 分片闸门、恢复事件与原生 time-pos 联合对账。
import 'dart:async';
import 'package:mova/mova.dart';
import 'cp1_harness.dart';
import 'seek_landing.dart';

Future<void> runRecovery(Cp1Harness h) async {
  for (final kind in ['resume', 'manual720']) {
    for (var run = 0; run < h.runs; run++) {
      await h.control('reset');
      await h.control('throttle', {'bytesPerSecond': 400000});
      final a = createMovaEngine(
        preciseFirstFrame: true,
        options: const MovaOpts(
          recovery: MovaRecoveryConfig(
            enabled: true,
            stallTimeout: Duration(seconds: 3),
          ),
        ),
      );
      await h.mount(a);
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final master = 'http://127.0.0.1:18194/master.m3u8?t=$stamp';
      final tier = 'http://127.0.0.1:18194/720/index.m3u8?t=$stamp';
      await a.open(MovaSource(kind == 'manual720' ? master : tier,
        mpvOptions: const {'demuxer-readahead-secs': '1',
          'demuxer-max-bytes': '524288', 'cache-secs': '1'}));
      await h.until(() => a.state.rendered);
      if (kind == 'manual720') {
        await a.switchQuality(
          MovaQuality(label: '720p', uri: tier, height: 720),
        );
        await h.until(() async => (await h.native())['path'] == tier);
      }
      await h.waitPosition(2000);
      final begin = h.records.length;
      Map<String, Object?>? stalled;
      // Watch native position throughout starvation, before the retry can reset it.
      final sub = a.events.listen((e) {
        if (e is MovaPlayFailure) unawaited(h.control('release'));
      });
      h.cleanup.add(sub.cancel);
      await h.control('arm', {'kind': 'recovery'});
      await h.until(() async {
        final fixture = await h.control('stats');
        if (fixture['segmentEntered'] == true && a.state.buffering) {
          stalled = await h.native();
          return true;
        }
        return false;
      }, seconds: 120);
      // A genuine stall failure must be observed; no command retries or fake events.
      await h.until(
        () => h.events('MovaRecovered', begin).isNotEmpty,
        seconds: 90,
      );
      // Recovery deliberately resumes with notify=false: MovaSeeked is a
      // user-seek event, not a recovery completion contract. Verify native
      // landing and motion instead of waiting for that unrelated event.
      final landing = SeekLanding(stalled!['timePosMs'] as int, playing: true);
      final landingClock = Stopwatch()..start();
      final nativeSamples = <Map<String, Object?>>[];
      Map<String, Object?>? candidate;
      Map<String, Object?>? after;
      await h.until(() async {
        final read = await h.native();
        nativeSamples.add(read);
        final prior = landing.landedMs;
        final accepted = landing.sample(
          elapsedMs: landingClock.elapsedMilliseconds,
          positionMs: read['timePosMs'] as int,
          seeking: read['seeking'] != 'no', buffering: a.state.buffering,
          pathMatches: read['path'] == tier);
        if (landing.landedMs == null) {
          candidate = null;
        } else if (prior == null) {
          candidate = read;
        }
        if (accepted) after = candidate;
        return accepted;
      });
      final resume = h.events('MovaSeeked', begin);
      final failures = h.events('MovaPlayFailure', begin);
      final diff =
          ((after!['timePosMs'] as int) - (stalled!['timePosMs'] as int)).abs();
      final retryCount = failures
          .where(
            (r) =>
                (r['payload'] as Map)['action'] == 'MovaRecoveryAction.retry',
          )
          .length;
      final fixture = await h.control('stats');
      h.check(
        '$kind.$run',
        {
          'failures': failures,
          'recovered': h.events('MovaRecovered', begin),
          'retryCount': retryCount,
          'before': stalled,
          'after': after,
          'resumeNativeSamples': nativeSamples,
          'resumePositionDiffMs': diff,
          'currentQuality': a.state.currentQuality?.label,
          'fixture': fixture,
          'seeked': resume,
        },
        pass:
            retryCount >= 1 &&
            failures.any(
              (r) => (r['payload'] as Map)['kind'] == 'stallTimeout',
            ) &&
            fixture['segmentEntered'] == true &&
            diff <= 500 &&
            stalled!['path'] == tier &&
            after!['path'] == tier &&
            (kind != 'manual720' || a.state.currentQuality?.label == '720p'),
      );
      await h.release();
    }
  }
}
