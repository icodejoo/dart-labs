// `CubicBezier.transform` 的求解精度与稳健性：对照 80 次二分的参考解，覆盖
// 真实 SVGator CSS 样本里出现过的全部曲线、CSS 关键字曲线与会让纯牛顿迭代
// 发散的边界曲线；另检查单调性、端点、线性快路径与"不产生 NaN/Infinity"。

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/smil_animation.dart';

/// 与参考解允许的最大误差（y 方向）。
const double _tolerance = 1e-5;

/// 参考解的二分次数，足以收敛到双精度极限。
const int _referenceIterations = 80;

/// 均匀网格的分段数：t = i / _gridSteps，共 _gridSteps + 1 个点。
const int _gridSteps = 2000;

/// 端点允许的数值误差。
const double _endpointSlack = 1e-9;

/// 单调性断言允许的浮点抖动。
const double _monotoneSlack = 1e-9;

/// 随机稳健性测试的固定种子。
const int _randomSeed = 20261103;

/// 真实 SVGator CSS 导出样本里出现过的 42 条去重曲线，格式 `[x1, y1, x2, y2]`。
const List<List<double>> _corpusCurves = [
  [0, 0, 0.075, 0.99],
  [0, 0, 0.255, 1],
  [0, 0, 0.58, 1],
  [0.005, 0.655, 0.32, 1.275],
  [0.075, 0.82, 0.165, 1],
  [0.08, 1.5, 0.32, 2.27],
  [0.165, 0.84, 0.44, 1],
  [0.175, 0.885, 0.32, 1.275],
  [0.175, 0.885, 0.4, 1.275],
  [0.215, 0.61, 0.355, 1],
  [0.23, 1, 0.32, 1],
  [0.25, 0.46, 0.45, 0.94],
  [0.25, 1, 0.25, 1],
  [0.26, 0.46, 0.995, 1],
  [0.271647, 0.516115, 0.573982, 0.942651],
  [0.293242, 0.419646, 0.537104, 0.953543],
  [0.295778, 0.542165, 0.623774, 0.905456],
  [0.315704, 0, 0.682506, 0.465055],
  [0.365, 0, 0.1, 0.995],
  [0.39, 0.575, 0.565, 1],
  [0.415, 0.08, 0.115, 0.955],
  [0.42, 0, 0.38, 1],
  [0.42, 0, 0.58, 1],
  [0.42, 0, 1, 1],
  [0.435, 0.145, 0.57, 0.855],
  [0.44, 0.015, 0.46, 0.99],
  [0.445, 0.05, 0.55, 0.95],
  [0.455, 0.03, 0.515, 0.955],
  [0.47, 0, 0.745, 0.715],
  [0.55, 0.055, 0.675, 0.19],
  [0.55, 0.085, 0.68, 0.53],
  [0.558732, 0.459376, 1, 1],
  [0.6, -0.28, 0.735, 0.045],
  [0.6, 0.04, 0.98, 0.335],
  [0.645, 0.045, 0.355, 1],
  [0.68, -0.275, 0.825, 0.115],
  [0.68, -0.55, 0.265, 1.55],
  [0.77, 0, 0.175, 1],
  [0.785, 0.135, 0.15, 0.86],
  [0.86, 0, 0.07, 1],
  [0.99, -0.105, 0.58, 1],
  [1, 0, 0, 1],
];

/// 样本之外补充的曲线：CSS 关键字、对称/回弹曲线，以及 x 导数在端点或中点
/// 退化为 0 的边界曲线（纯牛顿迭代在这些曲线上会发散）。
const List<List<double>> _extraCurves = [
  [0.25, 0.1, 0.25, 1], // ease
  [0.9, 0, 0.1, 1],
  [0, 1, 1, 0],
  [1, 1, 0, 0],
  [0.68, -0.55, 0.27, 1.55],
  [0, 0, 0, 1],
  [1, 0, 1, 1],
];

/// 全部待测曲线。
final List<List<double>> _allCurves = [..._corpusCurves, ..._extraCurves];

/// 把 `[x1, y1, x2, y2]` 转成 [CubicBezier]。
CubicBezier _curve(List<double> p) => CubicBezier(p[0], p[1], p[2], p[3]);

/// 曲线的可读名字，用于断言信息。
String _name(List<double> p) => 'cubic-bezier(${p.join(', ')})';

