import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/grid.dart';

import '../support/grid_fixtures.dart';

/// 将九宫格放入有界、固定方向的测试容器。
Widget gridHost(Widget child) => Directionality(
    textDirection: TextDirection.ltr, child: Center(child: child));

/// 点击与完整矩形命中契约。
void main() {
  group('GridController', () {
    testWidgets(
        'tapping a button calls onStart only in idle-like phases and onButtonTap always',
        (tester) async {
      final controller = GridController();
      var starts = 0;
      final taps = <LuckyPhase>[];
      final ends = <LuckyResult<GridPrize>>[];
      await tester.pumpWidget(gridHost(LuckyGrid(
          config: gridFixture,
          controller: controller,
          width: 300,
          height: 300,
          onStart: () => starts++,
          onButtonTap: (_, phase) => taps.add(phase),
          onEnd: ends.add)));
      final center = tester.getCenter(find.byType(LuckyGrid));
      await tester.tapAt(center);
      expect(starts, 1);
      expect(taps, [LuckyPhase.idle]);
      controller.play();
      await tester.pump();
      await tester.tapAt(center);
      expect(starts, 1);
      expect(taps.last, LuckyPhase.accelerating);
      controller.cancel();
      expect(ends.single.cancelled, isTrue);
      controller.idleSpin();
      await tester.pump();
      await tester.tapAt(center);
      expect(starts, 2);
      expect(taps.last, LuckyPhase.idleSpinning);
      expect(controller.cancel(), isTrue);
      expect(ends, hasLength(1));
      controller.idleSpin();
      controller.reset();
      expect(ends, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
    testWidgets('tapping a prize cell calls onCellTap', (tester) async {
      final tapped = <int>[];
      await tester.pumpWidget(gridHost(LuckyGrid(
          config: gridFixture,
          width: 300,
          height: 300,
          onCellTap: tapped.add)));
      final origin = tester.getTopLeft(find.byType(LuckyGrid));
      await tester.tapAt(origin + const Offset(30, 30));
      expect(tapped, [0]);
    });
    test('hit test ignores the shadow shrink like getGeometricProperty', () {
      final config = gridFixture.copyWith(
          style: const GridStyle(
              cell: LuckyCellStyle(
                  background: gridNormalFill,
                  shadow: LuckyShadow(
                      offsetX: 30, offsetY: 10, color: Color(0xFF000000)))));
      final layout = gridLayout(config);
      final point = layout.hitRect(0).bottomRight - const Offset(1, 1);
      expect(layout.cells.first.normal.rect.contains(point), isFalse);
      final hit = const GridGame()
          .hitTestAll(config, layout, GridFrame(), point)
          .single;
      expect(hit.kind, LuckyHitKind.item);
      expect(hit.index, 0);
    });
    testWidgets('overlapping buttons all fire like upstream forEach',
        (tester) async {
      final taps = <int>[];
      var starts = 0;
      final config = gridFixture.copyWith(
          buttons: const [GridButton(x: 1, y: 1), GridButton(x: 1, y: 1)]);
      await tester.pumpWidget(gridHost(LuckyGrid(
          config: config,
          width: 300,
          height: 300,
          onButtonTap: (i, _) => taps.add(i),
          onStart: () => starts++)));
      await tester.tapAt(tester.getCenter(find.byType(LuckyGrid)));
      expect(taps, [0, 1]);
      expect(starts, 2);
    });
    test('merged cells are hit across their whole span', () {
      const config =
          GridConfig(prizes: [GridPrize(x: 0, y: 0, col: 2, row: 2)]);
      final layout = gridLayout(config);
      final game = const GridGame();
      expect(
          game
              .hitTestAll(config, layout, GridFrame(), const Offset(190, 190))
              .single
              .index,
          0);
      expect(
          game.hitTestAll(config, layout, GridFrame(), const Offset(250, 250)),
          isEmpty);
      expect(
          game.hitTestAll(config, gridLayout(config, size: Size.zero),
              GridFrame(), Offset.zero),
          isEmpty);
    });
  });
  test(
      'GridGame > structural geometry changes and default factories follow the SPI',
      () {
    const game = GridGame();
    expect(game.isStructuralChange(gridFixture, gridFixture), isFalse);
    expect(game.isStructuralChange(gridFixture, gridFixture.copyWith(rows: 4)),
        isTrue);
    expect(game.isStructuralChange(gridFixture, gridFixture.copyWith(cols: 4)),
        isTrue);
    expect(
        game.isStructuralChange(
            gridFixture, gridFixture.copyWith(prizes: const [])),
        isTrue);
    expect(
        game.isStructuralChange(
            gridFixture, gridFixture.copyWith(buttons: const [])),
        isTrue);
    final changed = gridFixture.copyWith(prizes: [
      gridFixture.prizes.first.copyWith(col: 2),
      ...gridFixture.prizes.skip(1)
    ]);
    expect(game.isStructuralChange(gridFixture, changed), isTrue);
    final controller = game.createController();
    expect(controller.phase.value, LuckyPhase.idle);
    controller.dispose();
    expect(game.createDefaultRenderer(), isA<GridCanvasRenderer>());
    expect(game.semanticsLabel(gridFixture), '幸运九宫格，共 8 个奖品');
  });
}
