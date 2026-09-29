import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/events/events.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/report_config.dart';
import 'package:mova/src/core/report/collector.dart';
import 'package:mova/src/core/report/report.dart';

void main() {
  group('Task 10 — heartbeat (default off) + dispose Timer hygiene', () {
    test('heartbeat: null (default) never creates a Timer', () {
      fakeAsync((async) {
        final events = StreamController<MovaEvent>.broadcast();
        final received = <MovaReportEvent>[];
        final collector = MovaQoeCollector(
          events: events.stream,
          reporter: MovaCallbackReporter(received.add),
          config: const MovaReportConfig(qoe: true), // heartbeat left at its null default
        );
        collector.onOpen(const MovaSource('https://host/a.mp4'), autoPlay: true);
        expect(async.pendingTimers, isEmpty);
        async.elapse(const Duration(seconds: 30));
        expect(received.where((e) => e.name == MovaReportName.heartbeat), isEmpty);
        unawaited(collector.cancel());
        unawaited(events.close());
      });
    });

    test('heartbeat: <duration> emits on the configured interval while playing', () {
      fakeAsync((async) {
        final events = StreamController<MovaEvent>.broadcast();
        final received = <MovaReportEvent>[];
        final collector = MovaQoeCollector(
          events: events.stream,
          reporter: MovaCallbackReporter(received.add),
          config: const MovaReportConfig(qoe: true, heartbeat: Duration(seconds: 10)),
        );
        collector.onOpen(const MovaSource('https://host/a.mp4'), autoPlay: true);
        events.add(const MovaPlay());
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();
        expect(received.where((e) => e.name == MovaReportName.heartbeat), hasLength(1));

        async.elapse(const Duration(seconds: 20));
        async.flushMicrotasks();
        expect(received.where((e) => e.name == MovaReportName.heartbeat), hasLength(3));

        unawaited(collector.cancel());
        unawaited(events.close());
      });
    });

    test('no heartbeat while paused — nothing new to say', () {
      fakeAsync((async) {
        final events = StreamController<MovaEvent>.broadcast();
        final received = <MovaReportEvent>[];
        final collector = MovaQoeCollector(
          events: events.stream,
          reporter: MovaCallbackReporter(received.add),
          config: const MovaReportConfig(qoe: true, heartbeat: Duration(seconds: 10)),
        );
        collector.onOpen(const MovaSource('https://host/a.mp4'), autoPlay: true);
        // Never emits MovaPlay — stays paused for the whole window.
        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();
        expect(received.where((e) => e.name == MovaReportName.heartbeat), isEmpty);
        unawaited(collector.cancel());
        unawaited(events.close());
      });
    });

    test('dispose()/onTeardown() cancels the Timer — no heartbeat after teardown', () {
      fakeAsync((async) {
        final events = StreamController<MovaEvent>.broadcast();
        final received = <MovaReportEvent>[];
        final collector = MovaQoeCollector(
          events: events.stream,
          reporter: MovaCallbackReporter(received.add),
          config: const MovaReportConfig(qoe: true, heartbeat: Duration(seconds: 10)),
        );
        collector.onOpen(const MovaSource('https://host/a.mp4'), autoPlay: true);
        events.add(const MovaPlay());
        async.flushMicrotasks();
        collector.onTeardown();
        expect(async.pendingTimers, isEmpty);
        async.elapse(const Duration(seconds: 30));
        expect(received.where((e) => e.name == MovaReportName.heartbeat), isEmpty);
        unawaited(collector.cancel());
        unawaited(events.close());
      });
    });

    test('qoe: false never creates a heartbeat Timer even if heartbeat is configured', () {
      fakeAsync((async) {
        final events = StreamController<MovaEvent>.broadcast();
        final received = <MovaReportEvent>[];
        final collector = MovaQoeCollector(
          events: events.stream,
          reporter: MovaCallbackReporter(received.add),
          config: const MovaReportConfig(heartbeat: Duration(seconds: 10)), // qoe defaults to false
        );
        collector.onOpen(const MovaSource('https://host/a.mp4'), autoPlay: true);
        expect(async.pendingTimers, isEmpty);
        async.elapse(const Duration(seconds: 30));
        expect(received.where((e) => e.name == MovaReportName.heartbeat), isEmpty);
        unawaited(collector.cancel());
        unawaited(events.close());
      });
    });
  });
}
