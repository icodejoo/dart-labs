import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/events/events.dart';
import 'package:mova/src/core/model/quality.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/report_config.dart';
import 'package:mova/src/core/report/collector.dart';
import 'package:mova/src/core/report/report.dart';
import 'package:mova/src/core/report/stats_probe.dart';

import '../../support/fake_api.dart';

const _quality1080 = MovaQuality(label: '1080p', uri: 'https://host/1080.m3u8', width: 1920, height: 1080);
const _quality720 = MovaQuality(label: '720p', uri: 'https://host/720.m3u8', width: 1280, height: 720);

void main() {
  group('Task 9 — qualityChange/abrDownShift bitrate enrichment', () {
    test('probe absent — legacy shape unchanged, no fromBps/toBps/width/height/reason keys', () async {
      final events = StreamController<MovaEvent>.broadcast();
      final received = <MovaReportEvent>[];
      final collector = MovaQoeCollector(
        events: events.stream,
        reporter: MovaCallbackReporter(received.add),
        config: const MovaReportConfig(qoe: true),
      );
      collector.onOpen(const MovaSource('https://host/master.m3u8'), autoPlay: true);
      events.add(const MovaQualityChange(_quality1080));
      await Future<void>.delayed(Duration.zero);

      final e = received.singleWhere((r) => r.name == MovaReportName.qualityChange);
      expect(e.params.containsKey('fromBps'), isFalse);
      expect(e.params.containsKey('toBps'), isFalse);
      expect(e.params['quality'], '1080p');
      expect(e.params['width'], 1920);
      expect(e.params['height'], 1080);
      expect(e.params['reason'], 'manual');
      await collector.cancel();
      await events.close();
    });

    test('probe present — fromBps/toBps come from consecutive sample() calls', () async {
      final probe = FakeStatsProbe();
      final events = StreamController<MovaEvent>.broadcast();
      final received = <MovaReportEvent>[];
      final collector = MovaQoeCollector(
        events: events.stream,
        reporter: MovaCallbackReporter(received.add),
        config: const MovaReportConfig(qoe: true),
        probe: probe,
      );
      collector.onOpen(const MovaSource('https://host/master.m3u8'), autoPlay: true);

      probe.sampleResult = const MovaStatsSnapshot(videoBps: 8000000);
      events.add(const MovaQualityChange(_quality1080));
      await Future<void>.delayed(Duration.zero);
      final first = received.singleWhere((r) => r.name == MovaReportName.qualityChange);
      // First switch: there is no prior sample yet, so fromBps is absent.
      expect(first.params.containsKey('fromBps'), isFalse);
      expect(first.params['toBps'], 8000000);

      probe.sampleResult = const MovaStatsSnapshot(videoBps: 3000000);
      events.add(const MovaAbrDownShift(_quality1080, _quality720));
      await Future<void>.delayed(Duration.zero);
      final second = received.lastWhere((r) => r.name == MovaReportName.abrDownShift);
      expect(second.params['fromBps'], 8000000, reason: 'carries forward the previously sampled bps');
      expect(second.params['toBps'], 3000000);
      expect(second.params['reason'], 'abr');
      expect(second.params['from'], '1080p');
      expect(second.params['to'], '720p');
      expect(second.params['width'], 1280);
      expect(second.params['height'], 720);

      await collector.cancel();
      await events.close();
      await probe.dispose();
    });

    test('abrDownShift without a probe keeps the legacy from/to-only shape', () async {
      final events = StreamController<MovaEvent>.broadcast();
      final received = <MovaReportEvent>[];
      final collector = MovaQoeCollector(
        events: events.stream,
        reporter: MovaCallbackReporter(received.add),
        config: const MovaReportConfig(qoe: true),
      );
      collector.onOpen(const MovaSource('https://host/master.m3u8'), autoPlay: true);
      events.add(const MovaAbrDownShift(_quality1080, _quality720));
      await Future<void>.delayed(Duration.zero);

      final e = received.singleWhere((r) => r.name == MovaReportName.abrDownShift);
      expect(e.params.containsKey('fromBps'), isFalse);
      expect(e.params.containsKey('toBps'), isFalse);
      await collector.cancel();
      await events.close();
    });

    test('qoe: false keeps the pre-existing 1-key qualityChange/abrDownShift shape', () async {
      final events = StreamController<MovaEvent>.broadcast();
      final received = <MovaReportEvent>[];
      final collector = MovaQoeCollector(
        events: events.stream,
        reporter: MovaCallbackReporter(received.add),
        config: const MovaReportConfig(),
      );
      collector.onOpen(const MovaSource('https://host/master.m3u8'), autoPlay: true);
      events.add(const MovaQualityChange(_quality1080));
      events.add(const MovaAbrDownShift(_quality1080, _quality720));
      await Future<void>.delayed(Duration.zero);

      final quality = received.singleWhere((r) => r.name == MovaReportName.qualityChange);
      expect(quality.params, {'quality': '1080p'});
      final abr = received.singleWhere((r) => r.name == MovaReportName.abrDownShift);
      expect(abr.params, {'from': '1080p', 'to': '720p'});
      await collector.cancel();
      await events.close();
    });
  });
}
