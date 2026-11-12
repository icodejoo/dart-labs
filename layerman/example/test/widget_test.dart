import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:layerman_example/demo_kit/demo_kit.dart';
import 'package:layerman_example/demo_shell.dart';
import 'package:layerman_example/main.dart';
import 'package:layerman_example/pages/catalog_page.dart';
import 'package:layerman_example/pages/presenters_page.dart';
import 'package:layerman_example/pages/setup_page.dart';
import 'package:layerman_example/scenarios.dart';

/// 线上入口在测试中使用的稳定地址。
const _url = 'https://icodejoo.github.io/dart-labs/layerman/';

/// 验证完整应用的语言、主题、版本及所有页面响应式布局。
void main() {
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  test('version and external links match package metadata', () {
    final pubspec = File('../pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('version: $demoVersion'));
    expect(pubspec, contains('homepage: $demoRepository'));
    expect(demoReadme, endsWith('/layerman/README.md'));
  });

  testWidgets('AppRoot renders and responds to language and theme', (
    tester,
  ) async {
    final locale = DemoLocale(uri: Uri.parse('$_url?lang=en'));
    await tester.pumpWidget(AppRoot(locale: locale));
    await tester.pumpAndSettle();
    expect(find.text(demoVersion), findsOneWidget);
    await tester.tap(find.text('中文'));
    await tester.pumpAndSettle();
    expect(find.text('队列与模式'), findsOneWidget);
    await tester.tap(find.byTooltip('切换亮暗'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(DemoPage))).brightness,
      Brightness.dark,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    locale.dispose();
  });

  for (final size in [const Size(375, 667), const Size(1440, 900)]) {
    for (final language in ['en', 'zh']) {
      testWidgets('all pages at $size in $language, both themes', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final locale = DemoLocale(uri: Uri.parse('$_url?lang=$language'));
        final pages = <Widget>[
          for (final group in [...demoGroups, diagnosticsGroup])
            CatalogPage(group: group),
          const PresentersPage(),
          const SetupPage(),
        ];
        for (final brightness in Brightness.values) {
          for (final page in pages) {
            await tester.pumpWidget(
              DemoApp(
                key: UniqueKey(),
                title: demoProject,
                seedColor: Colors.blue,
                locale: locale,
                home: Theme(
                  data: ThemeData(brightness: brightness),
                  child: Scaffold(body: page),
                ),
              ),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 250));
            expect(tester.takeException(), isNull, reason: '$page $brightness');
            final cards = find.byType(DemoCard);
            expect(cards, findsWidgets);
            for (final element in cards.evaluate()) {
              final box = element.renderObject! as RenderBox;
              expect(box.size.width, lessThanOrEqualTo(size.width));
            }
            final first = tester.getRect(cards.first);
            expect(first.top, lessThan(size.height));
            if (page is CatalogPage && size.width == 375) {
              expect(
                tester.getRect(cards.at(1)).top,
                lessThan(size.height - 40),
              );
            }
            if (page is! SetupPage) {
              expect(find.byIcon(Icons.replay_rounded), findsWidgets);
            } else {
              expect(find.byIcon(Icons.replay_rounded), findsNothing);
            }
            await tester.pumpWidget(const SizedBox());
            await tester.pumpAndSettle();
          }
        }
        locale.dispose();
      });
    }
  }

  testWidgets(
    'drawer navigates to restored hash page without old version labels',
    (tester) async {
      final locale = DemoLocale(uri: Uri.parse('$_url?lang=en'));
      await tester.pumpWidget(
        AppRoot(locale: locale, initialFragment: '/pages/data'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Data & outcomes'), findsOneWidget);
      await tester.tap(find.byTooltip('Open navigation'));
      await tester.pumpAndSettle();
      expect(find.text('v0.3 Features'), findsNothing);
      await tester.tap(find.text('Timing & pause'));
      await tester.pumpAndSettle();
      expect(find.text('Timing & pause'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      locale.dispose();
    },
  );
}
