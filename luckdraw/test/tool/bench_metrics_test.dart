import 'package:flutter_test/flutter_test.dart';

import '../../tool/bench/compare.dart';

/// 注册指标汇总、帧预算和 timeline 解析的无设备单元测试。
void main() {
  group('bench rss cycles', () {
    test('accepts exactly kRssCycles raw page and blank samples', () {
      expect(kRssCycles, 5);
      expect(kBenchRssGrowth, 'rss_steady_growth_bytes');
      expect(
          () => validateRssSamples({
                kBenchRssCycles: kRssCycles,
                'rss_baseline': 80,
                'rss_pages': List.filled(kRssCycles, 100),
                'rss_blank': List.filled(kRssCycles, 90),
              }),
          returnsNormally);
    });
    test('rejects old missing short zero and invalid RSS samples', () {
      final valid = <String, Object?>{
        kBenchRssCycles: kRssCycles,
        'rss_baseline': 80,
        'rss_pages': List.filled(kRssCycles, 100),
        'rss_blank': List.filled(kRssCycles, 90),
      };
      expect(
          () => validateRssSamples({...valid, kBenchRssCycles: kRssCycles + 1}),
          throwsFormatException);
      for (final invalid in [
        null,
        <int>[],
        List.filled(kRssCycles, 0),
        List.filled(kRssCycles, -1),
        List.filled(kRssCycles, 'bad')
      ]) {
        expect(() => validateRssSamples({...valid, 'rss_pages': invalid}),
            throwsFormatException);
      }
    });
    test('separates first return warmup from later net growth', () {
      final raw = <String, Object?>{
        kBenchRssCycles: kRssCycles,
        'rss_baseline': 100,
        'rss_pages': [520, 550, 540, 570, 560],
        'rss_blank': [500, 530, 510, 550, 540],
        kBenchRssGrowth: 9999,
      };
      expect(summarizeRss(raw), {
        kBenchRssDelta: 470,
        kBenchRssWarmup: 400,
        kBenchRssGrowth: 40,
      });
      expect(raw[kBenchRssGrowth], 9999);
      expect(raw['rss_blank'], [500, 530, 510, 550, 540]);
    });
    test('treats reclaimed RSS as zero growth and rejects invalid baseline',
        () {
      final raw = <String, Object?>{
        kBenchRssCycles: kRssCycles,
        'rss_baseline': 100,
        'rss_pages': List.filled(kRssCycles, 90),
        'rss_blank': [90, 80, 85, 80, 70],
      };
      expect(summarizeRss(raw).values, everyElement(0));
      for (final baseline in [null, 0, -1, double.infinity, '100']) {
        expect(() => summarizeRss({...raw, 'rss_baseline': baseline}),
            throwsFormatException);
      }
    });
    test('compares noisy RSS medians without a relative spread gate', () {
      expect(
          summarize([
            {kBenchRssGrowth: 100, kBenchRssWarmup: 4000},
            {kBenchRssGrowth: 1000, kBenchRssWarmup: 10},
            {kBenchRssGrowth: 800, kBenchRssWarmup: 2000},
          ]),
          {kBenchRssGrowth: 800, kBenchRssWarmup: 2000});
    });
  });
  group('bench summarize', () {
    test('takes the median of three runs without mutating input', () {
      final runs = <Map<String, Object?>>[
        {'ms': 10.0},
        {'ms': 9.0},
        {'ms': 11.0},
      ];
      expect(summarize(runs), {'ms': 10.0});
      expect(runs.first, {'ms': 10.0});
    });
    test('accepts all zero samples and the thirty percent boundary', () {
      expect(
          summarize([
            {'gc': 0},
            {'gc': 0},
            {'gc': 0}
          ]),
          {'gc': 0.0});
      expect(
          summarize([
            {'ms': 85},
            {'ms': 100},
            {'ms': 115}
          ]),
          {'ms': 100.0});
    });
    test('rejects missing repetitions and empty metrics', () {
      expect(() => summarize([]), throwsFormatException);
      expect(() => summarize([{}, {}, {}]), throwsFormatException);
      expect(
          () => summarize([
                {'ms': 1},
                {'ms': 1}
              ]),
          throwsFormatException);
      expect(() => summarize(List.filled(4, {'ms': 1})), throwsFormatException);
    });
    test('rejects mismatched metric sets', () {
      expect(
          () => summarize([
                {'ms': 1},
                {'other': 1},
                {'ms': 1}
              ]),
          throwsFormatException);
    });
    test('rejects missing nonfinite negative and nonnumeric values', () {
      final invalidValues = [null, double.nan, double.infinity, -1, '1'];
      for (final invalid in invalidValues) {
        expect(
            () => summarize([
                  {'ms': invalid},
                  {'ms': 1},
                  {'ms': 1}
                ]),
            throwsFormatException);
      }
    });
    test('rejects spread above thirty percent including zero median', () {
      expect(
          () => summarize([
                {'ms': 84},
                {'ms': 100},
                {'ms': 115}
              ]),
          throwsFormatException);
      expect(
          () => summarize([
                {'ms': 0},
                {'ms': 0},
                {'ms': 1}
              ]),
          throwsFormatException);
    });
  });
  group('bench frames', () {
    test('summarizes average and nearest rank p90 in milliseconds', () {
      final frames = [
        for (var i = 1; i <= 10; i++) BenchFrame(i * 100, i * 200, i)
      ];
      final result = summarizeFrames(frames, 60);
      expect(result[kBenchBuildMean], 0.55);
      expect(result[kBenchBuildP90], 0.9);
      expect(result[kBenchRasterMean], 1.1);
      expect(result[kBenchRasterP90], 1.8);
      expect(result[kBenchFrameCount], 10);
      expect(result[kBenchRefreshRate], 60);
      expect(result[kBenchDroppedRatio], 0);
    });
    test('counts a frame once when both threads miss the actual refresh budget',
        () {
      const frames = [BenchFrame(9000, 9000, 1), BenchFrame(1000, 9000, 2)];
      expect(summarizeFrames(frames, 60)[kBenchDroppedRatio], 0);
      expect(summarizeFrames(frames, 120)[kBenchDroppedRatio], 1);
      expect(
          summarizeFrames(
              const [BenchFrame(10000, 10000, 1)], 100)[kBenchDroppedRatio],
          0);
    });
    test('rejects empty samples invalid refresh rates and negative timings',
        () {
      expect(() => summarizeFrames([], 60), throwsFormatException);
      final invalidRates = [0.0, -1.0, double.nan, double.infinity];
      for (final hz in invalidRates) {
        expect(() => summarizeFrames(const [BenchFrame(1, 1, 0)], hz),
            throwsFormatException);
      }
      expect(() => summarizeFrames(const [BenchFrame(-1, 1, 0)], 60),
          throwsFormatException);
      expect(() => summarizeFrames(const [BenchFrame(1, -1, 0)], 60),
          throwsFormatException);
    });
  });
  group('bench timeline', () {
    test('counts only new generation starts and complete events', () {
      expect(
          countNewGenerationGc([
            {'name': 'Scavenge', 'ph': 'B'},
            {'name': 'Scavenge', 'ph': 'E'},
            {'name': 'CollectNewGeneration', 'ph': 'X'},
            {'name': 'CollectNewGeneration', 'ph': 'b'},
            {'name': 'CollectNewGeneration', 'ph': 'e'},
            {'name': 'CollectOldGeneration', 'ph': 'X'},
            {'name': 'Frame', 'ph': 'X'},
            {'ph': 'X'},
          ]),
          3);
      expect(countNewGenerationGc([]), 0);
    });
    test('sums complete and nested paired layout record events by thread', () {
      expect(
          firstFrameMillis([
            {'name': 'luckdraw.layout', 'ph': 'B', 'ts': 0, 'tid': 1},
            {'name': 'nested', 'ph': 'B', 'ts': 100, 'tid': 1},
            {'ph': 'E', 'ts': 200, 'tid': 1},
            {'name': 'luckdraw.record', 'ph': 'X', 'dur': 2000, 'tid': 2},
            {'ph': 'E', 'ts': 1000, 'tid': 1},
          ]),
          3);
      expect(
          firstFrameMillis([
            {'name': 'luckdraw.layout', 'ph': 'X', 'dur': 1000},
            {'name': 'luckdraw.record', 'ph': 'B', 'ts': 1000},
            {'ph': 'E', 'ts': 2000},
          ]),
          2);
    });
    test('rejects missing incomplete and malformed timing markers', () {
      expect(() => firstFrameMillis([]), throwsFormatException);
      expect(
          () => firstFrameMillis([
                {'name': 'luckdraw.layout', 'ph': 'X', 'dur': 1},
              ]),
          throwsFormatException);
      expect(
          () => firstFrameMillis([
                {'name': 'luckdraw.layout', 'ph': 'B', 'ts': 1},
                {'name': 'luckdraw.record', 'ph': 'X', 'dur': 1},
              ]),
          throwsFormatException);
      expect(
          () => firstFrameMillis([
                {'name': 'luckdraw.layout', 'ph': 'X', 'dur': -1},
                {'name': 'luckdraw.record', 'ph': 'X', 'dur': 1},
              ]),
          throwsFormatException);
      expect(
          () => firstFrameMillis([
                {'name': 'luckdraw.layout', 'ph': 'B', 'ts': 2},
                {'ph': 'E', 'ts': 1},
                {'name': 'luckdraw.record', 'ph': 'X', 'dur': 1},
              ]),
          throwsFormatException);
    });
  });
}
