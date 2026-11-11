import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/capsule.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/src/capsule/motion/capsule_motion.dart';
import 'package:luckdraw/src/capsule/render/capsule_painter.dart';

import '../support/capsule_fixtures.dart';
import '../support/recording_canvas.dart';

/// 开启物理模式的配置。
final CapsuleConfig _physics = capsuleConfig.copyWith(
    options: const CapsuleOptions(physics: LuckyPhysics()));

/// 绘制 [config] 的整局，返回每帧的画布记录与最终 motion。
({CapsuleMotion motion, List<TestRecordingCanvas> canvases}) _play(
    CapsuleConfig config) {
  final motion = CapsuleMotion()..configure(config, capsuleLayout(config)),
      notifier = LuckyFrameNotifier();
  final data = capsuleSurface(motion.frame, notifier, config: config);
  final pictures = CapsulePictures()..prepare(data);
  final painter = CapsulePainter(data, pictures);
  final canvases = <TestRecordingCanvas>[];
  motion.start();
  for (var i = 0; i < 80; i++) {
    motion.tick(0, 20);
  }
  motion.requestStop(1);
  for (var i = 0; i < 400; i++) {
    motion.tick(0, 20);
    final canvas = TestRecordingCanvas();
    painter.paint(canvas, capsuleSize);
    canvases.add(canvas);
  }
  addTearDown(() {
    pictures.dispose();
    notifier.dispose();
  });
  return (motion: motion, canvases: canvases);
}

/// 验证扭蛋机物理模式的绘制：拨杆与置顶。
void main() {
  test('物理模式搅拌时画拨杆，全程不用 saveLayer 且保存恢复平衡', () {
    final run = _play(_physics);
    expect(run.motion.phase, LuckyPhase.settled);
    final withArms =
        run.canvases.where((c) => c.countCalls(#drawRRect) > 0).length;
    expect(withArms, greaterThan(20));
    expect(run.canvases.last.countCalls(#drawRRect), 0);
    for (final canvas in run.canvases) {
      canvas.expectBalancedWithoutSaveLayer();
    }
  });

  test('参数化模式与回退到参数化的物理配置都不画拨杆', () {
    final fallback = capsuleConfig.copyWith(
        options: const CapsuleOptions(physics: LuckyPhysics(maxBodies: 2)));
    for (final config in [capsuleConfig, fallback]) {
      final run = _play(config);
      expect(run.canvases.every((c) => c.countCalls(#drawRRect) == 0), isTrue);
    }
  });

  test('没有拨杆的物理配置不画拨杆', () {
    final none = capsuleConfig.copyWith(
        options: const CapsuleOptions(physics: LuckyPhysics(stirArms: 0)));
    final run = _play(none);
    expect(run.canvases.every((c) => c.countCalls(#drawRRect) == 0), isTrue);
  });

  test('被导引的胶囊在掉落前最后绘制，位于所有其他胶囊之上', () {
    final layout = capsuleLayout(_physics);
    final motion = CapsuleMotion()..configure(_physics, layout),
        notifier = LuckyFrameNotifier();
    final data = capsuleSurface(motion.frame, notifier, config: _physics);
    final pictures = CapsulePictures()..prepare(data);
    final painter = CapsulePainter(data, pictures);
    addTearDown(() {
      pictures.dispose();
      notifier.dispose();
    });
    motion.start();
    for (var i = 0; i < 80; i++) {
      motion.tick(0, 20);
    }
    motion.requestStop(1);
    var checked = 0;
    for (var i = 0;
        i < 400 && motion.frame.stage != CapsuleStage.dropping;
        i++) {
      motion.tick(0, 20);
      final guided = motion.frame.guided;
      if (guided < 0 || motion.frame.stage == CapsuleStage.dropping) continue;
      final canvas = TestRecordingCanvas();
      painter.paint(canvas, capsuleSize);
      final translates = canvas.invocations
          .where((r) => r.invocation.memberName == #translate)
          .map((r) => r.invocation.positionalArguments)
          .toList();
      final knob = translates.indexWhere(
          (a) => a[0] == layout.knobCenter.dx && a[1] == layout.knobCenter.dy);
      expect(knob, greaterThan(0));
      final order = <int>[];
      for (final a in translates.take(knob)) {
        for (var c = 0; c < layout.capsules.length; c++) {
          if (a[0] == layout.globeCenter.dx + motion.frame.x[c] &&
              a[1] == layout.globeCenter.dy + motion.frame.y[c]) {
            order.add(c);
          }
        }
      }
      expect(order.last, guided);
      expect(order.where((c) => c == guided), hasLength(1));
      expect(order.toSet(), hasLength(layout.capsules.length));
      checked++;
    }
    expect(checked, greaterThan(5));
  });
}
