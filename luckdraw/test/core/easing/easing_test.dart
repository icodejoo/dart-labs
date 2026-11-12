import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/luckdraw.dart';

/// 测试中的显式缓动集合，不在 lib 引入注册表。
const Map<String, LuckyEasing> _easings = {
  'quad': LuckyEasings.quad,
  'cubic': LuckyEasings.cubic,
  'quart': LuckyEasings.quart,
  'quint': LuckyEasings.quint,
  'sine': LuckyEasings.sine,
  'expo': LuckyEasings.expo,
  'circ': LuckyEasings.circ,
};

/// 验证每条公式在完整任务卡网格内与独立计算逐位一致。
void main() {
  group('LuckyEasings', () {
    for (final name in [
      'quad',
      'cubic',
      'quart',
      'quint',
      'sine',
      'expo',
      'circ'
    ]) {
      test('$name easeIn matches the upstream formula on a sample grid', () {
        for (final d in [2500.0, 1.0]) {
          for (final b in [0.0, 123.4]) {
            for (final c in <double>[360.0, -50.0]) {
              for (final fraction in [0.0, 0.1, 0.5, 0.9, 1.0, 1.5]) {
                final t = math.min(fraction * d, d);
                final x = t / d;
                final expected = switch (name) {
                  'quad' => c * x * x + b,
                  'cubic' => c * x * x * x + b,
                  'quart' => c * x * x * x * x + b,
                  'quint' => c * x * x * x * x * x + b,
                  'sine' => -c * math.cos(t / d * (math.pi / 2)) + c + b,
                  'expo' => t == 0 ? b : c * math.pow(2, 10 * (t / d - 1)) + b,
                  _ => -c * (math.sqrt(1 - x * x) - 1) + b,
                };
                expect(_easings[name]!.easeIn(fraction * d, b, c, d), expected,
                    reason: '$name $fraction $b $c $d');
              }
            }
          }
        }
      });
      test('$name easeOut matches the upstream formula on a sample grid', () {
        for (final outDuration in [2500.0, 1.0]) {
          for (final outStart in [0.0, 123.4]) {
            for (final outChange in <double>[360.0, -50.0]) {
              for (final outFraction in [0.0, 0.1, 0.5, 0.9, 1.0, 1.5]) {
                final t = math.min(outFraction * outDuration, outDuration);
                final x = t / outDuration;
                final y = t / outDuration - 1;
                final expected = switch (name) {
                  'quad' => -outChange * x * (x - 2) + outStart,
                  'cubic' => outChange * (y * y * y + 1) + outStart,
                  'quart' => -outChange * (y * y * y * y - 1) + outStart,
                  'quint' => outChange * (y * y * y * y * y + 1) + outStart,
                  'sine' =>
                    outChange * math.sin(t / outDuration * (math.pi / 2)) +
                        outStart,
                  'expo' => t == outDuration
                      ? outStart + outChange
                      : outChange * (-math.pow(2, -10 * t / outDuration) + 1) +
                          outStart,
                  _ => outChange * math.sqrt(1 - y * y) + outStart,
                };
                expect(
                    _easings[name]!.easeOut(outFraction * outDuration, outStart,
                        outChange, outDuration),
                    expected,
                    reason:
                        '$name $outFraction $outStart $outChange $outDuration');
              }
            }
          }
        }
      });
    }
    test('every easing clamps t to d before evaluating', () {
      for (final easing in _easings.values) {
        expect(
            easing.easeIn(150, 12, 37, 100), easing.easeIn(100, 12, 37, 100));
        expect(
            easing.easeOut(150, 12, 37, 100), easing.easeOut(100, 12, 37, 100));
      }
    });
    test('expo special-cases t == 0 and t == d like upstream', () {
      expect(LuckyEasings.expo.easeIn(0, 123.4, 360, 2500), 123.4);
      expect(LuckyEasings.expo.easeOut(2500, 123.4, 360, 2500), 123.4 + 360);
    });
    test('CurveEasing maps Curve.transform onto t b c d', () {
      const easing = CurveEasing(Curves.easeIn);
      expect(easing.easeIn(25, 10, 80, 100),
          10 + 80 * Curves.easeIn.transform(0.25));
      expect(easing.easeOut(25, 10, 80, 100),
          10 + 80 * Curves.easeIn.flipped.transform(0.25));
      const explicit = CurveEasing(Curves.easeIn, outCurve: Curves.linear);
      expect(explicit.easeOut(25, 10, 80, 100), 30);
      expect(explicit.easeIn(-1, 10, 80, 100), 10);
      expect(explicit.easeOut(200, 10, 80, 100), 90);
    });
    test('easing aliases are const and identical across accesses', () {
      expect(identical(LuckyEasings.quad, const QuadEasing()), isTrue);
      expect(identical(LuckyEasings.cubic, const CubicEasing()), isTrue);
      expect(identical(LuckyEasings.quart, const QuartEasing()), isTrue);
      expect(identical(LuckyEasings.quint, const QuintEasing()), isTrue);
      expect(identical(LuckyEasings.sine, const SineEasing()), isTrue);
      expect(identical(LuckyEasings.expo, const ExpoEasing()), isTrue);
      expect(identical(LuckyEasings.circ, const CircEasing()), isTrue);
    });
  });
}
