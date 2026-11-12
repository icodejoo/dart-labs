import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:layerman/layerman.dart';
import 'package:layerman_example/demo_kit/demo_kit.dart';
import 'package:layerman_example/helpers.dart';
import 'package:layerman_example/main.dart';

/// 路由式后端必须等待实际退场完成，不能只等待 Navigator.pop 的结果。
void main() {
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);
  for (final backend in ['material', 'getx', 'shadcn']) {
    testWidgets('$backend leaves before the next backend presents', (
      tester,
    ) async {
      final locale = DemoLocale(
        uri: Uri.parse('https://example.test/?lang=en'),
      );
      await tester.pumpWidget(
        AppRoot(locale: locale, initialFragment: '/pages/setup'),
      );
      await tester.pumpAndSettle();
      final manager = Layerman();
      manager.submit<void>(
        id: 'first',
        present: (ctx) {
          const content = AlertDialog(title: Text('first route'));
          return switch (backend) {
            'material' => presentCard<void>(ctx, (_, close) => content),
            'getx' => presentRouteDialog<void>(ctx, content, useGetx: true),
            _ => presentShadDialog<void>(ctx, content),
          };
        },
      );
      var secondShown = false;
      manager.submit<void>(
        id: 'next',
        present: (ctx) {
          secondShown = true;
          return presentRouteDialog<void>(
            ctx,
            const AlertDialog(title: Text('next route')),
          );
        },
      );
      await tester.pumpAndSettle();
      expect(find.text('first route'), findsOneWidget);
      manager.close('first');
      await tester.pump();
      expect(secondShown, isFalse);
      await tester.pump(const Duration(milliseconds: 20));
      expect(secondShown, isFalse);
      await tester.pumpAndSettle();
      expect(secondShown, isTrue);
      expect(find.text('first route'), findsNothing);
      expect(find.text('next route'), findsOneWidget);
      manager.dispose();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      locale.dispose();
      expect(tester.takeException(), isNull);
    });
  }
}
