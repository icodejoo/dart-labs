@Tags(['golden'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/lotto.dart';
import 'package:luckdraw/src/lotto/motion/lotto_motion.dart';
import '../support/lotto_fixtures.dart';
import 'lotto_render_support.dart';

/// 不改写球坐标的真实运动学截图。
void main() {
  testWidgets(
      'F2 lotto real kinematics rest deceleration and settled resize goldens',
      (tester) async {
    final config =
        lottoConfig.copyWith(style: const LottoStyle(buttonText: 'GO'));
    var layout = lottoLayout(config);
    final motion = LottoMotion()..configure(config, layout);
    final notifier = ChangeNotifier();
    addTearDown(notifier.dispose);
    for (var p = 0; p < layout.drums.length; p++) {
      for (var b = 0; b < layout.drums[p].rest.length; b++) {
        expect(motion.frame.x[p][b], layout.drums[p].rest[b].dx);
        expect(motion.frame.y[p][b], layout.drums[p].rest[b].dy);
      }
    }
    final scenes = ['rest', 'decelerating', 'resized'];
    for (final scene in scenes) {
      if (scene == 'decelerating') {
        motion.start();
        motion.tick(100, 100);
        motion.stopWith(lottoDraw);
        motion.tick(120, 20);
        expect(motion.phase, LuckyPhase.decelerating);
      } else if (scene == 'resized') {
        for (var i = 0; i < 100 && motion.phase != LuckyPhase.settled; i++) {
          motion.tick(1000 + i * 20, 20);
        }
        expect(motion.phase, LuckyPhase.settled);
        expect(motion.takeResult()!.draw, lottoDraw);
        layout = lottoLayout(config, const Size(320, 288));
        motion.configure(config, layout);
        for (var p = 0; p < layout.drums.length; p++) {
          final drum = layout.drums[p];
          for (var b = 0; b < motion.frame.slotOf[p].length; b++) {
            final slot = motion.frame.slotOf[p][b];
            if (slot < 0) continue;
            expect(motion.frame.x[p][b] + drum.center.dx,
                closeTo(drum.slots[slot].dx, 1e-8));
            expect(motion.frame.y[p][b] + drum.center.dy,
                closeTo(drum.slots[slot].dy, 1e-8));
          }
        }
      }
      await tester.pumpWidget(lottoSnapshot(lottoSurfaceData(
          config: config,
          layout: layout,
          frame: motion.frame,
          listenable: notifier)));
      await expectLater(find.byKey(const ValueKey('lotto-golden')),
          matchesGoldenFile('goldens/f2_lotto_$scene.png'));
      await tester.pumpWidget(const SizedBox());
    }
  });
}
