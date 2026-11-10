@Tags(['golden'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/wheel.dart';

import '../support/fonts.dart';
import 'wheel_render_support.dart';

/// 以真实 Canvas 后端输出固定尺寸和倍率的图像。
Future<void> _golden(WidgetTester tester, WheelConfig config, String name,
    {double rotation = 0}) async {
  expect(luckyTestFontsLoaded, isTrue);
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = const Size(1000, 1000);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final harness = WheelPainterHarness(config: config);
  harness.frame.rotateDeg = rotation;
  await tester.pumpWidget(wheelRenderRoot(RepaintBoundary(
      key: const ValueKey('wheel-golden'),
      child: Builder(
          builder: (context) => const WheelCanvasRenderer()
              .buildSurface(context, harness.data)))));
  await expectLater(find.byKey(const ValueKey('wheel-golden')),
      matchesGoldenFile('goldens/$name.png'));
}

/// 固定关键帧的转盘视觉回归。
void main() {
  group('wheel goldens', () {
    testWidgets('default six prize wheel at rest', (tester) async {
      await _golden(tester, wheelRenderFixture(), 'default');
    });
    testWidgets('wheel rotated 37 degrees mid spin', (tester) async {
      await _golden(tester, wheelRenderFixture(), 'rotated_37', rotation: 37);
    });
    testWidgets('wheel with gutter blocks pointer and wrapped text',
        (tester) async {
      final base = wheelRenderFixture();
      await _golden(
          tester,
          base.copyWith(
              blocks: const [
                WheelBlock(
                    padding: 15,
                    background: LuckyFill.color(kWheelRenderAccent))
              ],
              options: const WheelOptions(gutter: 4),
              prizes: [
                base.prizes.first.copyWith(texts: const [
                  LuckyText('LUCKY WHEEL WRAPPED PRIZE',
                      fontFamily: 'Roboto',
                      fontSize: 18,
                      top: LuckyLength.px(15),
                      lengthLimit: LuckyLength.percent(85))
                ]),
                ...base.prizes.skip(1)
              ]),
          'decorated');
    });
    testWidgets('wheel with weighted sectors', (tester) async {
      final base = wheelRenderFixture();
      await _golden(
          tester,
          base.copyWith(prizes: [
            for (var i = 0; i < base.prizes.length; i++)
              base.prizes[i].copyWith(sectorWeight: (i + 1).toDouble()),
          ]),
          'weighted');
    });
  });
}
