// 未上机。真实 HLS 分片闸门、恢复事件与原生 time-pos 联合对账。
import 'dart:async';
import 'package:mova/mova.dart';
import 'cp2_harness.dart';
import 'cp2_common.dart';
import 'seek_landing.dart';

Future<void> runQoe(Cp2Harness h) async {
  for (final kind in ['resume', 'manual720']) {
    for (var run = 0; run < h.runs; run++) {
      await h.control('reset');
      await h.control('throttle', {'bytesPerSecond': 400000});
      final reports=<Map<String,Object?>>[];
      final a = cp2Engine(h,
        reporter:MovaCallbackReporter((r){final row=<String,Object?>{'name':r.name.value,'sessionId':r.sessionId,'params':r.params};reports.add(row);h.mark('REPORT',row);}),

        options: const MovaOpts(
          report:MovaReportConfig(qoe:true),
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
      final recoveredQuality=a.state.currentQuality?.label;
      await a.switchQuality(MovaQuality(label:'360p',uri:'http://127.0.0.1:18194/360/index.m3u8?t=$stamp',height:360));
      await h.until(() async => (await h.native())['path']=='http://127.0.0.1:18194/360/index.m3u8?t=$stamp');
      await h.waitPosition(1000);
      final afterSwitch=await h.native();
      final starts=reports.where((r)=>r['name']=='sessionStart').toList();
      final sessionIds=reports.map((r)=>r['sessionId']).toSet();
      h.check(
        '$kind.$run',
        {
          'reports':reports, 'sessionStarts':starts.length, 'sessionIds':sessionIds.toList(), 'afterSwitch':afterSwitch,
          'failures': failures,
          'recovered': h.events('MovaRecovered', begin),
          'retryCount': retryCount,
          'before': stalled,
          'after': after,
          'resumeNativeSamples': nativeSamples,
          'resumePositionDiffMs': diff,
          'currentQuality': recoveredQuality,
          'fixture': fixture,
          'seeked': resume,
        },
        pass:
            starts.length==1 && starts.single['sessionId']!=null && '${starts.single['sessionId']}'.isNotEmpty && sessionIds.length==1 && a.state.currentQuality?.label=='360p' && retryCount >= 1 &&
            failures.any(
              (r) => (r['payload'] as Map)['kind'] == 'stallTimeout',
            ) &&
            fixture['segmentEntered'] == true &&
            diff <= 500 &&
            stalled!['path'] == tier &&
            after!['path'] == tier &&
            (kind != 'manual720' || recoveredQuality == '720p'),
      );
      await h.release();
    }
  }
}

/// R7：卡顿进行中用户暂停 30 秒再恢复，会话结束上报的 stallMs 不应包含暂停期。
/// Stall in progress, user pauses 30s then resumes: the ended report's stallMs must exclude the pause.
Future<void> runQoePause30(Cp2Harness h) async {
  for (var run = 0; run < h.runs; run++) {
    await h.control('reset');
    await h.control('throttle', {'bytesPerSecond': 400000});
    final reports = <Map<String, Object?>>[];
    final a = cp2Engine(h,
      reporter: MovaCallbackReporter((r) {
        final row = <String, Object?>{'name': r.name.value, 'sessionId': r.sessionId, 'params': r.params};
        reports.add(row);
        h.mark('REPORT', row);
      }),
      options: const MovaOpts(report: MovaReportConfig(qoe: true)),
    );
    await h.mount(a);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final tier = 'http://127.0.0.1:18194/720/index.m3u8?t=$stamp';
    await a.open(MovaSource(tier, mpvOptions: const {'demuxer-readahead-secs': '1', 'demuxer-max-bytes': '524288', 'cache-secs': '1'}));
    await h.until(() => a.state.rendered);
    await h.waitPosition(2000);
    await h.control('arm', {'kind': 'recovery'});
    await h.until(() async {
      final fixture = await h.control('stats');
      return fixture['segmentEntered'] == true && a.state.buffering;
    }, seconds: 120);
    final pauseClock = Stopwatch()..start();
    await a.pause();
    await Future<void>.delayed(const Duration(seconds: 30));
    await h.control('release');
    await a.play();
    await h.until(() async => !a.state.buffering, seconds: 60);
    await a.dispose();
    final ended = reports.where((r) => r['name'] == 'sessionEnd').toList();
    final stallMs = ended.isEmpty ? -1 : ((ended.last['params'] as Map)['stallMs'] as num?)?.toInt() ?? -1;
    h.check('pause30.$run', {
      'reports': reports,
      'pausedMs': pauseClock.elapsedMilliseconds,
      'stallMs': stallMs,
      'endCount': ended.length,
    }, pass: ended.length == 1 && stallMs >= 0 && stallMs < 15000);
    await h.release();
  }
}
