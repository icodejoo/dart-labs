import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:layerman_example/demo_kit/demo_kit.dart';
import 'package:layerman_example/main.dart';
import 'package:layerman_example/pages/presenters_page.dart';

/// 完成控件帧、等待旧路由退场，再绘制新后端。
Future<void> _present(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// 在真实应用宿主中验证每种后端的展示、重放与卸载清理。
void main() {
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);
  for (final language in ['en', 'zh']) {
    for (final backend in DemoBackend.values) {
      testWidgets(
        '${backend.name} $language paints, replays and cleans its real UI',
        (tester) async {
          final locale = DemoLocale(
            uri: Uri.parse('https://example.test/?lang=$language'),
          );
          await tester.pumpWidget(
            AppRoot(locale: locale, initialFragment: '/pages/presenters'),
          );
          await tester.pumpAndSettle();
          if (language == 'zh') {
            await tester.tap(find.byTooltip('切换亮暗'));
            await tester.pumpAndSettle();
          }
          final target = find.byWidgetPredicate(
            (widget) => widget is BackendDemo && widget.backend == backend,
          );
          final card = find.descendant(
            of: target,
            matching: find.byType(DemoCard),
          );
          final open = find.descendant(
            of: target,
            matching: find.text(language == 'en' ? 'Open demo' : '打开演示'),
          );
          await tester.ensureVisible(open);
          await tester.pumpAndSettle();
          await tester.tap(open);
          await _present(tester);
          expect(tester.takeException(), isNull);
          expect(
            find.descendant(
              of: target,
              matching: find.textContaining(
                language == 'en' ? 'Active 1' : '激活 1',
              ),
            ),
            findsOneWidget,
          );
          // 控制器级重放也必须能清理尚未退场的路由，不能只重置卡片文案。
          tester.widget<DemoCard>(card).onReplay!();
          await _present(tester);
          expect(tester.takeException(), isNull);
          expect(
            find.descendant(
              of: target,
              matching: find.textContaining(
                language == 'en' ? 'Active 1' : '激活 1',
              ),
            ),
            findsOneWidget,
          );
          // 先卸载页面，让 manager 通过自己的句柄清理，然后等实际动画结束。
          await tester.binding.handlePushRoute('/pages/setup');
          await tester.pumpAndSettle();
          await tester.pump(const Duration(seconds: 4));
          expect(find.byType(BackendDemo), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          locale.dispose();
        },
      );
    }
  }
  testWidgets('mixed sequence waits for every backend to exit', (tester) async {
    final locale = DemoLocale(uri: Uri.parse('https://example.test/?lang=en'));
    await tester.pumpWidget(
      AppRoot(locale: locale, initialFragment: '/pages/presenters'),
    );
    await tester.pumpAndSettle();
    final target = find.byWidgetPredicate(
      (widget) => widget is BackendDemo && widget.backend == DemoBackend.mixed,
    );
    final open = find.descendant(of: target, matching: find.text('Open demo'));
    await tester.ensureVisible(open);
    await tester.pumpAndSettle();
    await tester.tap(open);
    await _present(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Copied to clipboard'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pump();
    expect(find.text('Copied to clipboard'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('Copied to clipboard'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Copied to clipboard'), findsNothing);
    expect(find.text('One queue, any UI'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: target, matching: find.text('Active 0 · Queued 0')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    locale.dispose();
    expect(tester.takeException(), isNull);
  });
}
