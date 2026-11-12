/// 沿用基准的最近秩分位数，不修改输入。
double benchPercentile(List<double> values, double q) {
  if (!q.isFinite || q < 0 || q > 1) {
    throw RangeError.value(q, 'q', '分位数须在 0 到 1 之间');
  }
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  return sorted[((sorted.length - 1) * q).round()];
}

/// 按光栅完成时间截取半开窗口；长间隔占比以相邻间隔数为分母。
Map<String, Object> calculatePresentStats({
  required List<int> rasterFinishUs,
  required int windowStartUs,
  required int windowEndUs,
  required double refreshRateHz,
  double baselineIntervalUs = 0,
  bool isBaseline = false,
}) {
  if (windowEndUs <= windowStartUs) {
    throw ArgumentError('测量窗口必须为正');
  }
  final finishes =
      rasterFinishUs
          .where((t) => t >= windowStartUs && t < windowEndUs)
          .toList()
        ..sort();
  final intervalsUs = [
    for (var i = 1; i < finishes.length; i++)
      (finishes[i] - finishes[i - 1]).toDouble(),
  ];
  final detected = refreshRateHz.isFinite && refreshRateHz > 0;
  final baseline = isBaseline
      ? benchPercentile(intervalsUs, .5)
      : baselineIntervalUs;
  if (!detected && (!baseline.isFinite || baseline <= 0)) {
    throw StateError('刷新率不可用，须先采集有效 emptyBaseline 中位间隔');
  }
  final periodUs = detected ? 1000000 / refreshRateHz : baseline;
  final missed = intervalsUs.where((t) => t > 1.5 * periodUs).length;
  return {
    'presentFps': finishes.length * 1000000 / (windowEndUs - windowStartUs),
    'presentFrames': finishes.length,
    'intervalCount': intervalsUs.length,
    'intervalMs_p50': benchPercentile(intervalsUs, .5) / 1000,
    'intervalMs_p90': benchPercentile(intervalsUs, .9) / 1000,
    'intervalMs_p99': benchPercentile(intervalsUs, .99) / 1000,
    'missedVsyncFrames': missed,
    'missedVsyncPct': intervalsUs.isEmpty
        ? 0.0
        : 100 * missed / intervalsUs.length,
    'refreshRateDetectedHz': detected ? refreshRateHz : 0.0,
    'vsyncPeriodUs': periodUs,
    'vsyncSource': detected ? 'display.refreshRate' : 'emptyBaseline median',
  };
}
