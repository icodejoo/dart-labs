import 'dart:math' as math;
import 'package:countman/src/core/ticker.dart';
import 'package:countman/src/counter/plugin.dart';
import 'package:countman/src/widgets/ring_counter.dart';
import 'package:countman/src/widgets/bar_counter.dart';
import 'package:countman/src/widgets/ring_countdown.dart';
import 'package:countman/src/widgets/bar_countdown.dart';
import 'package:countman/src/widgets/ring_style.dart';
import 'package:countman/src/widgets/bar_style.dart';
import 'package:countman/src/widgets/providers.dart';
import 'package:countman/src/widgets/painter/ring_painter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证进度绘制、方向性渐变和 animateOnce 的显示契约。
void main() {
  tearDown(Countman.destroy);
  const size = Size.square(80);
  const gradient = LinearGradient(
      begin: AlignmentDirectional.centerStart,
      end: AlignmentDirectional.centerEnd,
      colors: [Color(0xff000000), Color(0xffffffff)]);
  test('满环圆头在全部进度区间严格单调', () {
    final sweeps = [1.0, 0.99, 0.97]
        .map((p) => RingPainter.arcGeometry(
                startAngle: 0,
                sweepAngle: 2 * math.pi,
                progress: p,
                strokeWidth: 12,
                radius: 54,
                strokeCap: StrokeCap.round,
                clockwise: true,
                anchorAtEnd: true)
            .sweep)
        .toList();
    expect(sweeps[0], greaterThan(sweeps[1]));
    expect(sweeps[1], greaterThan(sweeps[2]));
  });
  test('默认和自定义游标半径都预留布局余量', () {
    for (final thumb in <double?>[null, 15]) {
      final painter = RingPainter(
          progress: 1,
          color: const Color(0xff000000),
          trackColor: const Color(0xffffffff),
          strokeWidth: 8,
          clockwise: true,
          showThumb: true,
          thumbRadius: thumb);
      expect(
          painter.radiusFor(size) + (thumb ?? 8 * 0.7), lessThanOrEqualTo(40));
    }
  });
  for (final direction in TextDirection.values) {
    testWidgets('四个进度组件支持方向性渐变 $direction', (tester) async {
      await tester.pumpWidget(Directionality(
          textDirection: direction,
          child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: const [
            RingCounter(
                to: 1,
                from: 0.5,
                style: RingStyle(gradient: gradient, trackGradient: gradient)),
            BarCounter(
                to: 1,
                from: 0.5,
                style: BarStyle(gradient: gradient, trackGradient: gradient)),
            RingCountdown(
                to: Duration(seconds: 10),
                style: RingStyle(gradient: gradient, trackGradient: gradient)),
            BarCountdown(
                to: Duration(seconds: 10),
                style: BarStyle(gradient: gradient, trackGradient: gradient)),
          ]))));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('竖向进度条默认字面尺寸为 8×200', (tester) async {
    await tester.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr,
        child:
            Center(child: BarCounter(to: 1, style: BarStyle(vertical: true)))));
    final paint = find.descendant(
        of: find.byType(BarCounter), matching: find.byType(CustomPaint));
    expect(tester.getSize(paint), const Size(8, 200));
  });
  testWidgets('Ring/Bar 稳定 key 的 animateOnce 跳过重挂并同步 controller',
      (tester) async {
    final visible = ValueNotifier(0);
    final ring = CounterValueController();
    final bar = CounterValueController();
    await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: CounterProvider(
            animateOnce: true,
            child: ValueListenableBuilder<int>(
                valueListenable: visible,
                builder: (_, phase, child) => Center(
                    child: phase >= 0
                        ? Column(mainAxisSize: MainAxisSize.min, children: [
                            RingCounter(
                                key: const ValueKey('ring'),
                                to: 10.0 + phase,
                                controller: ring),
                            BarCounter(
                                key: const ValueKey('bar'),
                                to: 20.0 + phase,
                                controller: bar),
                          ])
                        : const SizedBox())))));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    visible.value = -1;
    await tester.pump();
    visible.value = 0;
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(ring.value, 10);
    expect(bar.value, 20);
    visible.value = 5;
    await tester.pump();
    expect(ring.value, 15);
    expect(bar.value, 25);
    await tester.pumpWidget(const SizedBox());
    visible.dispose();
  });
}
