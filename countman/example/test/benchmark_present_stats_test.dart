import 'package:flutter_test/flutter_test.dart';

import 'package:example/benchmark_present_stats.dart';

void main() {
  test('分位数覆盖空值、单值、端点、取整且不修改输入', () {
    final values = [4.0, 1.0, 3.0, 2.0];
    expect(benchPercentile([], .5), 0);
    expect(benchPercentile([7], .99), 7);
    expect(benchPercentile(values, 0), 1);
    expect(benchPercentile(values, .5), 3);
    expect(benchPercentile(values, .9), 4);
    expect(benchPercentile(values, .99), 4);
    expect(benchPercentile(values, 1), 4);
    expect(values, [4, 1, 3, 2]);
    for (final q in [-.1, 1.1, double.nan, double.infinity]) {
      expect(() => benchPercentile(values, q), throwsRangeError);
    }
  });

  Map<String, Object> stats({
    List<int> finishes = const [],
    double hz = 100,
    double baseline = 0,
    bool isBaseline = false,
    int end = 100000,
  }) => calculatePresentStats(
    rasterFinishUs: finishes,
    windowStartUs: 0,
    windowEndUs: end,
    refreshRateHz: hz,
    baselineIntervalUs: baseline,
    isBaseline: isBaseline,
  );

  test('排序、窗口边界、严格阈值与间隔分母', () {
    final input = [60001, -1, 0, 100000, 10000, 25000, 45001, 90000];
    final s = stats(finishes: input);
    expect(s, {
      'presentFps': 60.0,
      'presentFrames': 6,
      'intervalCount': 5,
      'intervalMs_p50': 15.0,
      'intervalMs_p90': 29.999,
      'intervalMs_p99': 29.999,
      'missedVsyncFrames': 2,
      'missedVsyncPct': 40.0,
      'refreshRateDetectedHz': 100.0,
      'vsyncPeriodUs': 10000.0,
      'vsyncSource': 'display.refreshRate',
    });
    expect(input.first, 60001);
  });

  test('零帧、单帧及非整数刷新率', () {
    for (final finishes in [
      <int>[],
      [100],
    ]) {
      final s = stats(finishes: finishes, hz: 59.94);
      expect(s['presentFps'], finishes.length * 10);
      expect(s['intervalCount'], 0);
      expect(s['intervalMs_p99'], 0);
      expect(s['missedVsyncPct'], 0);
      expect(s['vsyncPeriodUs'], closeTo(1000000 / 59.94, .000001));
    }
  });

  test('无刷新率时只使用空载中位间隔，组件不可自行估算', () {
    final base = stats(
      finishes: [0, 10000, 20000, 40000],
      hz: 0,
      isBaseline: true,
    );
    expect(base['vsyncSource'], 'emptyBaseline median');
    expect(base['vsyncPeriodUs'], 10000);
    expect(base['refreshRateDetectedHz'], 0);
    final loaded = stats(
      finishes: [0, 20000, 40000],
      hz: double.nan,
      baseline: 10000,
    );
    expect(loaded['missedVsyncFrames'], 2);
    expect(loaded['missedVsyncPct'], 100);
    for (final hz in [0.0, -1.0, double.nan, double.infinity]) {
      expect(() => stats(hz: hz), throwsStateError);
    }
    expect(() => stats(hz: 0, baseline: double.nan), throwsStateError);
    expect(() => stats(hz: 0, isBaseline: true), throwsStateError);
    expect(() => stats(end: 0), throwsArgumentError);
    expect(() => stats(end: -1), throwsArgumentError);
  });
}
