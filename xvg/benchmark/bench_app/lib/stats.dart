// Small percentile/summary helper shared by the frame-timing and parse-timing
// collectors.
//
// 帧耗时/解析耗时统计共用的小型分位数汇总工具。

/// Summary statistics (avg/p50/p90/p99/max) over a set of microsecond
/// durations.
///
/// 一组微秒级耗时的汇总统计（avg/p50/p90/p99/max）。
class DurationStats {
  /// Computes stats from raw sample durations. / 由原始样本耗时计算统计量。
  factory DurationStats.fromDurations(List<Duration> samples) {
    if (samples.isEmpty) {
      return const DurationStats._(
        count: 0,
        avgUs: 0,
        p50Us: 0,
        p90Us: 0,
        p99Us: 0,
        maxUs: 0,
      );
    }
    final us = samples.map((d) => d.inMicroseconds).toList()..sort();
    double pct(double p) {
      final idx = ((us.length - 1) * p).round();
      return us[idx].toDouble();
    }

    final avg = us.reduce((a, b) => a + b) / us.length;
    return DurationStats._(
      count: us.length,
      avgUs: avg,
      p50Us: pct(0.50),
      p90Us: pct(0.90),
      p99Us: pct(0.99),
      maxUs: us.last.toDouble(),
    );
  }

  const DurationStats._({
    required this.count,
    required this.avgUs,
    required this.p50Us,
    required this.p90Us,
    required this.p99Us,
    required this.maxUs,
  });

  /// Sample count. / 样本数。
  final int count;

  /// Average in microseconds. / 均值（微秒）。
  final double avgUs;

  /// 50th percentile in microseconds. / p50（微秒）。
  final double p50Us;

  /// 90th percentile in microseconds. / p90（微秒）。
  final double p90Us;

  /// 99th percentile in microseconds. / p99（微秒）。
  final double p99Us;

  /// Max in microseconds. / 最大值（微秒）。
  final double maxUs;

  String get _ms =>
      'avg=${(avgUs / 1000).toStringAsFixed(3)}ms '
      'p50=${(p50Us / 1000).toStringAsFixed(3)}ms '
      'p90=${(p90Us / 1000).toStringAsFixed(3)}ms '
      'p99=${(p99Us / 1000).toStringAsFixed(3)}ms '
      'max=${(maxUs / 1000).toStringAsFixed(3)}ms '
      '(n=$count)';

  @override
  String toString() => _ms;
}
