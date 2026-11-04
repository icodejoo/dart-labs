import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:countman/src/widgets/animated_counter/digit_column.dart';
import 'package:countman/src/widgets/animated_counter/digit_motion.dart';
import 'package:countman/src/widgets/animated_counter/types.dart';
import 'package:countman/src/widgets/painter/counter_painter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _cellW = 20.0;
const _cellH = 30.0;
const _ink = Color(0xFF000000);

/// 把 Canvas 的变换调用折算成矩阵，并记录每次 drawParagraph 的完整变换。
class _MatrixCanvas implements Canvas {
  Matrix4 m = Matrix4.identity();
  final _stack = <Matrix4>[];

  /// 每次绘制时「段落原点 → 画布」的完整矩阵，按绘制顺序排列。
  final draws = <Matrix4>[];

  @override
  void save() => _stack.add(m.clone());

  @override
  void saveLayer(Rect? bounds, Paint paint) => _stack.add(m.clone());

  @override
  void restore() => m = _stack.removeLast();

  @override
  void translate(double dx, double dy) => m.translateByDouble(dx, dy, 0, 1);

  @override
  void scale(double sx, [double? sy]) =>
      m.multiply(Matrix4.diagonal3Values(sx, sy ?? sx, 1));

  @override
  void rotate(double radians) => m.rotateZ(radians);

