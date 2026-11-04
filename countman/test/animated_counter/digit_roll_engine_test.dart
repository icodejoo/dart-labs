import 'dart:math' as math;

import 'package:countman/src/widgets/animated_counter/digit_roll_engine.dart';
import 'package:countman/src/widgets/animated_counter/number_format.dart';
import 'package:countman/src/widgets/animated_counter/types.dart';
import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';

/// 把整数值按 [whole] 位拆成引擎使用的累计位值（与组件同一套规则）。
List<double> digitsOf(int value, {int whole = 1, int fraction = 0}) =>
    CounterDisplayNumber(value, fraction, null).digits(whole);

/// 重构前 `_updateCurrentDigitValues` 的逐字抄录，用作等价性基准。
List<double> legacyCompute({
  required List<double> oldDigits,
  required List<double> targetDigits,
  required double t,
  required Curve curve,
  required double baseDurationUs,
  required double totalDurationUs,
  required double staggerUs,
  required StaggerDirection direction,
  required double valueRange,
  required double autoEaseThreshold,
  required bool fast,
  Curve? Function(int)? curveForDigit,
  double Function(double, double, double)? interpolation,
}) {
  final n = oldDigits.length;
  final autoEase = curve == Curves.linear && valueRange > autoEaseThreshold;
  final effective = autoEase ? Curves.easeInOut : curve;
  final out = List<double>.filled(n, 0.0);
  final elapsedUs = t * totalDurationUs;
  for (int i = 0; i < n; i++) {
    double tDigit = t;
    if (staggerUs > 0.0 && t < 1.0) {
      final delayUs = switch (direction) {
        StaggerDirection.leftToRight => staggerUs * i,
        StaggerDirection.rightToLeft => staggerUs * (n - 1 - i),
      };
      tDigit = ((elapsedUs - delayUs) / baseDurationUs).clamp(0.0, 1.0);
    }
    final digitCurve = curveForDigit?.call(i) ?? effective;
    final progress = digitCurve.transform(tDigit);
    if (fast) {
      out[i] = progress;
      continue;
    }
    final from = oldDigits[i];
    final to = targetDigits[i];
    out[i] = interpolation != null
        ? interpolation(from, to, progress)
        : from + (to - from) * progress;
  }
  return out;
}

