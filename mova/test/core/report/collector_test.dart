import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/events/events.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/report_config.dart';
import 'package:mova/src/core/report/collector.dart';
import 'package:mova/src/core/report/report.dart';

import '../../support/fake_api.dart';

/// A minimal end-to-end "open -> play -> pause -> seek -> done" sequence,
/// replayed against a fresh [MovaQoeCollector] so both the `qoe: false`
/// (byte-for-byte-unchanged) and `qoe: true` (enriched) paths can be
/// compared against the same inputs.
///
/// 一段最小的"open -> play -> pause -> seek -> done"序列，喂给一个全新的
/// [MovaQoeCollector]，使 `qoe: false`（逐字节不变）与 `qoe: true`（增强）
/// 两条路径可以在同一组输入下对比。
Future<List<MovaReportEvent>> _runSequence({required bool qoe}) async {
  final events = StreamController<MovaEvent>.broadcast();
  final received = <MovaReportEvent>[];
  final collector = MovaQoeCollector(
    events: events.stream,
    reporter: MovaCallbackReporter(received.add),
    config: MovaReportConfig(qoe: qoe),
  );
  collector.onOpen(const MovaSource('https://host/a.mp4'), autoPlay: true);
  events.add(const MovaSourceChange(MovaSource('https://host/a.mp4')));
  events.add(const MovaPlay());
  events.add(const MovaPause());
  events.add(const MovaDone());
  await Future<void>.delayed(Duration.zero);
  collector.onTeardown();
  await collector.cancel();
  await events.close();
  return received;
}

void main() {
  group('MovaQoeCollector — Task 4 skeleton wiring', () {
    test('reporter: null means the engine never constructs a collector, so a probe is never subscribed', () async {
      // This is exercised at the MovaEngine level (report_engine_test.dart);
      // here we just confirm a collector with a null-probe FakeStatsProbe
      // that is never even listened to proves the same contract at this
      // layer: nothing subscribes unless qoe is on.
      final probe = FakeStatsProbe();
      final events = StreamController<MovaEvent>.broadcast();
      MovaQoeCollector(
        events: events.stream,
        reporter: MovaCallbackReporter((_) {}),
        config: const MovaReportConfig(), // qoe defaults to false
        probe: probe,
      );
      await Future<void>.delayed(Duration.zero);
      expect(probe.stallingSubscribed, isFalse);
      expect(probe.logsSubscribed, isFalse);
      expect(probe.playbackRestartsSubscribed, isFalse);
      expect(probe.endFilesSubscribed, isFalse);
      await events.close();
      await probe.dispose();
    });

    test('qoe: true does subscribe the probe', () async {
      final probe = FakeStatsProbe();
      final events = StreamController<MovaEvent>.broadcast();
      MovaQoeCollector(
        events: events.stream,
        reporter: MovaCallbackReporter((_) {}),
        config: const MovaReportConfig(qoe: true),
        probe: probe,
      );
      await Future<void>.delayed(Duration.zero);
      expect(probe.stallingSubscribed, isTrue);
      expect(probe.logsSubscribed, isTrue);
      expect(probe.playbackRestartsSubscribed, isTrue);
      expect(probe.endFilesSubscribed, isTrue);
      await events.close();
      await probe.dispose();
    });

    test('qoe: false — the report event stream is the legacy whitelist, sessionId is always null', () async {
      final received = await _runSequence(qoe: false);
      final names = received.map((e) => e.name).toList();
      expect(names, [
        MovaReportName.sourceChange,
        MovaReportName.play,
        MovaReportName.pause,
        MovaReportName.done,
      ]);
      expect(received.every((e) => e.sessionId == null), isTrue);
    });

    test('qoe: true — the same 4 legacy names still appear, now with a constant non-null sessionId', () async {
      final received = await _runSequence(qoe: true);
      final legacyNames = received
          .map((e) => e.name)
          .where(
            (n) => [
              MovaReportName.sourceChange,
              MovaReportName.play,
              MovaReportName.pause,
              MovaReportName.done,
            ].contains(n),
          )
          .toList();
      expect(legacyNames, [
        MovaReportName.sourceChange,
        MovaReportName.play,
        MovaReportName.pause,
        MovaReportName.done,
      ]);
      final sessionIds = received.map((e) => e.sessionId).toSet();
      expect(sessionIds.length, 1, reason: 'one session -> one constant sessionId');
      expect(sessionIds.single, isNotNull);
    });

    test(
      'regression: sessionStart keeps its own session\'s id even when a probe '
      'sample is still pending and a teardown/new open() races in before it '
      'resolves (the async report builders must capture sessionId before '
      'their `await`, not read the mutable field after it)',
      () async {
        final probe = FakeStatsProbe();
        final events = StreamController<MovaEvent>.broadcast();
        final received = <MovaReportEvent>[];
        final collector = MovaQoeCollector(
          events: events.stream,
          reporter: MovaCallbackReporter(received.add),
          config: const MovaReportConfig(qoe: true),
          probe: probe,
        );
        // onOpen kicks off an async sessionStart (awaiting probe.sample())
        // that has not resolved yet when onTeardown runs synchronously right
        // after it — this is exactly the race the fix addresses.
        collector.onOpen(const MovaSource('https://host/a.mp4'), autoPlay: true);
        collector.onTeardown();
        await Future<void>.delayed(Duration.zero);
        final sessionStart = received.singleWhere((e) => e.name == MovaReportName.sessionStart);
        final sessionEnd = received.singleWhere((e) => e.name == MovaReportName.sessionEnd);
        expect(sessionStart.sessionId, isNotNull);
        expect(sessionStart.sessionId, sessionEnd.sessionId);
        await collector.cancel();
        await events.close();
        await probe.dispose();
      },
    );

    test('sessionId differs across two separate open() calls', () async {
      final events = StreamController<MovaEvent>.broadcast();
      final received = <MovaReportEvent>[];
      final collector = MovaQoeCollector(
        events: events.stream,
        reporter: MovaCallbackReporter(received.add),
        config: const MovaReportConfig(qoe: true),
      );
      collector.onOpen(const MovaSource('https://host/a.mp4'), autoPlay: true);
      collector.onTeardown();
      collector.onOpen(const MovaSource('https://host/b.mp4'), autoPlay: true);
      collector.onTeardown();
      await Future<void>.delayed(Duration.zero);
      final ids = received.map((e) => e.sessionId).toSet();
      expect(ids.length, 2);
      await collector.cancel();
      await events.close();
    });
  });
}