  @override
  void transform(Float64List matrix4) => m.multiply(Matrix4.fromFloat64List(matrix4));

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) {
    draws.add(m.clone()..translateByDouble(offset.dx, offset.dy, 0, 1));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 记录每次 paragraphFor 的 (数位, 透明度)，其余行为不变。
class _ProbePainter extends CounterPainter {
  _ProbePainter({
    required super.transition,
    required super.flipDirection,
    required super.increasing,
  }) : super(
          repaint: ValueNotifier<int>(0),
          digitValues: const <double>[0],
          style: const TextStyle(fontSize: 20, color: _ink),
          digitSize: const Size(_cellW, _cellH),
          fractionDigits: 0,
          groupingPattern: const [3],
          hideLeadingZeroes: false,
          numeralSystem: NumeralSystem.latin,
          fast: true,
          fastFrom: const [3],
          fastTo: const [4],
        );

  final probes = <(int, double)>[];

  @override
  ui.Paragraph paragraphFor(int digit, double alpha) {
    probes.add((digit, alpha));
    return super.paragraphFor(digit, alpha);
  }
}

/// 从相对基线的变换里取出的可比数值。
class _Delta {
  _Delta(Matrix4 now, Matrix4 rest) {
    final inv = Matrix4.copy(rest)..invert();
    final g = now.multiplied(inv);
    tx = g.storage[12];
    ty = g.storage[13];
    angle = math.atan2(g.storage[1], g.storage[0]);
    scale = math.sqrt(g.storage[0] * g.storage[0] + g.storage[1] * g.storage[1]);
  }

  late final double tx, ty, angle, scale;
}

void main() {
  group('resolveDigitMotion 数值', () {
    final m = DigitMotion();

    void solve(CounterTransition t, AxisDirection d, double p, bool leaving) =>
        resolveDigitMotion(m,
            transition: t, direction: d, p: p, leaving: leaving,
            width: _cellW, height: _cellH);

    test('slide 垂直：up 离场向上、入场从下方进入', () {
      solve(CounterTransition.slide, AxisDirection.up, 0.25, true);
      expect(m.dy, closeTo(-0.25 * _cellH, 1e-9));
      expect(m.dx, 0);
      solve(CounterTransition.slide, AxisDirection.up, 0.25, false);
      expect(m.dy, closeTo(0.75 * _cellH, 1e-9));
    });

    test('slide 垂直：down 方向相反', () {
      solve(CounterTransition.slide, AxisDirection.down, 0.25, true);
      expect(m.dy, closeTo(0.25 * _cellH, 1e-9));
      solve(CounterTransition.slide, AxisDirection.down, 0.25, false);
      expect(m.dy, closeTo(-0.75 * _cellH, 1e-9));
    });

    test('slide 水平：right 离场向右、left 离场向左', () {
      solve(CounterTransition.slide, AxisDirection.right, 0.5, true);
      expect(m.dx, closeTo(0.5 * _cellW, 1e-9));
      expect(m.dy, 0);
      solve(CounterTransition.slide, AxisDirection.left, 0.5, true);
      expect(m.dx, closeTo(-0.5 * _cellW, 1e-9));
      solve(CounterTransition.slide, AxisDirection.left, 0.5, false);
      expect(m.dx, closeTo(0.5 * _cellW, 1e-9));
    });

    test('rotate：离场逆时针、入场从顺时针归位', () {
      solve(CounterTransition.rotate, AxisDirection.up, 0.5, true);
      expect(m.rotateZ, closeTo(-math.pi / 4, 1e-9));
      solve(CounterTransition.rotate, AxisDirection.up, 0.5, false);
      expect(m.rotateZ, closeTo(math.pi / 4, 1e-9));
      expect(m.dx, 0);
      expect(m.dy, 0);
    });

    test('flip：同一时刻只显示一面，角度随相位', () {
      solve(CounterTransition.flip, AxisDirection.up, 0.25, true);
      expect(m.visible, isTrue);
      expect(m.rotateX, closeTo(-0.25 * math.pi, 1e-9));
      solve(CounterTransition.flip, AxisDirection.up, 0.25, false);
      expect(m.visible, isFalse);
      solve(CounterTransition.flip, AxisDirection.up, 0.75, true);
      expect(m.visible, isFalse);
      solve(CounterTransition.flip, AxisDirection.up, 0.75, false);
      expect(m.visible, isTrue);
      expect(m.rotateX, closeTo(0.25 * math.pi, 1e-9));
      // 0.5 属于入场面。
      solve(CounterTransition.flip, AxisDirection.up, 0.5, true);
      expect(m.visible, isFalse);
      solve(CounterTransition.flip, AxisDirection.up, 0.5, false);
      expect(m.visible, isTrue);
    });

    test('none：无位移、无旋转', () {
      solve(const CounterTransition(motion: CounterMotion.none), AxisDirection.up, 0.4, true);
      expect([m.dx, m.dy, m.rotateZ, m.rotateX], everyElement(0));
    });

    test('fade：离场 1-p、入场 p；关闭时恒为 1', () {
      solve(CounterTransition.slide, AxisDirection.up, 0.3, true);
      expect(m.alpha, closeTo(0.7, 1e-9));
      solve(CounterTransition.slide, AxisDirection.up, 0.3, false);
      expect(m.alpha, closeTo(0.3, 1e-9));
      solve(CounterTransition.flip, AxisDirection.up, 0.3, true);
      expect(m.alpha, 1.0);
    });

    test('scale：离场 1-p、入场 p；关闭时恒为 1', () {
      solve(CounterTransition.slideScale, AxisDirection.up, 0.3, true);
      expect(m.scale, closeTo(0.7, 1e-9));
      solve(CounterTransition.slideScale, AxisDirection.up, 0.3, false);
      expect(m.scale, closeTo(0.3, 1e-9));
      solve(CounterTransition.slide, AxisDirection.up, 0.3, true);
      expect(m.scale, 1.0);
    });

    test('visible：完全透明或缩放为 0 时为 false', () {
      solve(CounterTransition.slide, AxisDirection.up, 0.0, false);
      expect(m.alpha, 0.0);
      expect(m.visible, isFalse);
      solve(const CounterTransition(fade: false, scale: true), AxisDirection.up, 1.0, true);
      expect(m.scale, 0.0);
      expect(m.visible, isFalse);
      solve(CounterTransition.slide, AxisDirection.up, 0.0, true);
      expect(m.visible, isTrue);
    });

    test('越界相位被钳制，不产生负透明度或负缩放', () {
      solve(CounterTransition.slideScale, AxisDirection.up, 1.2, true);
      expect(m.alpha, 0.0);
      expect(m.scale, 0.0);
    });

    test('每次调用都会清掉上一次的残留', () {
      solve(CounterTransition.rotate, AxisDirection.up, 0.5, true);
      solve(CounterTransition.slide, AxisDirection.up, 0.5, true);
      expect(m.rotateZ, 0);
    });
  });

  group('方向与辅助函数', () {
    test('effectiveRollDirection：递增不变、递减取反', () {
      for (final d in AxisDirection.values) {
        expect(effectiveRollDirection(d, true), d);
      }
      expect(effectiveRollDirection(AxisDirection.up, false), AxisDirection.down);
      expect(effectiveRollDirection(AxisDirection.down, false), AxisDirection.up);
      expect(effectiveRollDirection(AxisDirection.left, false), AxisDirection.right);
      expect(effectiveRollDirection(AxisDirection.right, false), AxisDirection.left);
    });

    test('verticalExitSign / horizontalExitSign / digitBounceShift', () {
      expect(verticalExitSign(AxisDirection.up), -1);
      expect(verticalExitSign(AxisDirection.right), -1);
      expect(verticalExitSign(AxisDirection.down), 1);
      expect(verticalExitSign(AxisDirection.left), 1);
      expect(horizontalExitSign(AxisDirection.right), 1);
      expect(horizontalExitSign(AxisDirection.left), -1);
      expect(digitBounceShift(AxisDirection.up, 0.1, 40), closeTo(-4, 1e-9));
      expect(digitBounceShift(AxisDirection.down, 0.1, 40), closeTo(4, 1e-9));
    });

    test('digitBlurSigma：关闭时为 0，0.5 处最大，接近端点时回落为 0', () {
      expect(digitBlurSigma(CounterTransition.slide, 0.5), 0);
      expect(digitBlurSigma(CounterTransition.slideBlur, 0.5), closeTo(kDigitBlurMaxSigma * 0.5, 1e-9));
      expect(digitBlurSigma(CounterTransition.slideBlur, 0.0), 0);
      expect(digitBlurSigma(CounterTransition.slideBlur, 0.005), 0);
    });
  });

  group('painter 与组件树两条路径', () {
    final transitions = <String, CounterTransition>{};
    for (final motion in CounterMotion.values) {
      for (final scale in [false, true]) {
        for (final fade in [false, true]) {
          transitions['${motion.name} scale=$scale fade=$fade'] =
              CounterTransition(motion: motion, scale: scale, fade: fade);
        }
      }
    }

    Widget column(CounterTransition t, AxisDirection effective, bool inc, double p) =>
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: DigitColumn(
              value: 4,
              oldValue: 3,
              animationValue: p,
              size: const Size(_cellW, _cellH),
              color: _ink,
              style: const TextStyle(fontSize: 20),
              padding: EdgeInsets.zero,
              numeralSystem: NumeralSystem.latin,
              transition: t,
              triggerHaptics: false,
              flipDirection: effective,
              fast: true,
              fastFromDigit: 3,
              fastToDigit: 4,
              increasing: inc,
            ),
          ),
        );

    testWidgets('四个方向 × 增减 × motion × scale × fade：数值一致', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);

      // 组件树路径中某数位的 (变换, 透明度)；该数位不在树里（flip 的背面）返回 null。
      Future<(Matrix4, double)?> widgetState(CounterTransition t,
          AxisDirection raw, bool inc, double p, int digit) async {
        await tester.pumpWidget(column(t, effectiveRollDirection(raw, inc), inc, p));
        final f = find.text('$digit');
        if (f.evaluate().isEmpty) return null;
        final matrix = tester.renderObject<RenderBox>(f).getTransformTo(null);
        return (matrix, tester.widget<Text>(f).style!.color!.a);
      }

      // painter 路径中某数位的 (完整矩阵, 透明度)；未绘制返回 null。
      (Matrix4, double)? painterState(CounterTransition t, AxisDirection raw,
          bool inc, double p, int digit) {
        final painter = _ProbePainter(transition: t, flipDirection: raw, increasing: inc);
        final canvas = _MatrixCanvas();
        painter.paintTransition(canvas, 3, 4, p, 0, _cellH, _cellW);
        final i = painter.probes.indexWhere((e) => e.$1 == digit);
        painter.disposeCache();
        if (i < 0) return null;
        return (canvas.draws[i], painter.probes[i].$2);
      }

      final probe = DigitMotion();
      for (final entry in transitions.entries) {
        final t = entry.value;
        for (final raw in AxisDirection.values) {
          for (final inc in [true, false]) {
            // 基线：离场位在 p=0、入场位在 p≈1 时都在原位。
            final widgetRestCur = (await widgetState(t, raw, inc, 0.0, 3))!;
            final widgetRestNxt = (await widgetState(t, raw, inc, 0.999999999, 4))!;
            final painterRestCur = painterState(t, raw, inc, 0.0, 3)!;
            final painterRestNxt = painterState(t, raw, inc, 0.999999999, 4)!;
            for (final p in [0.2, 0.5, 0.8]) {
              for (final digit in [3, 4]) {
                final leaving = digit == 3;
                final reason = '${entry.key} $raw inc=$inc p=$p digit=$digit';
                resolveDigitMotion(probe,
                    transition: t,
                    direction: effectiveRollDirection(raw, inc),
                    p: p, leaving: leaving, width: _cellW, height: _cellH);

                final pt = painterState(t, raw, inc, p, digit);
                final wd = await widgetState(t, raw, inc, p, digit);
                // flip 同一时刻只显示一面，其余 motion 两位都在树里。
                expect(pt != null, probe.visible, reason: 'painter 绘制与否 $reason');
                if (t.motion == CounterMotion.flip) {
                  expect(wd != null, probe.visible, reason: 'widget 存在与否 $reason');
                }
                if (pt == null || wd == null) continue;

                expect(pt.$2, closeTo(probe.alpha, 1e-9), reason: 'painter alpha $reason');
                expect(wd.$2, closeTo(probe.alpha, 1e-6), reason: 'widget alpha $reason');
                if (t.motion == CounterMotion.flip) continue;

                final pd = _Delta(pt.$1, leaving ? painterRestCur.$1 : painterRestNxt.$1);
                final wdd = _Delta(wd.$1, leaving ? widgetRestCur.$1 : widgetRestNxt.$1);
                expect(pd.angle, closeTo(probe.rotateZ, 1e-6), reason: 'painter 旋转 $reason');
                expect(wdd.angle, closeTo(probe.rotateZ, 1e-6), reason: 'widget 旋转 $reason');
                expect(pd.scale, closeTo(probe.scale, 1e-6), reason: 'painter 缩放 $reason');
                expect(wdd.scale, closeTo(probe.scale, 1e-6), reason: 'widget 缩放 $reason');
                // 位移与缩放的叠加顺序两条路径一致：位移在缩放之外，不随缩放变化。
                // 总平移 = 位移 + 缩放中心 × (1 - scale)（缩放绕数位自身中心，
                // painter 的中心是单元格中心，组件树的中心是文字盒中心），
                // 因此扣除缩放中心项后，两边的位移都等于解算值——位移不随缩放变化。
                // 未开 scale 时缩放项为 0，总平移就是解算位移。
                // 旋转绕单元中心，平移分量随基线位置变化，不作比较。
                if (t.motion != CounterMotion.rotate) {
                  final k = t.scale ? 1 - probe.scale : 0.0;
                  // 组件树的缩放中心 = 文字盒中心；增量矩阵在全局坐标里，取其全局位置
                  // （getCenter 已含位移，缩放不改变中心点，故减去位移得到基线中心）。
                  final center = tester.getCenter(find.text('$digit'));
                  expect(pd.tx - k * _cellW / 2, closeTo(probe.dx, 1e-6),
                      reason: 'painter dx $reason');
                  expect(pd.ty - k * _cellH / 2, closeTo(probe.dy, 1e-6),
                      reason: 'painter dy $reason');
                  expect(wdd.tx,
                      closeTo(probe.dx + k * (center.dx - probe.dx), 1e-6),
                      reason: 'widget dx $reason');
                  expect(wdd.ty,
                      closeTo(probe.dy + k * (center.dy - probe.dy), 1e-6),
                      reason: 'widget dy $reason');
                }
              }
            }
          }
        }
      }
    });
  });
}