void main() {
  group('DigitRollEngine.settle / begin', () {
    test('settle 普通模式：端点与当前位置都落在静止数位', () {
      final e = DigitRollEngine()..settle(digitsOf(123), fast: false);
      expect(e.maxDigits, 3);
      expect(e.oldDigits, e.targetDigits);
      expect(e.currentDigits, [1.0, 12.0, 123.0]);
      expect(e.fastFromDigits, [1, 2, 3]);
      expect(e.fastToDigits, [1, 2, 3]);
      expect(e.digitsAreFast, isFalse);
    });

    test('settle fast 模式：进度全部为 1.0', () {
      final e = DigitRollEngine()..settle(digitsOf(45), fast: true);
      expect(e.currentDigits, [1.0, 1.0]);
      expect(e.digitsAreFast, isTrue);
      expect(e.fastToDigits, [4, 5]);
    });

    test('begin 把较短一侧左侧补零，并记录 fast 起止位', () {
      final e = DigitRollEngine()
        ..begin(from: digitsOf(1000), to: digitsOf(7), fast: false, unchanged: false);
      expect(e.maxDigits, 4);
      expect(e.targetDigits, [0.0, 0.0, 0.0, 7.0]);
      expect(e.currentDigits, e.oldDigits);
      expect(e.fastFromDigits, [1, 0, 0, 0]);
      expect(e.fastToDigits, [0, 0, 0, 7]);
    });

    test('begin 列数只增不减', () {
      final e = DigitRollEngine()
        ..begin(from: digitsOf(1000), to: digitsOf(7), fast: false, unchanged: false)
        ..begin(from: digitsOf(7), to: digitsOf(8), fast: false, unchanged: false);
      expect(e.maxDigits, 4);
      expect(e.oldDigits.length, 4);
    });

    test('begin fast：起止相同直接 1.0，否则从 0 起', () {
      final changed = DigitRollEngine()
        ..begin(from: digitsOf(10), to: digitsOf(99), fast: true, unchanged: false);
      expect(changed.currentDigits, [0.0, 0.0]);
      final same = DigitRollEngine()
        ..begin(from: digitsOf(10), to: digitsOf(10), fast: true, unchanged: true);
      expect(same.currentDigits, [1.0, 1.0]);
    });

    test('swapEndpoints 同时交换普通与 fast 两套端点', () {
      final e = DigitRollEngine()
        ..begin(from: digitsOf(12), to: digitsOf(34), fast: false, unchanged: false);
      final oldBefore = List<double>.of(e.oldDigits);
      final targetBefore = List<double>.of(e.targetDigits);
      e.swapEndpoints();
      expect(e.oldDigits, targetBefore);
      expect(e.targetDigits, oldBefore);
      expect(e.fastFromDigits, [3, 4]);
      expect(e.fastToDigits, [1, 2]);
    });
  });

  group('DigitRollEngine.displayProgress', () {
    test('未建列时返回 null', () {
      expect(DigitRollEngine().displayProgress(0.3), isNull);
    });

    test('普通模式按个位列走过的比例还原', () {
      final e = DigitRollEngine()
        ..begin(from: digitsOf(0), to: digitsOf(10), fast: false, unchanged: false);
      e.currentDigits[1] = 4.0; // 个位走了 4/10
      expect(e.displayProgress(0.9), closeTo(0.4, 1e-12));
    });

    test('普通模式跨度为零时回退到传入的 t', () {
      final e = DigitRollEngine()
        ..begin(from: digitsOf(5), to: digitsOf(5), fast: false, unchanged: true);
      expect(e.displayProgress(0.7), 0.7);
    });

    test('fast 模式直接取进度并钳制到 0–1', () {
      final e = DigitRollEngine()
        ..begin(from: digitsOf(1), to: digitsOf(9), fast: true, unchanged: false);
      e.currentDigits[0] = 1.5;
      expect(e.displayProgress(0), 1.0);
    });
  });

  group('DigitRollEngine.compute', () {
    DigitRollEngine prepared(int from, int to, {required bool fast, int whole = 1}) =>
        DigitRollEngine()
          ..begin(
              from: digitsOf(from, whole: whole),
              to: digitsOf(to, whole: whole),
              fast: fast,
              unchanged: from == to);

    void compute(DigitRollEngine e, double t,
        {bool fast = false,
        Curve curve = Curves.linear,
        double staggerUs = 0,
        StaggerDirection direction = StaggerDirection.rightToLeft,
        double range = 0,
        double threshold = 100000,
        Curve? Function(int)? curveForDigit,
        double Function(double, double, double)? interpolation}) {
      e.compute(
        t: t,
        curve: curve,
        baseDurationUs: 1000000,
        totalDurationUs: 1000000 + staggerUs * (e.maxDigits - 1),
        staggerUs: staggerUs,
        direction: direction,
        valueRange: range,
        autoEaseThreshold: threshold,
        fast: fast,
        curveForDigit: curveForDigit,
        interpolation: interpolation,
      );
    }

    test('普通递增：个位携带整个数值，高位为 值/10^位 取整后的累计位', () {
      final e = prepared(0, 99, fast: false);
      compute(e, 0.5);
      expect(e.currentDigits[1], closeTo(49.5, 1e-9));
      expect(e.currentDigits[0], closeTo(4.5, 1e-9));
      compute(e, 1.0);
      expect(e.currentDigits, [9.0, 99.0]);
    });

    test('普通递减：位置向下单调', () {
      final e = prepared(90, 10, fast: false);
      compute(e, 0.5);
      expect(e.currentDigits[1], closeTo(50.0, 1e-9));
      expect(e.currentDigits[0], closeTo(5.0, 1e-9));
    });

    test('fast：各列只携带 0–1 进度', () {
      final e = prepared(1000, 9999, fast: true);
      compute(e, 0.25, fast: true);
      expect(e.currentDigits, everyElement(closeTo(0.25, 1e-12)));
      compute(e, 1.0, fast: true);
      expect(e.currentDigits, everyElement(1.0));
    });

    test('错峰 rightToLeft：个位先动，最高位最晚', () {
      final e = prepared(0, 999, fast: true, whole: 3);
      compute(e, 0.3, fast: true, staggerUs: 400000);
      // 总时长 1.8s，t=0.3 → 已过 0.54s；个位延迟 0，十位 0.4s，百位 0.8s。
      expect(e.currentDigits[2], closeTo(0.54, 1e-9));
      expect(e.currentDigits[1], closeTo(0.14, 1e-9));
      expect(e.currentDigits[0], 0.0);
    });

    test('错峰 leftToRight：最高位先动', () {
      final e = prepared(0, 999, fast: true, whole: 3);
      compute(e, 0.3, fast: true, staggerUs: 400000, direction: StaggerDirection.leftToRight);
      expect(e.currentDigits[0], closeTo(0.54, 1e-9));
      expect(e.currentDigits[1], closeTo(0.14, 1e-9));
      expect(e.currentDigits[2], 0.0);
    });

    test('t 到终点时错峰不再折算，各列一律到位', () {
      final e = prepared(0, 999, fast: true, whole: 3);
      compute(e, 1.0, fast: true, staggerUs: 400000);
      expect(e.currentDigits, everyElement(1.0));
    });

    test('autoEase：线性且跨度超阈值时改用 easeInOut', () {
      final linear = prepared(0, 5, fast: true);
      final eased = prepared(0, 5, fast: true);
      compute(linear, 0.25, fast: true, range: 10, threshold: 100000);
      compute(eased, 0.25, fast: true, range: 200000, threshold: 100000);
      expect(linear.currentDigits.first, closeTo(0.25, 1e-12));
      expect(eased.currentDigits.first, closeTo(Curves.easeInOut.transform(0.25), 1e-12));
      // 非线性曲线不触发 autoEase。
      final custom = prepared(0, 5, fast: true);
      compute(custom, 0.25, fast: true, curve: Curves.easeOut, range: 200000);
      expect(custom.currentDigits.first, closeTo(Curves.easeOut.transform(0.25), 1e-12));
    });

    test('curveForDigit 逐位覆盖整体曲线，返回 null 时回退', () {
      final e = prepared(0, 99, fast: true, whole: 2);
      compute(e, 0.5, fast: true,
          curveForDigit: (i) => i == 0 ? Curves.easeIn : null);
      expect(e.currentDigits[0], closeTo(Curves.easeIn.transform(0.5), 1e-12));
      expect(e.currentDigits[1], closeTo(0.5, 1e-12));
    });

    test('interpolation 自定义插值只作用于普通模式', () {
      final e = prepared(0, 9, fast: false);
      compute(e, 0.5, interpolation: (from, to, t) => to * t * t);
      expect(e.currentDigits[0], closeTo(9 * 0.25, 1e-12));
    });

    test('位数变化时重分配缓冲，其余帧复用同一列表', () {
      final e = prepared(0, 99, fast: false);
      e.currentDigits = <double>[0];
      compute(e, 0.5);
      expect(e.currentDigits.length, 2);
      final buffer = e.currentDigits;
      compute(e, 0.6);
      expect(identical(e.currentDigits, buffer), isTrue);
    });

    test('与重构前实现逐位一致：普通/fast × 递增/递减 × 错峰 × 全 9 目标', () {
      final cases = <(int, int)>[
        (0, 9), (0, 99), (0, 999), (0, 9999), (1000, 7), (9999, 0), (123, 456),
        (456, 123), (5, 5), (0, 100000),
      ];
      final curves = <Curve>[Curves.linear, Curves.easeOut, Curves.easeInOutCubic];
      for (final (from, to) in cases) {
        final whole = math.max(from.toString().length, to.toString().length);
        for (final fast in [false, true]) {
          for (final curve in curves) {
            for (final stagger in [0.0, 120000.0, 400000.0]) {
              for (final dir in StaggerDirection.values) {
                final e = prepared(from, to, fast: fast, whole: whole);
                final range = (to - from).abs().toDouble();
                for (final t in [0.0, 0.1, 0.37, 0.5, 0.83, 1.0]) {
                  final total = 1000000 + stagger * (e.maxDigits - 1);
                  e.compute(
                    t: t, curve: curve, baseDurationUs: 1000000,
                    totalDurationUs: total, staggerUs: stagger, direction: dir,
                    valueRange: range, autoEaseThreshold: 50000, fast: fast,
                  );
                  final expected = legacyCompute(
                    oldDigits: e.oldDigits, targetDigits: e.targetDigits, t: t,
                    curve: curve, baseDurationUs: 1000000, totalDurationUs: total,
                    staggerUs: stagger, direction: dir, valueRange: range,
                    autoEaseThreshold: 50000, fast: fast,
                  );
                  expect(e.currentDigits, expected,
                      reason: '$from→$to fast=$fast $curve stagger=$stagger $dir t=$t');
                }
              }
            }
          }
        }
      }
    });
  });

  group('DigitBounce', () {
    DigitBounce make({double overshoot = 0.3, double stagger = 0, int n = 3,
            StaggerDirection dir = StaggerDirection.rightToLeft}) =>
        DigitBounce(overshoot: overshoot, staggerUs: stagger,
            baseDurationUs: 1000000, direction: dir, digitCount: n);

    test('时间轴总长 = 最后一列滚动结束 + 一次回弹', () {
      expect(make().totalUs, 1000000 + DigitBounce.bounceUs);
      expect(make(stagger: 100000).totalUs, 1000000 + 200000 + DigitBounce.bounceUs);
    });

    test('maxFraction 等于 tanh(overshoot)', () {
      final b = make(overshoot: 0.5);
      final ex2 = math.exp(1.0);
      expect(b.maxFraction, closeTo((ex2 - 1) / (ex2 + 1), 1e-12));
    });

    test('每列只在自己滚动结束后的回弹窗口内非零，峰值在窗口中点', () {
      final b = make(n: 1);
      final out = List<double>.filled(1, 0);
      b.fill(out, 0.0);
      expect(out[0], 0.0);
      b.fill(out, 1000000 / b.totalUs); // 刚好滚动结束
      expect(out[0], 0.0);
      b.fill(out, (1000000 + DigitBounce.bounceUs / 2) / b.totalUs);
      expect(out[0], closeTo(b.maxFraction, 1e-9));
      b.fill(out, 1.0);
      expect(out[0], 0.0);
    });

    test('错峰使各列回弹相位错开', () {
      final b = make(stagger: 200000, n: 2);
      final out = List<double>.filled(2, 0);
      // 个位（索引 1）延迟 0，滚动在 1.0s 结束；十位（索引 0）在 1.2s 结束。
      b.fill(out, (1000000 + 175000) / b.totalUs);
      expect(out[1], closeTo(b.maxFraction, 1e-9));
      expect(out[0], 0.0);
    });
  });
}
