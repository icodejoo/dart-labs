import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/events/events.dart';
import 'package:mova/src/core/model/quality.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/report/report.dart';
import 'package:mova/src/core/report/translator.dart';
import 'package:mova/src/core/swap/ctl.dart';

void main() {
  final fixedNow = DateTime(2026, 1, 1);
  DateTime now() => fixedNow;

  group('translateMovaEvent — whitelisted events map to the right name/kind/priority', () {
    test('MovaSourceChange -> sourceChange (event, batched)', () {
      final r = translateMovaEvent(const MovaSourceChange(MovaSource('https://host/a.mp4')), now: now);
      expect(r!.kind, MovaReportKind.event);
      expect(r.name, MovaReportName.sourceChange);
      expect(r.priority, MovaReportPriority.batched);
      expect(r.params['uri'], 'https://host/a.mp4');
      expect(r.at, fixedNow);
    });

    test('MovaPlay -> play', () {
      final r = translateMovaEvent(const MovaPlay(), now: now);
      expect(r!.name, MovaReportName.play);
      expect(r.kind, MovaReportKind.event);
    });

    test('MovaPause -> pause', () {
      final r = translateMovaEvent(const MovaPause(), now: now);
      expect(r!.name, MovaReportName.pause);
    });

    test('MovaSeek -> seek with targetMs param', () {
      final r = translateMovaEvent(const MovaSeek(Duration(seconds: 5)), now: now);
      expect(r!.name, MovaReportName.seek);
      expect(r.params['targetMs'], 5000);
    });

    test('MovaSeeked -> seeked with positionMs param', () {
      final r = translateMovaEvent(const MovaSeeked(Duration(seconds: 7)), now: now);
      expect(r!.name, MovaReportName.seeked);
      expect(r.params['positionMs'], 7000);
    });

    test('MovaDone -> done, immediate priority', () {
      final r = translateMovaEvent(const MovaDone(), now: now);
      expect(r!.name, MovaReportName.done);
      expect(r.priority, MovaReportPriority.immediate);
    });

    test('MovaQualityChange -> qualityChange with quality label', () {
      const q = MovaQuality(label: '1080p', uri: 'https://host/1080.m3u8');
      final r = translateMovaEvent(const MovaQualityChange(q), now: now);
      expect(r!.name, MovaReportName.qualityChange);
      expect(r.params['quality'], '1080p');
    });

    test('MovaAbrDownShift -> abrDownShift with from/to labels', () {
      const from = MovaQuality(label: '1080p', uri: 'https://host/1080.m3u8');
      const to = MovaQuality(label: '720p', uri: 'https://host/720.m3u8');
      final r = translateMovaEvent(const MovaAbrDownShift(from, to), now: now);
      expect(r!.name, MovaReportName.abrDownShift);
      expect(r.params['from'], '1080p');
      expect(r.params['to'], '720p');
    });

    test('MovaFullScreenChange -> fullScreenChange', () {
      final r = translateMovaEvent(const MovaFullScreenChange(true), now: now);
      expect(r!.name, MovaReportName.fullScreenChange);
      expect(r.params['value'], isTrue);
    });

    test('MovaPipChange -> pipChange', () {
      final r = translateMovaEvent(const MovaPipChange(true), now: now);
      expect(r!.name, MovaReportName.pipChange);
    });

    test('MovaMiniChange -> miniChange', () {
      final r = translateMovaEvent(const MovaMiniChange(true), now: now);
      expect(r!.name, MovaReportName.miniChange);
    });

    test('MovaLiveEdgeReach -> liveEdgeReach', () {
      final r = translateMovaEvent(const MovaLiveEdgeReach(), now: now);
      expect(r!.name, MovaReportName.liveEdgeReach);
    });
  });

  group('translateMovaEvent — deliberately excluded high-frequency/internal events return null', () {
    test('MovaErrorEvent is excluded (fatal/code classification moved to MovaQoeCollector)', () {
      expect(translateMovaEvent(const MovaErrorEvent('boom'), now: now), isNull);
    });

    test('MovaBufferChange is excluded (flaps during stalls)', () {
      expect(translateMovaEvent(const MovaBufferChange(true), now: now), isNull);
    });

    test('MovaVolumeChange is excluded (fires per drag pixel)', () {
      expect(translateMovaEvent(const MovaVolumeChange(50), now: now), isNull);
    });

    test('MovaBrightChange is excluded (fires per drag pixel)', () {
      expect(translateMovaEvent(const MovaBrightChange(0.5), now: now), isNull);
    });

    test('MovaZoomChange is excluded (fires per pinch step)', () {
      expect(translateMovaEvent(const MovaZoomChange(1.5), now: now), isNull);
    });

    test('MovaDurationChange/MovaSizeChange are excluded (decoder metadata)', () {
      expect(translateMovaEvent(const MovaDurationChange(Duration(seconds: 1)), now: now), isNull);
      expect(translateMovaEvent(const MovaSizeChange(1920, 1080), now: now), isNull);
    });

    test('MovaReady is excluded (redundant with MovaSourceChange)', () {
      expect(translateMovaEvent(const MovaReady(), now: now), isNull);
    });

    test('MovaSwapChange is excluded (internal implementation detail)', () {
      expect(translateMovaEvent(const MovaSwapChange(MovaSwapPhase.idle), now: now), isNull);
    });

    test('MovaTimeShiftChange is excluded (flaps while timeshifting)', () {
      expect(translateMovaEvent(const MovaTimeShiftChange(Duration(seconds: 3)), now: now), isNull);
    });
  });
}
