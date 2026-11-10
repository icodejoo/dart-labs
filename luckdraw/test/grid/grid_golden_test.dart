@Tags(['golden'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/grid.dart';

import '../support/grid_fixtures.dart';
import 'grid_controller_test.dart' show gridHost;

/// Golden 捕捉边界。
const Key _goldenKey = ValueKey<String>('grid golden');

/// Golden 设备像素边长。
const double _physicalSide = 800;

/// Golden 逻辑边长。
const double _logicalSide = 400;

/// Golden 像素比。
const double _dpr = 2;

/// 固定字体和像素比的九宫格基线。
void main() {
  group('grid goldens', () {
    testWidgets('default 3x3 grid with center button', (tester) async {
      await _pumpGolden(tester, gridFixture);
      await expectLater(find.byKey(_goldenKey),
          matchesGoldenFile('goldens/default_grid.png'));
    });
    testWidgets('grid with active cell shadow and gradient', (tester) async {
      final controller = GridController();
      final config = gridFixture.copyWith(
          activeStyle: const LuckyCellStyle(
              background: LuckyFill.legacyLinear(
                  LuckyLegacyGradientDirection.angle(45), [
                LuckyColorStop(Color(0xFFFFCF70)),
                LuckyColorStop(Color(0xFFFF7755))
              ]),
              shadow: LuckyShadow(
                  offsetX: 6, offsetY: 8, blur: 6, color: Color(0x88331100)),
              borderRadius: 10,
              text: LuckyTextOverride(color: Color(0xFFFFFFFF), fontSize: 28)));
      await _pumpGolden(tester, config, controller: controller);
      controller.play();
      await tester.pump();
      await expectLater(
          find.byKey(_goldenKey), matchesGoldenFile('goldens/active_grid.png'));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
    testWidgets('grid with merged cells and border', (tester) async {
      final config = gridFixture.copyWith(
          prizes: const [
            GridPrize(x: 0, y: 0, col: 2, texts: [LuckyText('WIDE')]),
            GridPrize(x: 2, y: 0, row: 2, texts: [LuckyText('TALL')]),
            GridPrize(x: 0, y: 1, row: 2, texts: [LuckyText('A')]),
            GridPrize(x: 1, y: 2, col: 2, texts: [LuckyText('B')]),
          ],
          style: const GridStyle(
              text: gridTextDefaults,
              cell: LuckyCellStyle(
                  background: gridNormalFill,
                  borderRadius: 14,
                  border: LuckyBorder(width: 3, color: Color(0xFFDD4455)))));
      await _pumpGolden(tester, config);
      await expectLater(
          find.byKey(_goldenKey), matchesGoldenFile('goldens/merged_grid.png'));
    });
  });
}

/// 设置设备视口并渲染 400×400 的独立捕捉边界。
Future<void> _pumpGolden(WidgetTester tester, GridConfig config,
    {GridController? controller}) async {
  tester.view.devicePixelRatio = _dpr;
  tester.view.physicalSize = const Size(_physicalSide, _physicalSide);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(gridHost(RepaintBoundary(
      key: _goldenKey,
      child: LuckyGrid(
          config: config,
          controller: controller,
          width: _logicalSide,
          height: _logicalSide))));
  await tester.pump();
}
