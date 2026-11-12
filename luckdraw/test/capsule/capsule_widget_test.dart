import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/capsule.dart';
import 'package:luckdraw/extend.dart';

import '../support/capsule_fixtures.dart';

/// 可替换后端捕获布局与帧。
final class _Renderer extends LuckyRenderer<CapsuleConfig, CapsuleLayout,
    CapsuleFrame, LuckyResult<CapsulePrize>> {
  /// 创建捕获后端。
  _Renderer();

  /// 最近一次输入。
  LuckySurfaceData<CapsuleConfig, CapsuleLayout, CapsuleFrame>? data;

  /// 捕获输入并返回空表面。
  @override
  Widget buildSurface(BuildContext context,
      LuckySurfaceData<CapsuleConfig, CapsuleLayout, CapsuleFrame> data) {
    this.data = data;
    return const SizedBox.expand();
  }
}

/// 组件交互与宿主回调契约。
void main() {
  group('LuckyCapsuleMachine', () {
    testWidgets('tapping the knob calls onStart only in idle-like phases',
        (tester) async {
      final c = CapsuleController();
      var starts = 0;
      await tester.pumpWidget(capsuleHost(LuckyCapsuleMachine(
          config: capsuleConfig,
          controller: c,
          width: 300,
          height: 500,
          onStart: () => starts++)));
      await tester.tapAt(capsuleLayout().knobCenter);
      expect(starts, 1);
      c.play();
      await tester.pump();
      await tester.tapAt(capsuleLayout().knobCenter);
      expect(starts, 1);
      c.stop(0);
      await tester.pumpAndSettle();
      await tester.tapAt(capsuleLayout().knobCenter);
      expect(starts, 2);
      c.idleSpin();
      await tester.pump();
      await tester.tapAt(capsuleLayout().knobCenter);
      expect(starts, 3);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
    testWidgets(
        'tapping the capsule in the tray calls onItemTap after settling',
        (tester) async {
      final c = CapsuleController();
      final taps = <int>[];
      await tester.pumpWidget(capsuleHost(LuckyCapsuleMachine(
          config: capsuleConfig,
          controller: c,
          width: 300,
          height: 500,
          onItemTap: taps.add)));
      await tester.tapAt(capsuleLayout().tray.center);
      expect(taps, isEmpty);
      c.play();
      c.stop(1);
      await tester.pumpAndSettle();
      await tester.tapAt(capsuleLayout().tray.center);
      expect(taps, [1]);
      await tester.tapAt(capsuleLayout().card.topLeft + const Offset(10, 10));
      expect(taps, [1, 1]);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
    testWidgets('onEnd receives the prize of the dropped capsule',
        (tester) async {
      final c = CapsuleController();
      final results = <LuckyResult<CapsulePrize>>[];
      await tester.pumpWidget(capsuleHost(LuckyCapsuleMachine(
          config: capsuleConfig,
          controller: c,
          width: 300,
          height: 500,
          onEnd: results.add)));
      c.play();
      c.stop(1);
      await tester.pumpAndSettle();
      expect(results.length, 1);
      expect(results.single.index, 1);
      expect(results.single.prize, capsuleConfig.prizes[1]);
      expect(results.single.cancelled, isFalse);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
    testWidgets('a custom renderer receives capsule layout and frame',
        (tester) async {
      final c = CapsuleController(), renderer = _Renderer();
      await tester.pumpWidget(capsuleHost(LuckyCapsuleMachine(
          config: capsuleConfig,
          controller: c,
          renderer: renderer,
          width: 300,
          height: 500)));
      expect(renderer.data?.layout.globeCenter, capsuleLayout().globeCenter);
      expect(identical(renderer.data?.frame, c.frame), isTrue);
      expect(renderer.data?.config, capsuleConfig);
      c.play();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(renderer.data?.frame.swirlDeg, greaterThan(0));
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });
  testWidgets(
      'LuckyCapsuleMachine edges > owned controller empty layout and config update',
      (tester) async {
    await tester.pumpWidget(capsuleHost(const LuckyCapsuleMachine(
        config: CapsuleConfig(), width: 0, height: 0)));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(capsuleHost(const LuckyCapsuleMachine(
        config: capsuleConfig, width: 300, height: 500)));
    expect(find.byType(CustomPaint), findsOneWidget);
    expect(
        const CapsuleGame().hitTestAll(
            capsuleConfig,
            capsuleLayout(capsuleConfig, Size.zero),
            CapsuleFrame(),
            Offset.zero),
        isEmpty);
    expect(
        const CapsuleGame().isStructuralChange(
            capsuleConfig, capsuleConfig.copyWith(capsules: [0])),
        isTrue);
    expect(
        const CapsuleGame().isStructuralChange(
            capsuleConfig, capsuleConfig.copyWith(capsulesPerPrize: 2)),
        isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
