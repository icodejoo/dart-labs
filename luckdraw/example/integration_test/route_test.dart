import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:luckdraw_example/demo_shell.dart';
import 'package:luckdraw_example/main.dart';
import 'package:luckdraw_example/pages/wheel_page.dart';

import 'support/flows.dart';

/// 反复挂载运动中的路由，验证离开后没有 Ticker 残留。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('route', () {
    testWidgets('push and pop 20 times leaves no active ticker',
        (tester) async {
      await tester.pumpWidget(const LuckdrawExample());
      await tester.pumpAndSettle();
      final baseline = tester.binding.transientCallbackCount;
      for (var i = 0; i < 20; i++) {
        await tester.tap(find.text('转盘'));
        await tester.pumpAndSettle();
        final state = tester.state<WheelPageState>(find.byType(WheelPage));
        final controller = state.controller;
        await tester.tap(find.byKey(startKey));
        await waitFor(tester, () => controller.frame.rotateDeg > 0);
        expect(controller.isAttached, isTrue);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(state.mounted, isFalse);
        expect(controller.isAttached, isFalse);
        expect(tester.binding.transientCallbackCount, baseline);
        expect(find.byType(WheelPage), findsNothing);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      expect(tester.binding.transientCallbackCount, 0);
    });
  });
}
