@Tags(['golden'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/src/lots/motion/lots_motion.dart';
import 'package:luckdraw/src/lots/render/lots_painter.dart';

import '../support/lots_fixtures.dart';

/// 在固定画布比较抽签视觉基线。
Future<void> _golden(WidgetTester tester, String name, LotsFrame frame) async {
  final n = LuckyFrameNotifier(), cache = LuckyPictureCache();
  final data = lotsSurface(n,
      frame: frame,
      config: lotsFixture.copyWith(
          style: lotsFixture.style.copyWith(fontFamily: 'Roboto')));
  await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
          child: RepaintBoundary(
              key: const ValueKey('golden'),
              child: CustomPaint(
                  size: const Size(300, 400),
                  painter: LotsPainter(data, cache))))));
  await expectLater(find.byKey(const ValueKey('golden')),
      matchesGoldenFile('goldens/$name.png'));
  await tester.pumpWidget(const SizedBox());
  n.dispose();
  cache.dispose();
}

/// 验证静止、摇动和展示的绘制。
void main() {
  group('lots goldens', () {
    testWidgets('lots cylinder at rest', (tester) async {
      await _golden(tester, 'rest', LotsFrame());
    });
    testWidgets('lots shaking', (tester) async {
      await _golden(
          tester,
          'shaking',
          LotsFrame()
            ..shakeDeg = 12
            ..stage = LotsStage.shaking);
    });
    testWidgets('lots revealed stick', (tester) async {
      await _golden(
          tester,
          'revealed',
          LotsFrame()
            ..targetIndex = 1
            ..targetSlot = 1
            ..riseProgress = 1
            ..revealProgress = 1
            ..stage = LotsStage.done
            ..phase = LuckyPhase.settled);
    });
  });
}
