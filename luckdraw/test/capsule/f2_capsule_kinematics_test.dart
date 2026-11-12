@Tags(['golden'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/capsule.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/src/capsule/motion/capsule_motion.dart';
import '../support/capsule_fixtures.dart';

/// 使用真实运动学输出验证静止、减速和结算后缩放。
void main() {
  testWidgets(
      'F2 capsule real kinematics rest deceleration and settled resize goldens',
      (tester) async {
    final config = capsuleConfig.copyWith(
        style: capsuleConfig.style
            .copyWith(text: const LuckyTextDefaults(fontFamily: 'Roboto')));
    final motion = CapsuleMotion()..configure(config, capsuleLayout(config));
    final notifier = LuckyFrameNotifier();
    addTearDown(notifier.dispose);
    var layout = capsuleLayout(config);
    for (var i = 0; i < layout.rest.length; i++) {
      expect(motion.frame.x[i], layout.rest[i].dx);
      expect(motion.frame.y[i], layout.rest[i].dy);
    }
    final scenes = ['rest', 'decelerating', 'resized'];
    for (final scene in scenes) {
      if (scene == 'decelerating') {
        motion.start();
        for (var i = 0; i < 60; i++) {
          motion.tick(i * 20, 20);
        }
        motion.requestStop(1);
        motion.tick(1200, 20);
        motion.tick(1220, 20);
        expect(motion.phase, LuckyPhase.decelerating);
        expect(motion.frame.mix, greaterThan(0));
      } else if (scene == 'resized') {
        for (var i = 62; i < 600 && motion.phase != LuckyPhase.settled; i++) {
          motion.tick(i * 20, 20);
        }
        expect(motion.takeResult()!.index, 1);
        layout = capsuleLayout(config, const Size(240, 400));
        motion.configure(config, layout);
        final index = motion.frame.droppedCapsule;
        expect(motion.frame.x[index] + layout.globeCenter.dx,
            closeTo(layout.tray.center.dx, 1e-8));
        expect(motion.frame.y[index] + layout.globeCenter.dy,
            closeTo(layout.tray.center.dy, 1e-8));
      }
      final data = LuckySurfaceData<CapsuleConfig, CapsuleLayout, CapsuleFrame>(
          config: config,
          layout: layout,
          layoutGeneration: 0,
          frame: motion.frame,
          frameListenable: notifier,
          images: const CapsuleEmptyImages(),
          imagesListenable: notifier,
          layers: const [],
          hooks: const LuckyHooks(),
          devicePixelRatio: 1,
          textDirection: TextDirection.ltr,
          performance:
              const LuckyPerformanceOptions(cacheMode: LuckyCacheMode.picture),
          isAnimating: motion.phase.isMoving);
      await tester.pumpWidget(capsuleHost(RepaintBoundary(
          key: const ValueKey('real-capsule'),
          child: SizedBox.fromSize(
              size: layout.size,
              child: Builder(
                  builder: (context) => const CapsuleCanvasRenderer()
                      .buildSurface(context, data))))));
      await expectLater(find.byKey(const ValueKey('real-capsule')),
          matchesGoldenFile('goldens/f2_capsule_$scene.png'));
      await tester.pumpWidget(const SizedBox());
    }
  });
}
