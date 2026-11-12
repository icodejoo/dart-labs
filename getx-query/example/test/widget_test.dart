import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:getx_query_example/demo_kit/demo_kit.dart';
import 'package:getx_query_example/main.dart';
import 'package:getx_query_example/pages/query_page.dart';
import 'package:getx_query_example/pages/mutation_page.dart';
import 'package:getx_query_example/pages/infinite_page.dart';
import 'package:getx_query_example/pages/queries_page.dart';
import 'package:getx_query_example/pages/viewmodel_page.dart';

/// 控件测试使用的显式英文地址。
const _testUrl = 'https://example.test/?lang=en';

/// 单个模拟请求的完整等待时间。
const _requestWait = Duration(milliseconds: 700);

/// 五个稳定的 URL 页面标识。
const _pages = ['query', 'mutation', 'infinite', 'queries', 'viewmodel'];

/// 挂载独立页面，确保每个交互测试有足够可视空间。
Future<void> _mount(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(1440, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final locale = DemoLocale(uri: Uri.parse(_testUrl));
  addTearDown(locale.dispose);
  await tester.pumpWidget(
    DemoApp(
      title: 'test',
      seedColor: Colors.orange,
      locale: locale,
      home: Scaffold(body: page),
    ),
  );
  await tester.pumpAndSettle();
}

/// 移除所有订阅并排空仍在执行的本地任务。
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(_requestWait * 2);
  expect(tester.takeException(), isNull);
}

