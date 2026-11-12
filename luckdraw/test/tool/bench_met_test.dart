import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/bench/metrics.dart';

/// MET 的测试场景键。
const String _wheel = 'wheel_steady';

/// 五秒 60Hz 合成窗口，测试明确区分成本和帧交付。
Map<String, Object?> _window() => {
      for (final key in kBenchFrameMetrics) key: 0.0,
      kBenchRasterP99: 8.0,
      kBenchBuildP99: 2.0,
      kBenchCombinedP99: 10.0,
      kBenchFrameCount: 300,
      'fps': kBenchDeliveryHz,
      'elapsed_micros': 5000000,
      kBenchRasterP90: kBenchBackpressureP90,
    };

/// 与合成窗口对应的非零预算，避免无关超标。
Map<String, Object?> _limits() => {
      for (final key in kBenchFrameMetrics) key: 10.0,
      kBenchRasterP90: 20.0,
    };

/// 读取指定轮的真实转盘窗口，不修改保存数据。
Map<String, Object?> _realWheel(int round) {
  final file = Directory('tool/bench/results/perf_after/wheel_default_$round')
      .listSync()
      .whereType<File>()
      .singleWhere((f) =>
          f.path.endsWith('.timeline_summary.json') &&
          !f.path.contains('reference'));
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}

/// 注册 MET 口径边界、预算政策和真实保存窗口回归。
void main() {
  group('bench MET', () {
    test('classifies exactly 15.5ms and exactly 98 percent delivery', () {
      final window = _window()..[kBenchFrameCount] = 294;
      expect(frameDeliveryRatio(window), kBenchMinimumDelivery);
      expect(frameDeliveryPassed(window), isTrue);
      expect(isBackpressureContaminated(window), isTrue);
      window[kBenchRasterP90] = kBenchBackpressureP90 - 0.001;
      expect(isBackpressureContaminated(window), isFalse);
    });
    test('never classifies 58.9fps or incomplete delivery as contamination',
        () {
      final window = _window()..['fps'] = 58.9;
      expect(frameDeliveryPassed(window), isFalse);
      expect(isBackpressureContaminated(window), isFalse);
      window['fps'] = kBenchDeliveryHz;
      window[kBenchFrameCount] = 293;
      expect(frameDeliveryPassed(window), isFalse);
      expect(isBackpressureContaminated(window), isFalse);
    });
    test('requires at least two clean windows and never hides real jank', () {
      final clean = _window()..[kBenchRasterP90] = 3.0;
      final result =
          assessScenario(_wheel, [_window(), _window(), clean], _limits());
      expect(result['status'], kBenchUncertain);
      expect(result['clean_count'], 1);
      expect(result['contaminated_count'], 2);
      final jank = {...clean, 'fps': 58.9};
      final failed = assessScenario(_wheel, [clean, clean, jank], _limits());
      expect(failed['status'], kBenchFail);
      expect(failed['delivery_passed'], isFalse);
      final windows = failed['windows']! as List<Object?>;
      expect((windows.last! as Map<String, Object?>)['classification'],
          'REAL_JANK');
    });
    test(
        'applies pass calibration and failure budget tiers including boundaries',
        () {
      final equal = assessMetric([5, 5], 5);
      expect(equal['status'], kBenchPass);
      expect(equal['calibrated'], isFalse);
      final calibrated = assessMetric([5.75, 5.75], 5, calibrate: true);
      expect(calibrated['status'], kBenchPass);
      expect(calibrated['limit'], 6.325);
      expect(calibrated['calibrated'], isTrue);
      final failed = assessMetric([5.751, 5.751], 5);
      expect(failed['status'], kBenchFail);
      expect(failed['limit'], 5);
      expect(failed['calibrated'], isFalse);
      final unstable = assessMetric([0, 5.4, 6], 5);
      expect(unstable['status'], kBenchUncertain);
      expect(unstable['limit'], 5);
      expect(unstable['calibrated'], isFalse);
    });
    test('keeps first frame informational and RSS on its FIN absolute gate',
        () {
      final result = assessScenario('wheel_first_frame', [
        for (var i = 0; i < kBenchRepetitions; i++)
          {kBenchFirstFrame: 40.378, 'fps': 22},
      ], {
        kBenchFirstFrame: 4,
        kBenchInformational: true,
        kBenchInformationReason: '缺少空白页基线',
      });
      expect(result['status'], kBenchInfo);
      expect(result['delivery_passed'], isNull);
      final metrics = result['metrics']! as Map<String, Object?>;
      expect((metrics[kBenchFirstFrame]! as Map<String, Object?>)['status'],
          kBenchInfo);
      expect(assessMetric([100, 120], 100, rss: true)['status'], kBenchFail);
      expect(assessMetric([1, 100], 100, rss: true)['status'], kBenchPass);
    });
    test('classifies saved wheel rounds two and three with complete delivery',
        () {
      final good = _realWheel(2);
      final bad = _realWheel(3);
      expect(isBackpressureContaminated(good), isFalse);
      expect(isBackpressureContaminated(bad), isTrue);
      expect(frameDeliveryPassed(good), isTrue);
      expect(frameDeliveryPassed(bad), isTrue);
      expect(good[kBenchFrameCount], 301);
      expect(bad[kBenchFrameCount], 301);
    });
    test('uses even medians and excludes contaminated costs from stability',
        () {
      final clean = _window()..[kBenchRasterP90] = 3.0;
      final other = {...clean, kBenchRasterP90: 3.2};
      final result =
          assessScenario(_wheel, [clean, other, _window()], _limits());
      expect(result['status'], kBenchPass);
      final metrics = result['metrics']! as Map<String, Object?>;
      final p90 = metrics[kBenchRasterP90]! as Map<String, Object?>;
      expect(p90['median'], 3.1);
      expect(p90['stable'], isTrue);
      expect(benchMedian([3, 1, 2]), 2);
      expect(() => benchMedian([]), throwsFormatException);
      expect(() => frameDeliveryRatio({...clean, 'elapsed_micros': 0}),
          throwsFormatException);
    });
  });
}
