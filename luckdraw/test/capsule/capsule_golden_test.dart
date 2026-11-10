@Tags(['golden'])
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/capsule.dart';
import 'package:luckdraw/extend.dart';

import '../support/capsule_fixtures.dart';
import 'capsule_perf_support.dart';

/// 使用渲染夹具而非 mixer 数值，基线不绑定临时 T5.0 实现。
Future<void> _golden(WidgetTester tester, String scene) async {
  final l = capsuleLayout();
  final r = l.capsuleRadius;
  final bottom = l.globeRadius - r;
  final row = math.sqrt(3) * r;
  final frame = CapsuleFrame()
    ..x = Float64List.fromList([0, -r, r, -2 * r, 0, 2 * r])
    ..y = Float64List.fromList([
      bottom,
      bottom - row,
      bottom - row,
      bottom - 2 * row,
      bottom - 2 * row,
      bottom - 2 * row
    ])
    ..angle = Float64List(6);
  if (scene == 'mixing') {
    frame
      ..phase = LuckyPhase.cruising
      ..stage = CapsuleStage.mixing
      ..swirlDeg = 300
      ..knobDeg = 75
      ..mix = 1;
    frame.x.setAll(0, [-65, 35, 60, -35, 0, 15]);
    frame.y.setAll(0, [-10, 65, -30, 35, -60, 0]);
    frame.angle.setAll(0, [0.4, 1.2, 2, 2.8, 3.6, 4.4]);
  } else if (scene == 'revealed') {
    frame
      ..phase = LuckyPhase.settled
      ..stage = CapsuleStage.done
      ..targetPrize = 1
      ..droppedCapsule = 3
      ..dropProgress = 1
      ..revealProgress = 1;
    frame.x[3] = l.tray.center.dx - l.globeCenter.dx;
    frame.y[3] = l.tray.center.dy - l.globeCenter.dy;
  }
  final notifier = LuckyFrameNotifier();
  final input = capsulePictureSurface(capsuleSurface(frame, notifier));
  await tester.pumpWidget(capsuleHost(RepaintBoundary(
      key: const ValueKey('golden'),
      child: SizedBox(
          width: 300,
          height: 500,
          child: Builder(
              builder: (context) => const CapsuleCanvasRenderer()
                  .buildSurface(context, input))))));
  await expectLater(find.byKey(const ValueKey('golden')),
      matchesGoldenFile('goldens/capsule_$scene.png'));
  await tester.pumpWidget(const SizedBox());
  notifier.dispose();
}

/// 验证静止、搅拌、开蛋三个确定的渲染快照。
void main() {
  group('capsule goldens', () {
    testWidgets('capsule machine at rest', (tester) => _golden(tester, 'rest'));
    testWidgets(
        'capsule machine mixing', (tester) => _golden(tester, 'mixing'));
    testWidgets('capsule revealed in the tray',
        (tester) => _golden(tester, 'revealed'));
  });
}
