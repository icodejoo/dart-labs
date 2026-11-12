import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:layerman_example/demo_kit/demo_kit.dart';
import 'package:layerman_example/main.dart';

/// 在真实设备上确认导航、串行关闭与重放的端到端交互。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'queue advances, replay restores, and navigation stays bilingual',
    (tester) async {
      final locale = DemoLocale(
        uri: Uri.parse('https://example.test/?lang=en'),
      );
      await tester.pumpWidget(AppRoot(locale: locale));
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('queue'));
      await tester.tap(
        find.descendant(of: card, matching: find.text('Close')).first,
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: card, matching: find.text('B')),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(of: card, matching: find.byTooltip('Replay')),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: card, matching: find.text('A')),
        findsOneWidget,
      );
      await tester.tap(find.text('中文'));
      await tester.pumpAndSettle();
      expect(find.text('队列与模式'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      locale.dispose();
      Get.reset();
    },
  );
}