/// 验证真实查询状态、重放、资源释放与全站响应式布局。
void main() {
  testWidgets('version chip reads the current package pubspec asset', (
    tester,
  ) async {
    final source = File('../pubspec.yaml').readAsStringSync();
    final expected = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(source)!.group(1);
    expect(await loadDemoVersion(), expected);
    await tester.pumpWidget(const GetxQueryDemoApp());
    await tester.pumpAndSettle();
    expect(find.text(expected!), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets(
    'reactive filter, enabled, refetch and replay restore initial query',
    (tester) async {
      await _mount(tester, const QueryPage());
      expect(find.text('Loaded 6 posts'), findsOneWidget);
      await tester.tap(find.text('Even IDs'));
      await tester.pumpAndSettle();
      expect(find.text('Loaded 3 posts'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      await tester.tap(find.text('Refetch'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byTooltip('Replay').first);
      await tester.pump();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Loaded 6 posts'), findsOneWidget);
      await _unmount(tester);
    },
  );

  testWidgets('failed query retries and replay repeats the first failure', (
    tester,
  ) async {
    await _mount(tester, const QueryPage());
    expect(find.text('Simulated failure'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Simulated failure'), findsNothing);
    expect(find.text('Loaded 6 posts'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Replay').last);
    await tester.pumpAndSettle();
    expect(find.text('Simulated failure'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets(
    'mutation validates, succeeds, resets, fails and replays form state',
    (tester) async {
      await _mount(tester, const MutationPage());
      final submit = find.widgetWithText(FilledButton, 'Submit');
      expect(tester.widget<FilledButton>(submit.first).onPressed, isNull);
      await tester.enterText(find.byType(TextField).first, 'A local title');
      await tester.pump();
      await tester.tap(submit.first);
      await tester.pumpAndSettle();
      expect(find.text('Created: A local title'), findsOneWidget);
      await tester.tap(find.text('Reset').first);
      await tester.pumpAndSettle();
      expect(find.text('Idle'), findsNWidgets(2));
      await tester.enterText(find.byType(TextField).last, 'Keep this title');
      await tester.pump();
      await tester.tap(submit.last);
      await tester.pumpAndSettle();
      expect(find.text('Simulated failure'), findsOneWidget);
      expect(find.text('Keep this title'), findsOneWidget);
      await tester.tap(find.byTooltip('Replay').last);
      await tester.pumpAndSettle();
      expect(find.text('Keep this title'), findsNothing);
      expect(find.text('Simulated failure'), findsNothing);
      await _unmount(tester);
    },
  );

  testWidgets('pagination stops at the finite end and replay clears pages', (
    tester,
  ) async {
    await _mount(tester, const InfinitePage());
    expect(find.text('Pages: 1'), findsOneWidget);
    for (var page = 2; page <= 3; page++) {
      await tester.tap(find.widgetWithText(FilledButton, 'Load more'));
      await tester.pumpAndSettle();
      expect(find.text('Pages: $page'), findsOneWidget);
    }
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'End of feed'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('Replay'));
    await tester.pumpAndSettle();
    expect(find.text('Pages: 1'), findsOneWidget);
    expect(find.text('Post 5 · Post 6'), findsNothing);
    await _unmount(tester);
  });

  testWidgets(
    'parallel combine and in-flight counter follow invalidation and replay',
    (tester) async {
      await _mount(tester, const QueriesPage());
      expect(find.text('Ready: 2 / 2 · Fetching: 0'), findsOneWidget);
      await tester.tap(find.text('Invalidate both'));
      await tester.pump();
      expect(find.text('Ready: 2 / 2 · Fetching: 2'), findsOneWidget);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Replay'));
      await tester.pump();
      expect(find.text('Ready: 0 / 2 · Fetching: 2'), findsOneWidget);
      await tester.pump(_requestWait);
      expect(find.text('Ready: 1 / 2 · Fetching: 1'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Ready: 2 / 2 · Fetching: 0'), findsOneWidget);
      await _unmount(tester);
    },
  );

  testWidgets(
    'viewmodel delete invalidates data; scope replay resets its revision',
    (tester) async {
      await _mount(tester, const ViewModelPage());
      final original = find.text(
        'Post 1 · Post 2 · Post 3 · Post 4 · Post 5 · Post 6',
      );
      expect(original, findsOneWidget);
      await tester.tap(find.text('Delete first'));
      await tester.pumpAndSettle();
      expect(original, findsNothing);
      expect(find.text('Deleted post 1'), findsOneWidget);
      await tester.tap(find.byTooltip('Replay').first);
      await tester.pumpAndSettle();
      expect(original, findsOneWidget);
      await tester.tap(find.text('Invalidate scope'));
      await tester.pumpAndSettle();
      expect(find.text('Revision: 2'), findsOneWidget);
      await tester.tap(find.byTooltip('Replay').last);
      await tester.pumpAndSettle();
      expect(find.text('Revision: 1'), findsOneWidget);
      await _unmount(tester);
      expect(Get.isRegistered<PostsViewModel>(), isFalse);
    },
  );

  testWidgets(
    'unmount during requests and mutation does not update disposed widgets',
    (tester) async {
      await _mount(tester, const ViewModelPage());
      await tester.tap(find.text('Delete first'));
      await tester.pump();
      await _unmount(tester);
      await _mount(tester, const QueryPage());
      await tester.tap(find.byTooltip('Replay').first);
      await tester.pump();
      await _unmount(tester);
    },
  );

  testWidgets('every dynamic card replays safely while work is in flight', (
    tester,
  ) async {
    final pages = <Widget>[
      const QueryPage(),
      const MutationPage(),
      const InfinitePage(),
      const QueriesPage(),
      const ViewModelPage(),
    ];
    for (final page in pages) {
      await _mount(tester, page);
      final replayCount = find.byTooltip('Replay').evaluate().length;
      for (var index = 0; index < replayCount; index++) {
        if (page is MutationPage) {
          await tester.enterText(
            find.byType(TextField).at(index),
            'Pending title',
          );
          await tester.pump();
          await tester.tap(
            find.widgetWithText(FilledButton, 'Submit').at(index),
          );
          await tester.pump();
        }
        await tester.tap(find.byTooltip('Replay').at(index));
        await tester.pump();
        await tester.tap(find.byTooltip('Replay').at(index));
        await tester.pumpAndSettle();
      }
      await _unmount(tester);
    }
  });

  for (final width in [375.0, 1440.0]) {
    for (final language in ['en', 'zh']) {
      testWidgets('all pages, code, theme and replay at $width / $language', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, width == 375 ? 667 : 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final locale = DemoLocale(
          uri: Uri.parse('https://example.test/?lang=$language'),
        );
        for (final page in _pages) {
          await tester.pumpWidget(
            GetxQueryDemoApp(
              key: ValueKey('$page-$width-$language'),
              locale: locale,
              initialFragment: '/pages/$page',
            ),
          );
          await tester.pumpAndSettle();
          final cards = tester
              .widgetList<DemoCard>(find.byType(DemoCard))
              .toList();
          expect(cards.length, 2);
          expect(
            find.byTooltip(language == 'en' ? 'Replay' : '重放'),
            findsNWidgets(cards.where((card) => card.replayable).length),
          );
          // 首屏能操作演示，手机还能看到第二张卡片标题。
          final controls = find.byType(FilledButton).hitTestable();
          expect(controls, findsWidgets);
          if (width == 375) {
            final second = find.byType(DemoCard).last;
            expect(tester.getTopLeft(second).dy, lessThan(667));
          }
          await tester.tap(
            find.byTooltip(language == 'en' ? 'Toggle theme' : '切换亮暗'),
          );
          await tester.pumpAndSettle();
          final code = find.byType(CodeBlock).first;
          await tester.ensureVisible(code);
          await tester.tap(
            find.descendant(of: code, matching: find.byType(ExpansionTile)),
          );
          await tester.pumpAndSettle();
          expect(
            find.text(language == 'en' ? 'Copy code' : '复制代码'),
            findsWidgets,
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '$page / $width / $language',
          );
          await _unmount(tester);
        }
        locale.dispose();
      });
    }
  }

  testWidgets(
    'application navigation and external URLs retain current package paths',
    (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add(call.arguments['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(const GetxQueryDemoApp());
      await tester.pumpAndSettle();
      for (final tooltip in ['pub.dev', 'GitHub', 'Read documentation']) {
        await tester.tap(find.byTooltip(tooltip));
        await tester.pump();
      }
      expect(copied, [
        'https://pub.dev/packages/getx_query',
        'https://github.com/icodejoo/dart-labs/tree/main/getx-query',
        'https://github.com/icodejoo/dart-labs/blob/main/getx-query/README.md',
      ]);
      await _unmount(tester);
    },
  );
}
