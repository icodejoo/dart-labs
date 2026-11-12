@Tags(['golden'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/lotto.dart';
import 'package:luckdraw/src/lotto/motion/lotto_motion.dart';

import '../support/lotto_fixtures.dart';
import 'lotto_render_support.dart';

/// 按指定阶段截图；容器内使用测试姿态，避免数值绑定临时 core。
Future<void> expectLottoGolden(WidgetTester tester, String phase) async {
  // SDK 测试字体只有 Roboto，按钮使用 ASCII 文案以保持跨平台基线。
  final config =
      LottoConfig.superLotto(style: const LottoStyle(buttonText: 'GO'));
  final layout = lottoLayout(config);
  final motion = LottoMotion()..configure(config, layout);
  final notifier = ChangeNotifier();
  addTearDown(notifier.dispose);
  if (phase != 'rest') {
    motion.start();
    motion.tick(800, 800);
  }
  if (phase == 'drawn') {
    motion.stopWith(const LottoDraw([
      [35, 1, 23, 8, 16],
      [12, 2]
    ]));
    motion.tick(810, 10);
    for (var i = 0; i < 7; i++) {
      motion.tick(10000, i == 0 ? 10000 : 0);
    }
    expect(motion.phase, LuckyPhase.settled);
    expect(motion.frame.drawnCount, 7);
  }
  setLottoGoldenPose(motion.frame, layout, mixing: phase == 'mixing');
  await tester.pumpWidget(lottoSnapshot(lottoSurfaceData(
      config: config,
      layout: layout,
      frame: motion.frame,
      listenable: notifier)));
  await expectLater(find.byKey(const ValueKey('lotto-golden')),
      matchesGoldenFile('goldens/super_lotto_$phase.png'));
}

/// 验证默认预设的三个视觉阶段。
void main() {
  group('lotto goldens', () {
    testWidgets('super lotto machine at rest',
        (tester) => expectLottoGolden(tester, 'rest'));
    testWidgets(
        'super lotto mixing', (tester) => expectLottoGolden(tester, 'mixing'));
    testWidgets('super lotto with all balls drawn',
        (tester) => expectLottoGolden(tester, 'drawn'));
  });
}
