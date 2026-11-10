import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/bench/metrics.dart';

/// MET2 的合成场景键。
const String _scene = 'wheel_steady';

/// 创建交付完整且满足硬门禁的合成窗口，仅用于边界测试。
Map<String, Object?> _window() => {
      for (final key in kBenchFrameMetrics) key: 0.0,
      kBenchFrameCount: 300,
      kBenchFps: kBenchDeliveryHz,
      kBenchElapsed: 5000000,
      kBenchRasterP99: 8.0,
      kBenchBuildP99: kBenchBuildP99Limit,
      kBenchCombinedP99: kBenchCombinedP99Limit,
    };

/// 合成非零成本预算，比例和 GC 仍严格限制。
Map<String, Object?> _limits() => {
      for (final key in kBenchFrameMetrics) key: 5.0,
      kBenchDroppedRatio: 0.005,
      kBenchExtraGc: 0.0,
    };

/// 从真实评估结果取指定场景，不修改保存数据。
Map<String, Object?> _savedScene(String name) {
  final root = jsonDecode(
          File('tool/bench/results/met2/assessment.json').readAsStringSync())
      as Map<String, Object?>;
  return (root['scenarios']! as Map<String, Object?>)[name]!
      as Map<String, Object?>;
}

/// 注册分类型稳定性、冻结预算与独立硬门禁的 MET2 回归。
void main() {
  group('bench MET2', () {
    test('uses one percentage point absolute spread for near zero ratios', () {
      expect(benchStable([0, 1 / 301], ratio: true), isTrue);
      expect(benchStable([0, 0.01], ratio: true), isTrue);
      expect(benchStable([0, 0.010001], ratio: true), isFalse);
      expect(benchStable([0.9, 0.92], ratio: true), isFalse);
      expect(benchStable([], ratio: true), isFalse);
    });
    test('uses absolute small time tolerance and relative time byte tolerance',
        () {
      expect(benchStable([0, 0.15]), isTrue);
      expect(benchStable([0, 0.150001]), isFalse);
      expect(benchStable([0.425, 0.575]), isTrue);
      expect(benchStable([0.424, 0.576]), isFalse);
      expect(benchStable([85, 115], millis: false), isTrue);
      expect(benchStable([84, 116], millis: false), isFalse);
      expect(benchStable([0, 0.1], millis: false), isFalse);
    });
    test('calibrates stable measured costs without a fifteen percent cutoff',
        () {
      final row = assessMetric([1.4, 1.4], 1, calibrate: true, designTarget: 1);
      expect(row[kBenchLimit], 1.54);
      expect(row[kBenchDesignGap], closeTo(0.4, 1e-9));
      expect(row[kBenchDesignStatus], kBenchCalibratedDesign);
      expect(row[kBenchStatus], kBenchPass);
      expect(assessMetric([1.4, 1.4], 1)[kBenchStatus], kBenchFail);
    });
    test('keeps evidenced floors and rounds only measured time budgets', () {
      final row =
          assessMetric([1.01, 1.01], 1, calibrate: true, calibratedFloor: 1.2);
      expect(row[kBenchLimit], 1.2);
      expect(
          assessMetric([1.001, 1.001], 1, calibrate: true)[kBenchLimit], 1.102);
      final ratio =
          assessMetric([0, 0.01], 0.004, ratio: true, calibrate: true);
      expect(ratio[kBenchLimit], 0.004);
      expect(ratio[kBenchStatus], kBenchFail);
      final gc = assessMetric([1, 1], 0, millis: false, calibrate: true);
      expect(gc[kBenchStatus], kBenchFail);
      expect(gc[kBenchDesignGap], isNull);
    });
    test(
        'marks unstable or insufficient clean samples uncertain without tuning',
        () {
      final row = assessMetric([1, 2], 1, calibrate: true);
      expect(row[kBenchStatus], kBenchUncertain);
      expect(row[kBenchLimit], 1);
      expect(row[kBenchCalibrated], isFalse);
      expect(
          assessMetric([1], 1, calibrate: true)[kBenchStatus], kBenchUncertain);
      expect(assessMetric([], 1)[kBenchDesignGap], isNull);
    });
    test('enforces per window p99 boundaries without median masking', () {
      final good = _window();
      expect(
          assessScenario(_scene, [good, good, good], _limits())[kBenchStatus],
          kBenchPass);
      for (final key in [kBenchCombinedP99, kBenchBuildP99]) {
        final bad = {...good, key: (good[key]! as double) + 0.001};
        expect(
            assessScenario(_scene, [good, good, bad], _limits())[kBenchStatus],
            kBenchFail);
      }
    });
    test('excludes contaminated p99 but never ignores delivery failure', () {
      final good = _window();
      final polluted = {
        ...good,
        kBenchRasterP90: kBenchBackpressureP90,
        kBenchCombinedP99: 20.0,
        kBenchBuildP99: 8.0,
      };
      expect(
          assessScenario(
              _scene, [good, good, polluted], _limits())[kBenchStatus],
          kBenchPass);
      final bad = {...polluted, kBenchFps: 58.9};
      expect(assessScenario(_scene, [good, good, bad], _limits())[kBenchStatus],
          kBenchFail);
    });
    test('rejects missing or invalid hard gate evidence', () {
      for (final key in [kBenchBuildP99, kBenchCombinedP99]) {
        for (final value in [null, -1, double.infinity]) {
          final bad = {..._window(), key: value};
          expect(() => assessScenario(_scene, [bad, bad, bad], _limits()),
              throwsFormatException);
        }
      }
    });
    test('retains initial design gaps independently of scenario hard failures',
        () {
      final lotto = _savedScene('lotto_draw');
      expect(lotto[kBenchStatus], kBenchFail);
      final metrics = lotto[kBenchMetrics]! as Map<String, Object?>;
      final build = metrics[kBenchBuildMean]! as Map<String, Object?>;
      expect(build[kBenchDesignTarget], 1.5);
      expect(build[kBenchDesignGap], closeTo(0.4791899827, 1e-8));
      expect(build[kBenchStatus], kBenchPass);
      expect(build[kBenchDesignStatus], kBenchCalibratedDesign);
    });
    test('reproduces saved hard failures and remaining raster uncertainty', () {
      for (final scene in ['grid_steady', 'slot_raster', 'lotto_draw']) {
        expect(_savedScene(scene)[kBenchStatus], kBenchFail);
      }
      expect(_savedScene('lots_shaking')[kBenchStatus], kBenchUncertain);
      expect(_savedScene('wheel_first_frame')[kBenchStatus], kBenchInfo);
      expect(_savedScene('wheel_steady')[kBenchStatus], kBenchPass);
    });
  });
}
