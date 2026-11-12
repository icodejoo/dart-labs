import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/src/lots/control/lots_controller.dart';
import 'package:luckdraw/src/lots/model/lots_parts.dart';
import 'package:luckdraw/src/lots/widgets/lucky_lots.dart';

import '../support/lots_fixtures.dart';

/// 固定测试约束。
Widget _box(Widget child) => Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
        data: const MediaQueryData(),
        child: Center(child: SizedBox(width: 300, height: 400, child: child))));

/// 小步推进结束。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// 测试签筒按钮和结算条目命中。
void main() {
  group('LuckyLots', () {
    testWidgets('tapping the cylinder calls onStart only in idle-like phases',
        (tester) async {
      final c = LotsController();
      addTearDown(c.dispose);
      var starts = 0;
      await tester.pumpWidget(_box(LuckyLots(
          config: lotsFixture, controller: c, onStart: () => starts++)));
      final origin = tester.getTopLeft(find.byType(LuckyLots));
      final position = origin + lotsLayout().cylinder.center;
      await tester.tapAt(position);
      expect(starts, 1);
      c.play();
      await tester.pump();
      await tester.tapAt(position);
      expect(starts, 1);
      c.stop(1);
      await _settle(tester);
      await tester.tapAt(position);
      expect(starts, 2);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('tapping the raised stick calls onItemTap after settling',
        (tester) async {
      final c = LotsController();
      addTearDown(c.dispose);
      final items = <int>[];
      final config = lotsFixture.copyWith(
          options: lotsFixture.options.copyWith(revealOnSettle: false));
      await tester.pumpWidget(
          _box(LuckyLots(config: config, controller: c, onItemTap: items.add)));
      final origin = tester.getTopLeft(find.byType(LuckyLots));
      await tester.tapAt(origin + lotsLayout().card.center);
      expect(items, isEmpty);
      c.play();
      c.stop(1);
      await _settle(tester);
      final layout = lotsLayout(config);
      final mouth = layout.cylinder.topCenter;
      final delta =
          layout.raisedStick(1).bottomCenter - const Offset(0, 1) - mouth;
      final angle = layout.angles[1];
      final position = mouth +
          Offset(delta.dx * math.cos(angle) - delta.dy * math.sin(angle),
              delta.dx * math.sin(angle) + delta.dy * math.cos(angle));
      await tester.tapAt(origin + position);
      expect(items, [1]);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('onEnd receives the drawn stick', (tester) async {
      final c = LotsController();
      addTearDown(c.dispose);
      LuckyResult<LotsStick>? result;
      await tester.pumpWidget(_box(LuckyLots(
          config: lotsFixture, controller: c, onEnd: (r) => result = r)));
      c.play();
      c.stop(1);
      await _settle(tester);
      expect(result?.prize, lotsFixture.sticks[1]);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
