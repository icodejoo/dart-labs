import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/src/number_wheel/control/number_wheel_controller.dart';
import 'package:luckdraw/src/number_wheel/model/number_wheel_config.dart';
import 'package:luckdraw/src/number_wheel/widgets/lucky_number_wheel.dart';

import '../support/number_wheel_fixtures.dart';

/// 在固定盒子中挂接组件。
Widget _box(Widget child) => Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
        data: const MediaQueryData(),
        child: Center(child: SizedBox(width: 300, height: 300, child: child))));

/// 以小步长推进完整一局。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// 验证数字转盘交互与结果。
void main() {
  group('LuckyNumberWheel', () {
    testWidgets('onEnd receives the number of the target pocket',
        (tester) async {
      final controller = NumberWheelController();
      addTearDown(controller.dispose);
      LuckyResult<NumberWheelPocket>? result;
      await tester.pumpWidget(_box(LuckyNumberWheel(
          config: numberWheelFixture,
          controller: controller,
          onEnd: (r) => result = r)));
      controller.play();
      controller.stopNumber(20);
      await _settle(tester);
      expect(result?.prize?.number, 20);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('tapping the center calls onStart only in idle-like phases',
        (tester) async {
      final controller = NumberWheelController();
      addTearDown(controller.dispose);
      var starts = 0;
      await tester.pumpWidget(_box(LuckyNumberWheel(
          config: numberWheelFixture,
          controller: controller,
          onStart: () => starts++)));
      await tester.tap(find.byType(LuckyNumberWheel));
      expect(starts, 1);
      controller.play();
      await tester.pump();
      await tester.tap(find.byType(LuckyNumberWheel));
      expect(starts, 1);
      controller.stop(1);
      await _settle(tester);
      await tester.tap(find.byType(LuckyNumberWheel));
      expect(starts, 2);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('onPocketPassed fires as the ball passes pockets',
        (tester) async {
      final controller = NumberWheelController();
      addTearDown(controller.dispose);
      final passed = <int>[];
      await tester.pumpWidget(_box(LuckyNumberWheel(
          config: numberWheelFixture,
          controller: controller,
          onPocketPassed: passed.add)));
      controller.play();
      await _settle(tester);
      expect(passed, isNotEmpty);
      expect(passed.every((i) => i >= 0 && i < 3), isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
