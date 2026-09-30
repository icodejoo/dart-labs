import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/events/events.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/report_config.dart';
import 'package:mova/src/core/report/collector.dart';
import 'package:mova/src/core/report/report.dart';
import 'package:mova/src/core/report/stats_probe.dart';

import '../../support/fake_api.dart';

void main() {
  group('MovaStatsProbe — degrades gracefully, never errors', () {
    test('a collector with probe: null does not throw and just skips enrichment', () async {
      final events = StreamController<MovaEvent>.broadcast();
      final received = <MovaReportEvent>[];
      final collector = MovaQoeCollector(
        events: events.stream,
        reporter: MovaCallbackReporter(received.add),
        config: const MovaReportConfig(qoe: true),
      );
      collector.onOpen(const MovaSource('https://host/a.mp4'), autoPlay: true);
      await Future<void>.delayed(Duration.zero);
      await collector.cancel();
      await events.close();
    });

    test('FakeStatsProbe tracks whether stalling was ever subscribed', () async {
      final probe = FakeStatsProbe();
      expect(probe.stallingSubscribed, isFalse);
      final sub = probe.stalling.listen((_) {});
      expect(probe.stallingSubscribed, isTrue);
      probe.pushStalling(true);
      probe.pushStalling(false);
      await sub.cancel();
    });

    test('logs carries the prefix the fake was told to push', () async {
      final probe = FakeStatsProbe();
      final lines = <MovaLogLine>[];
      final sub = probe.logs.listen(lines.add);
      probe.pushLog(const MovaLogLine(prefix: 'vd', level: 'error', text: 'boom'));
      await Future<void>.delayed(Duration.zero);
      expect(lines.single.prefix, 'vd');
      await sub.cancel();
    });

    test('sample() can return a snapshot with some fields present, others null', () async {
      final probe = FakeStatsProbe();
      probe.sampleResult = const MovaStatsSnapshot(videoBps: 5000, hwdec: null);
      final snap = await probe.sample();
      expect(snap!.videoBps, 5000);
      expect(snap.hwdec, isNull);
    });

    test('an audioOnly-shaped snapshot has null video-side fields', () {
      const snap = MovaStatsSnapshot(inputBps: 100, viaNetwork: true, fileFormat: 'hls');
      expect(snap.videoBps, isNull);
      expect(snap.voDrops, isNull);
      expect(snap.decoderDrops, isNull);
    });

    test('playbackRestarts tracks whether it was ever subscribed', () async {
      final probe = FakeStatsProbe();
      expect(probe.playbackRestartsSubscribed, isFalse);
      final sub = probe.playbackRestarts.listen((_) {});
      expect(probe.playbackRestartsSubscribed, isTrue);
      probe.pushRestart();
      await sub.cancel();
    });

    test('endFiles carries the reason the fake was told to push', () async {
      final probe = FakeStatsProbe();
      final reasons = <MovaEndFileReason>[];
      final sub = probe.endFiles.listen(reasons.add);
      probe.pushEndFile(MovaEndFileReason.stop);
      await Future<void>.delayed(Duration.zero);
      expect(reasons.single, MovaEndFileReason.stop);
      await sub.cancel();
    });

    test(
      '2026-09-29 platform guard: a probe whose native streams simply never '
      'emit (silent degrade, mirroring MovaMpvKernel._observeNativeEvents '
      'catching an observeEvent failure) does not stop the rest of the QoE '
      'layer from working — firstFrame still lands via the buffering fallback, '
      'sessionEnd still resolves via the old heuristic',
      () async {
        final events = StreamController<MovaEvent>.broadcast();
        final received = <MovaReportEvent>[];
        final probe = FakeStatsProbe(); // never pushRestart()/pushEndFile()
        final collector = MovaQoeCollector(
          events: events.stream,
          reporter: MovaCallbackReporter(received.add),
          config: const MovaReportConfig(qoe: true),
          probe: probe,
        );
        collector.onOpen(const MovaSource('https://host/a.mp4'), autoPlay: true);
        events.add(const MovaBufferChange(true));
        events.add(const MovaBufferChange(false));
        await Future<void>.delayed(Duration.zero);
        expect(
          received.any((e) => e.name == MovaReportName.firstFrame && e.params['signal'] == 'buffering'),
          isTrue,
        );
        collector.onTeardown();
        expect(received.any((e) => e.name == MovaReportName.sessionEnd), isTrue);
        await collector.cancel();
        await events.close();
        await probe.dispose();
      },
    );

    group('nativeRestartAvailable gating', () {
      /// 建 collector 并开一次会话，返回收集到的上报与清理函数。
      Future<({List<MovaReportEvent> got, StreamController<MovaEvent> events, MovaQoeCollector c, FakeStatsProbe probe})>
          setup({required bool native}) async {
        final events = StreamController<MovaEvent>.broadcast();
        final got = <MovaReportEvent>[];
        final probe = FakeStatsProbe()..nativeRestartAvailable = native;
        final c = MovaQoeCollector(
          events: events.stream,
          reporter: MovaCallbackReporter(got.add),
          config: const MovaReportConfig(qoe: true),
          probe: probe,
        );
        c.onOpen(const MovaSource('https://host/a.mp4'), autoPlay: true);
        return (got: got, events: events, c: c, probe: probe);
      }

      List<MovaReportEvent> firstFrames(List<MovaReportEvent> l) =>
          l.where((e) => e.name == MovaReportName.firstFrame).toList();

      test('native live: buffering edge and position samples do NOT land the first frame', () async {
        final t = await setup(native: true);
        t.events.add(const MovaBufferChange(true));
        t.events.add(const MovaBufferChange(false));
        t.c.onPosition(const Duration(milliseconds: 10));
        t.c.onPosition(const Duration(milliseconds: 60));
        await Future<void>.delayed(Duration.zero);
        expect(firstFrames(t.got), isEmpty);
        await t.c.cancel();
        await t.events.close();
        await t.probe.dispose();
      });

      test('native live: the RESTART event lands it, exactly once, with signal=restart', () async {
        final t = await setup(native: true);
        t.events.add(const MovaBufferChange(true));
        t.events.add(const MovaBufferChange(false));
        t.probe.pushRestart();
        await Future<void>.delayed(Duration.zero);
        final ff = firstFrames(t.got);
        expect(ff, hasLength(1));
        expect(ff.single.params['signal'], 'restart');
        await t.c.cancel();
        await t.events.close();
        await t.probe.dispose();
      });

      test('native not live: fallbacks still land the first frame (unchanged behavior)', () async {
        final t = await setup(native: false);
        t.events.add(const MovaBufferChange(true));
        t.events.add(const MovaBufferChange(false));
        await Future<void>.delayed(Duration.zero);
        expect(firstFrames(t.got).single.params['signal'], 'buffering');
        await t.c.cancel();
        await t.events.close();
        await t.probe.dispose();
      });
    });
  });
}
