import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/lotto.dart';

import '../support/lotto_fixtures.dart';
import '../support/recording_canvas.dart';
import 'lotto_painter_test.dart' show currentLottoPainter;
import 'lotto_widget_test.dart' show lottoHost;

/// 全部池开启物理模式的配置。
final LottoConfig _physics = lottoConfig.copyWith(
    options: lottoOptions.copyWith(physics: const LuckyPhysics()));

/// 单次整局绘制的 drawRRect 计数记录。
Future<List<int>> _arms(WidgetTester tester, LottoConfig config) async {
  final controller = LottoController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(lottoHost(LuckyLotto(
      config: config,
      controller: controller,
      width: lottoSize.width,
      height: lottoSize.height)));
  for (var i = 0; i < 60; i++) {
    await tester.pump(lottoStep);
  }
  controller.play();
  final counts = <int>[];
  for (var i = 0; i < 10; i++) {
    await tester.pump(lottoStep);
  }
  controller.stopWith(lottoDraw);
  for (var i = 0; i < 120; i++) {
    await tester.pump(lottoStep);
    final canvas = TestRecordingCanvas();
    currentLottoPainter(tester).paint(canvas, lottoSize);
    canvas.expectBalancedWithoutSaveLayer();
    counts.add(canvas.countCalls(#drawRRect));
  }
  await tester.pumpWidget(const SizedBox());
  return counts;
}

/// 验证大乐透物理模式的绘制：每个容器各画一组拨杆。
void main() {
  testWidgets('物理模式每个容器画两根拨杆，参数化模式不画', (tester) async {
    final physics = await _arms(tester, _physics);
    expect(physics.where((c) => c == 4).length, greaterThan(20));
    expect(physics.every((c) => c == 0 || c == 4), isTrue);
    expect(physics.last, 0);
    final kinematic = await _arms(tester, lottoConfig);
    expect(kinematic.every((c) => c == 0), isTrue);
  });

  testWidgets('只有部分池能物理模拟时，只给物理池画拨杆', (tester) async {
    final partial = lottoConfig.copyWith(
        options:
            lottoOptions.copyWith(physics: const LuckyPhysics(maxBodies: 5)));
    final counts = await _arms(tester, partial);
    expect(counts.where((c) => c == 2).length, greaterThan(20));
    expect(counts.every((c) => c == 0 || c == 2), isTrue);
  });

  testWidgets('没有拨杆的物理配置不画拨杆', (tester) async {
    final none = lottoConfig.copyWith(
        options:
            lottoOptions.copyWith(physics: const LuckyPhysics(stirArms: 0)));
    expect((await _arms(tester, none)).every((c) => c == 0), isTrue);
  });
}
