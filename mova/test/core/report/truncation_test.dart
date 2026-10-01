import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/events/events.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/report_config.dart';
import 'package:mova/src/core/report/collector.dart';
import 'package:mova/src/core/report/report.dart';
import 'package:mova/src/core/report/stats_probe.dart';
import 'package:mova/src/core/report/truncation.dart';

import '../../support/fake_api.dart';

bool _judge({
  double threshold = 0.9,
  int duration = 100000,
  int position = 0,
  bool live = false,
  bool ffErr = false,
}) =>
    resolveTruncated(
      threshold: threshold,
      durationMs: duration,
      validPositionMs: position,
      isLiveSource: live,
      ffmpegErrorBeforeEof: ffErr,
    );

/// Runs open -> first frame -> positions -> done -> teardown and returns reports.
Future<List<MovaReportEvent>> _run({
  required MovaReportConfig config,
  MovaStreamType type = MovaStreamType.vod,
  Duration? duration,
  List<int> positionsMs = const [],
  FakeStatsProbe? probe,
  Future<void> Function(FakeStatsProbe probe)? beforeDone,
}) async {
  final events = StreamController<MovaEvent>.broadcast();
  final received = <MovaReportEvent>[];
  final collector = MovaQoeCollector(
    events: events.stream,
    reporter: MovaCallbackReporter(received.add),
    config: config,
    probe: probe,
  );
  collector.onOpen(MovaSource('https://host/a', type: type), autoPlay: true);
  events.add(const MovaPlay());
  // buffering true -> false edge lands the first frame (no native restart).
  events.add(const MovaBufferChange(true));
  events.add(const MovaBufferChange(false));
  if (duration != null) events.add(MovaDurationChange(duration));
  await Future<void>.delayed(Duration.zero);
  for (final p in positionsMs) {
    collector.onPosition(Duration(milliseconds: p));
  }
  if (probe != null && beforeDone != null) {
    await beforeDone(probe);
  }
  events.add(const MovaDone());
  await Future<void>.delayed(Duration.zero);
  collector.onTeardown();
  await collector.cancel();
  await events.close();
  return received;
}

String _endReason(List<MovaReportEvent> r) =>
    r.firstWhere((e) => e.name == MovaReportName.sessionEnd).params['reason'] as String;

void main() {
  group('resolveTruncated', () {
    test('VOD below threshold is truncated', () => expect(_judge(position: 37000), isTrue));
    test('exactly at threshold is not truncated', () => expect(_judge(position: 90000), isFalse));
    test('just below threshold is truncated', () => expect(_judge(position: 89999), isTrue));
    test('full playback is not truncated', () => expect(_judge(position: 100000), isFalse));
    test('threshold 0 disables', () => expect(_judge(threshold: 0, position: 1), isFalse));
    test('duration 0 without ffmpeg error stays ended', () => expect(_judge(duration: 0), isFalse));
    test('duration 0 with ffmpeg error is truncated', () => expect(_judge(duration: 0, ffErr: true), isTrue));
    test('live ignores completion ratio', () => expect(_judge(live: true, position: 1), isFalse));
    test('live with ffmpeg error is truncated', () => expect(_judge(live: true, ffErr: true), isTrue));
    test('VOD ignores ffmpeg error when completion is enough', () => expect(_judge(position: 99000, ffErr: true), isFalse));
    test('threshold 0 disables live rule too', () => expect(_judge(threshold: 0, live: true, ffErr: true), isFalse));
  });

  group('collector truncated session end', () {
    test('early EOF -> failed + error code truncated', () async {
      final r = await _run(
        config: const MovaReportConfig(qoe: true),
        duration: const Duration(seconds: 100),
        positionsMs: [10000, 37000],
      );
      expect(_endReason(r), 'failed');
      final err = r.firstWhere((e) => e.name == MovaReportName.error);
      expect(err.params['code'], 'truncated');
      expect(err.params['fatal'], true);
    });

    test('full playback -> ended, no error', () async {
      final r = await _run(
        config: const MovaReportConfig(qoe: true),
        duration: const Duration(seconds: 100),
        positionsMs: [50000, 99000],
      );
      expect(_endReason(r), 'ended');
      expect(r.where((e) => e.name == MovaReportName.error), isEmpty);
    });

    test('seek near end then play to EOF -> ended', () async {
      final r = await _run(
        config: const MovaReportConfig(qoe: true),
        duration: const Duration(seconds: 100),
        positionsMs: [95000, 99500],
      );
      expect(_endReason(r), 'ended');
    });

    test('threshold disabled -> ended even if cut short', () async {
      final r = await _run(
        config: const MovaReportConfig(qoe: true, truncatedBelow: 0),
        duration: const Duration(seconds: 100),
        positionsMs: [37000],
      );
      expect(_endReason(r), 'ended');
    });

    test('unknown duration -> ended', () async {
      final r = await _run(config: const MovaReportConfig(qoe: true), positionsMs: [1000]);
      expect(_endReason(r), 'ended');
    });

    test('qoe off -> no sessionEnd, no truncated error', () async {
      final r = await _run(
        config: const MovaReportConfig(),
        duration: const Duration(seconds: 100),
        positionsMs: [37000],
      );
      expect(r.where((e) => e.name == MovaReportName.sessionEnd), isEmpty);
      expect(r.where((e) => e.name == MovaReportName.error), isEmpty);
    });

    test('live with ffmpeg error log before EOF -> failed truncated', () async {
      final r = await _run(
        config: const MovaReportConfig(qoe: true),
        type: MovaStreamType.live,
        probe: FakeStatsProbe(),
        beforeDone: (p) async {
          p.pushLog(const MovaLogLine(prefix: 'ffmpeg', level: 'error', text: 'tcp: Connection reset'));
          await Future<void>.delayed(Duration.zero);
        },
      );
      expect(_endReason(r), 'failed');
      expect(r.where((e) => e.name == MovaReportName.error && e.params['code'] == 'truncated'), hasLength(1));
    });

    test('live without error log -> ended', () async {
      final r = await _run(
        config: const MovaReportConfig(qoe: true),
        type: MovaStreamType.live,
        probe: FakeStatsProbe(),
      );
      expect(_endReason(r), 'ended');
    });
  });
}
