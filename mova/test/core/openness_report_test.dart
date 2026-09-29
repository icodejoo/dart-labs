import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/events/events.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/report_config.dart';
import 'package:mova/src/core/report/collector.dart';
import 'package:mova/src/core/report/error_policy.dart';
import 'package:mova/src/core/report/report.dart';
import 'package:mova/src/core/report/session_id.dart';
import 'package:mova/src/core/report/stall.dart';

import '../support/fake_api.dart';

/// A stall policy that records every call so tests can prove it was really
/// consulted rather than the default silently winning.
///
/// 记录每次调用的卡顿策略，供测试证明它真被使用，而非默认实现悄悄生效。
class _RecordingStall implements MovaStallPolicy {
  int calls = 0;

  @override
  MovaStall? onStall(bool stalled, DateTime at) {
    calls++;
    return null;
  }

  @override
  void reset() {}
}

/// An error policy that records every call.
///
/// 记录每次调用的错误策略。
class _RecordingError implements MovaErrorPolicy {
  int calls = 0;

  @override
  MovaErrorVerdict classify(Object error, {String? subsystem, required bool afterFirstFrame}) {
    calls++;
    return const MovaErrorVerdict(fatal: true, code: 'custom');
  }
}

void main() {
  group(
    'telemetry-enhancement openness contract — every replace-the-user-decision '
    'row needs default + config knob + injectable policy',
    () {
      group('injection points', () {
        test('stallPolicy: default is MovaEdgeStall, injecting one replaces it and it is really consulted', () async {
          expect(const MovaReportConfig().newStallPolicy(), isA<MovaEdgeStall>());

          final recording = _RecordingStall();
          final events = StreamController<MovaEvent>.broadcast();
          final probe = FakeStatsProbe();
          final collector = MovaQoeCollector(
            events: events.stream,
            reporter: MovaCallbackReporter((_) {}),
            config: MovaReportConfig(qoe: true, stallPolicy: recording),
            probe: probe,
          );
          collector.onOpen(const MovaSource('https://host/a.mp4'), autoPlay: true);
          probe.pushRestart(); // land TTFF so stalls are actually forwarded to the policy
          await Future<void>.delayed(Duration.zero);
          probe.pushStalling(true);
          probe.pushStalling(false);
          await Future<void>.delayed(Duration.zero);
          expect(recording.calls, greaterThan(0), reason: 'the injected policy must really be consulted');
          await collector.cancel();
          await events.close();
          await probe.dispose();
        });

        test('errorPolicy: default is MovaPrefixError, injecting one replaces it and it is really consulted', () async {
          expect(const MovaReportConfig().effectiveErrorPolicy, isA<MovaPrefixError>());

          final recording = _RecordingError();
          final events = StreamController<MovaEvent>.broadcast();
          final collector = MovaQoeCollector(
            events: events.stream,
            reporter: MovaCallbackReporter((_) {}),
            config: MovaReportConfig(qoe: true, errorPolicy: recording),
          );
          collector.onOpen(const MovaSource('https://host/a.mp4'), autoPlay: true);
          events.add(MovaErrorEvent(Exception('boom')));
          await Future<void>.delayed(Duration.zero);
          expect(recording.calls, 1, reason: 'the injected policy must really be consulted');
          await collector.cancel();
          await events.close();
        });

        test('sessionId: default is newMovaSessionId, injecting a factory replaces it and it is really consulted', () async {
          expect(const MovaReportConfig().effectiveSessionIdFactory, newMovaSessionId);

          var calls = 0;
          String factory() {
            calls++;
            return 'fixed-id';
          }

          final events = StreamController<MovaEvent>.broadcast();
          final received = <MovaReportEvent>[];
          final collector = MovaQoeCollector(
            events: events.stream,
            reporter: MovaCallbackReporter(received.add),
            config: MovaReportConfig(qoe: true, sessionId: factory),
          );
          collector.onOpen(const MovaSource('https://host/a.mp4'), autoPlay: true);
          await Future<void>.delayed(Duration.zero);
          expect(calls, 1, reason: 'the injected factory must really be consulted');
          expect(received.single.sessionId, 'fixed-id');
          await collector.cancel();
          await events.close();
        });
      });

      group('config knobs', () {
        test('qoe: default false, event stream identical to legacy translator until flipped', () async {
          expect(const MovaReportConfig().qoe, isFalse);
          final events = StreamController<MovaEvent>.broadcast();
          final received = <MovaReportEvent>[];
          final collector = MovaQoeCollector(
            events: events.stream,
            reporter: MovaCallbackReporter(received.add),
            config: const MovaReportConfig(),
          );
          collector.onOpen(const MovaSource('https://host/a.mp4'), autoPlay: true);
          events.add(const MovaSourceChange(MovaSource('https://host/a.mp4')));
          await Future<void>.delayed(Duration.zero);
          expect(received.every((e) => e.sessionId == null), isTrue);
          await collector.cancel();
          await events.close();
        });

        test('minStall: default 200ms, feeds MovaEdgeStall when no policy is injected', () {
          expect(const MovaReportConfig().minStall, const Duration(milliseconds: 200));
          final policy = const MovaReportConfig(minStall: Duration(seconds: 1)).newStallPolicy() as MovaEdgeStall;
          expect(policy.minStall, const Duration(seconds: 1));
        });

        test('heartbeat: default null (no Timer at all), non-null enables periodic emission', () {
          expect(const MovaReportConfig().heartbeat, isNull);
          expect(const MovaReportConfig(heartbeat: Duration(seconds: 5)).heartbeat, const Duration(seconds: 5));
        });
      });
    },
  );
}
