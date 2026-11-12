@Tags(['golden'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/src/number_wheel/model/number_wheel_config.dart';
import 'package:luckdraw/src/number_wheel/motion/number_wheel_motion.dart';
import 'package:luckdraw/src/number_wheel/render/number_wheel_painter.dart';

import '../support/number_wheel_fixtures.dart';

/// 固定尺寸录制，避免宿主时钟影响视觉基线。
Future<void> _golden(
    WidgetTester tester, String file, NumberWheelFrame frame) async {
  final notifier = LuckyFrameNotifier(), cache = LuckyPictureCache();
  final config = NumberWheelConfig.range(0, 36,
      style: const NumberWheelStyle(fontFamily: 'Roboto'));
  final expectedRadius = frame.ballRadius;
  final data = numberWheelSurface(notifier, config: config, frame: frame);
  expect(data.frame.ballRadius, expectedRadius);
  await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
          child: RepaintBoundary(
              key: const ValueKey('golden'),
              child: CustomPaint(
                  size: const Size(300, 300),
                  painter: NumberWheelPainter(data, cache))))));
  await expectLater(find.byKey(const ValueKey('golden')),
      matchesGoldenFile('goldens/$file.png'));
  await tester.pumpWidget(const SizedBox());
  notifier.dispose();
  cache.dispose();
}

/// 数字盘静止、滚动和落袋基线。
void main() {
  group('number wheel goldens', () {
    testWidgets('number wheel 0 to 36 at rest', (tester) async {
      await _golden(tester, 'rest', NumberWheelFrame()..ballRadius = 139.5);
    });
    testWidgets('number wheel ball on the track', (tester) async {
      await _golden(
          tester,
          'track',
          NumberWheelFrame()
            ..ballRadius = 139.5
            ..ballDeg = 110
            ..discDeg = 28);
    });
    testWidgets('number wheel ball in the target pocket', (tester) async {
      await _golden(
          tester,
          'pocket',
          NumberWheelFrame()
            ..ballRadius = 105
            ..ballDeg = 360 / 37 * 12 + 20
            ..discDeg = 20
            ..targetIndex = 12
            ..phase = LuckyPhase.settled);
    });
  });
}