/// 三次贝塞尔某一分量在参数 [s] 处的值（Bernstein 形式，独立于被测实现）。
double _bezier(double p1, double p2, double s) {
  final u = 1 - s;
  return 3 * u * u * s * p1 + 3 * u * s * s * p2 + s * s * s;
}

/// 参考解：x(s)=[t] 用 80 次二分求 s，再取 y(s)。仅适用于 x1、x2 在 `[0, 1]`
/// 内（x(s) 单调）的曲线。
double _reference(List<double> p, double t) {
  var lo = 0.0;
  var hi = 1.0;
  for (var i = 0; i < _referenceIterations; i++) {
    final mid = (lo + hi) / 2;
    if (_bezier(p[0], p[2], mid) < t) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return _bezier(p[1], p[3], (lo + hi) / 2);
}

/// 均匀网格加靠近 0 与 1 的点，共 `_gridSteps + 1 + 28` 个，含 0 和 1。
List<double> _samplePoints() {
  final points = <double>[for (var i = 0; i <= _gridSteps; i++) i / _gridSteps];
  for (var k = 3; k <= 9; k++) {
    final eps = math.pow(10, -k).toDouble();
    points
      ..add(eps)
      ..add(2 * eps)
      ..add(1 - eps)
      ..add(1 - 2 * eps);
  }
  return points;
}

/// x1、x2、y1、y2 全在 `[0, 1]` 内（输出应当单调不减）的曲线。
bool _isUnitCurve(List<double> p) => p.every((v) => v >= 0 && v <= 1);

void main() {
  group('CubicBezier.transform 对照二分参考解', () {
    test('全部曲线在全部采样点上最大误差 <= 1e-5', () {
      final points = _samplePoints();
      expect(points.length, greaterThanOrEqualTo(2000));
      final failures = <String>[];
      var worstOverall = 0.0;
      for (final p in _allCurves) {
        final curve = _curve(p);
        var worst = 0.0;
        var worstT = 0.0;
        for (final t in points) {
          final err = (curve.transform(t) - _reference(p, t)).abs();
          if (err > worst) {
            worst = err;
            worstT = t;
          }
        }
        if (worst > worstOverall) worstOverall = worst;
        if (worst > _tolerance) {
          failures.add('${_name(p)} 最大误差 $worst @ t=$worstT');
        }
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
      expect(worstOverall, lessThanOrEqualTo(_tolerance));
    });

    test('回归：(1,0,0,1) 修复前在 t≈0.4997 误差高达 8.57e3', () {
      // 该曲线 x(s) 在 s=0.5 处是三重根（导数为 0），修复前的牛顿迭代一步就
      // 飞出 [0, 1]，t∈[0.456, 0.544] 一带输出垃圾值，最大误差 8.57e3
      // （乘以段位移后元素会飞出画面）。真实样本里这条曲线出现过 14 次。
      const p = [1.0, 0.0, 0.0, 1.0];
      final curve = _curve(p);
      for (final t in [0.4563, 0.4997, 0.5, 0.5003, 0.5436]) {
        final y = curve.transform(t);
        expect(y, inInclusiveRange(-1e-6, 1 + 1e-6), reason: 't=$t y=$y');
        expect((y - _reference(p, t)).abs(), lessThanOrEqualTo(_tolerance));
      }
    });

    test('回归：(0,0,.075,.99) 起点导数为 0，修复前 t∈[0.0001, 0.0101] 误差达 1.6e-2', () {
      const p = [0.0, 0.0, 0.075, 0.99];
      final curve = _curve(p);
      for (var t = 0.0001; t <= 0.0101; t += 0.0001) {
        expect(
          (curve.transform(t) - _reference(p, t)).abs(),
          lessThanOrEqualTo(_tolerance),
          reason: 't=$t',
        );
      }
    });
  });

  group('CubicBezier.transform 单调性', () {
    test('(1,0,0,1) 在 t∈[0.4, 0.6] 上落在 [0, 1] 内且单调不减', () {
      final curve = _curve([1, 0, 0, 1]);
      var prev = double.negativeInfinity;
      for (var i = 0; i <= 2000; i++) {
        final t = 0.4 + 0.2 * i / 2000;
        final y = curve.transform(t);
        expect(y, inInclusiveRange(-1e-6, 1 + 1e-6), reason: 't=$t');
        expect(y, greaterThanOrEqualTo(prev - _monotoneSlack), reason: 't=$t');
        prev = y;
      }
    });

    test('x1、x2、y1、y2 都在 [0, 1] 的曲线输出单调不减', () {
      final unitCurves = _allCurves.where(_isUnitCurve).toList();
      expect(unitCurves.length, greaterThan(20), reason: '样本应覆盖足够多的曲线');
      final failures = <String>[];
      for (final p in unitCurves) {
        final curve = _curve(p);
        var prev = double.negativeInfinity;
        for (var i = 0; i <= _gridSteps; i++) {
          final y = curve.transform(i / _gridSteps);
          if (y < prev - _monotoneSlack) {
            failures.add('${_name(p)} 在 t=${i / _gridSteps} 回落: $prev -> $y');
            break;
          }
          prev = y;
        }
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
    });
  });

  group('CubicBezier.transform 端点与快路径', () {
    test('t=0 返回 0，t=1 返回 1（任意曲线）', () {
      for (final p in _allCurves) {
        final curve = _curve(p);
        expect(
          curve.transform(0),
          closeTo(0, _endpointSlack),
          reason: _name(p),
        );
        expect(
          curve.transform(1),
          closeTo(1, _endpointSlack),
          reason: _name(p),
        );
      }
    });

    test('t 越出 [0, 1] 时钳到端点值', () {
      final curve = _curve([0.42, 0, 0.58, 1]);
      expect(curve.transform(-0.25), closeTo(0, _endpointSlack));
      expect(curve.transform(1.25), closeTo(1, _endpointSlack));
    });

    test('线性曲线 (0,0,1,1) 走快路径，原样返回 t', () {
      const linear = CubicBezier(0, 0, 1, 1);
      for (final t in [0.0, 0.1, 0.25, 0.5, 0.75, 0.999, 1.0]) {
        expect(linear.transform(t), t);
      }
    });

    test('y 不被钳制：回弹曲线可以输出越出 [0, 1] 的值', () {
      final curve = _curve([0.68, -0.55, 0.265, 1.55]);
      var min = double.infinity;
      var max = double.negativeInfinity;
      for (var i = 0; i <= _gridSteps; i++) {
        final y = curve.transform(i / _gridSteps);
        min = math.min(min, y);
        max = math.max(max, y);
      }
      expect(min, lessThan(-0.01), reason: '起步应先向反方向回拉');
      expect(max, greaterThan(1.01), reason: '收尾应冲过终点再回落');
    });
  });

  group('CubicBezier.transform 稳健性', () {
    test('随机曲线（含 x 超出 [0, 1]）与随机 t 不抛异常、不产生 NaN/Infinity', () {
      final rnd = math.Random(_randomSeed);
      double range(double lo, double hi) => lo + (hi - lo) * rnd.nextDouble();
      for (var k = 0; k < 3000; k++) {
        final p = [
          range(-1.5, 2.5),
          range(-3, 4),
          range(-1.5, 2.5),
          range(-3, 4),
        ];
        final curve = _curve(p);
        final ts = <double>[
          0,
          1,
          for (var i = 0; i < 40; i++) rnd.nextDouble(),
        ];
        for (final t in ts) {
          final y = curve.transform(t);
          expect(y.isFinite, isTrue, reason: '${_name(p)} t=$t y=$y');
        }
      }
    });

    test('x 在 [0, 1] 内的随机曲线与参考解误差 <= 1e-5', () {
      // 随机曲线补充固定清单之外的覆盖：x1、x2 在 [0, 1]，y 含回弹范围。
      final rnd = math.Random(_randomSeed);
      double range(double lo, double hi) => lo + (hi - lo) * rnd.nextDouble();
      for (var k = 0; k < 1500; k++) {
        final p = [range(0, 1), range(-1, 2.5), range(0, 1), range(-1, 2.5)];
        final curve = _curve(p);
        for (var i = 0; i < 40; i++) {
          final t = rnd.nextDouble();
          expect(
            (curve.transform(t) - _reference(p, t)).abs(),
            lessThanOrEqualTo(_tolerance),
            reason: '${_name(p)} t=$t',
          );
        }
      }
    });
  });
}
