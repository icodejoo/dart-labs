import 'dart:async';
import 'dart:io';
import 'package:ffuzzy/ffuzzy.dart';
import 'package:ffuzzy_example/constructors_page.dart';
import 'package:ffuzzy_example/demo_data.dart';
import 'package:ffuzzy_example/demo_kit/demo_kit.dart';
import 'package:ffuzzy_example/lifecycle_page.dart';
import 'package:ffuzzy_example/main.dart';
import 'package:ffuzzy_example/package_version.dart';
import 'package:ffuzzy_example/search_page.dart';
import 'package:ffuzzy_example/search_specs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 为小组件提供统一的英语环境。
Widget _host(Widget child) => DemoApp(
      title: projectName,
      seedColor: Colors.blue,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

/// 让真实 isolate 有机会完成，再处理界面更新。
Future<void> _finish(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
    if (find.text('Working…').evaluate().isEmpty &&
        find.text('Searching…').evaluate().isEmpty) {
      break;
    }
  }
  await tester.pumpAndSettle();
}

/// 验证真实 API、双语页面、响应式布局与重放资源寿命。
void main() {
  test('version chip matches the current package pubspec', () {
    final pubspec = File('../pubspec.yaml').readAsStringSync();
    expect(
        RegExp(r'^version: (.+)$', multiLine: true)
            .firstMatch(pubspec)!
            .group(1)!
            .trim(),
        packageVersion);
  });

  for (final width in <double>[375, 1440]) {
    for (final language in ['en', 'zh']) {
      testWidgets('all pages fit $width in $language', (tester) async {
        tester.view.physicalSize = Size(width, width == 375 ? 667 : 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final locale =
            DemoLocale(uri: Uri.parse('https://test/?lang=$language'));
        for (final page in [
          'search',
          'lifecycle',
          'constructors',
          'benchmark'
        ]) {
          await tester.pumpWidget(FuzzyDemoApp(
              locale: locale,
              initialFragment: '/pages/$page',
              key: ValueKey(page)));
          await tester.pumpAndSettle();
          expect(find.text(packageVersion), findsOneWidget);
          expect(tester.takeException(), isNull,
              reason: '$page $width $language');
          final cards = find.byType(DemoCard);
          expect(cards, findsWidgets);
          if (page == 'search') {
            final fields = find.byType(TextField);
            expect(tester.getRect(fields.first).top, lessThan(667));
            if (width == 375) {
              expect(tester.getRect(cards.at(1)).top, lessThan(667));
            }
            if (width == 1440) {
              expect(tester.getTopLeft(cards.at(0)).dy,
                  tester.getTopLeft(cards.at(2)).dy);
            }
          }
          if (page == 'constructors') {
            expect(find.byTooltip(language == 'en' ? 'Replay' : '重放'),
                findsNWidgets(3));
          }
        }
        await tester.pumpWidget(const SizedBox());
        locale.dispose();
      });
    }
  }

  for (final spec in searchSpecs) {
    testWidgets('${spec.name} supports every offered API variant',
        (tester) async {
      final corpus = FuzzyCorpus.strings(demoItems, matchPaths: true);
      final calls = <Object>[
        spec.hits(corpus, spec.query),
        if (spec.raws != null) spec.raws!(corpus, spec.query),
      ];
      await tester.runAsync(() async {
        calls.add(await spec.asyncHits(corpus, spec.query));
        if (spec.asyncRaws != null) {
          calls.add(await spec.asyncRaws!(corpus, spec.query));
        }
      });
      for (final result in calls) {
        await tester.pumpWidget(_host(SearchResults(result: result)));
        await tester.pumpAndSettle();
        if (result is FuzzyDualResult<String>) {
          expect(result.approx, isNotEmpty);
          expect(find.text('No matches'), findsOneWidget);
        } else {
          expect(find.text('No matches'), findsNothing, reason: spec.name);
        }
        expect(tester.takeException(), isNull);
      }
      corpus.dispose();
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('search query, raw and async variants reset independently',
      (tester) async {
    await tester.pumpWidget(_host(DemoCard(
        title: 'search',
        description: 'test',
        child: SearchDemo(spec: searchSpecs.first))));
    await tester.enterText(find.byType(TextField), 'readme');
    await tester.pumpAndSettle();
    expect(find.text('README.md', findRichText: true), findsOneWidget);
    expect(find.text('CHANGELOG.md', findRichText: true), findsNothing);
    await tester.tap(find.byType(DropdownButtonFormField<SearchVariant>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Async raw objects').last);
    await _finish(tester);
    expect(find.text('README.md', findRichText: true), findsOneWidget);
    await tester.tap(find.byTooltip('Replay'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        searchSpecs.first.query);
    expect(find.text('Hits'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('late async result is ignored after replay', (tester) async {
    final pending = Completer<Object>();
    var calls = 0;
    final base = searchSpecs.first;
    final spec = SearchSpec(
        base.name, base.en, base.zh, base.query, base.hits, base.raws,
        (corpus, query) {
      calls++;
      return pending.future;
    }, null, base.code);
    await tester.pumpWidget(_host(DemoCard(
        title: 'async', description: 'test', child: SearchDemo(spec: spec))));
    await tester.tap(find.byType(DropdownButtonFormField<SearchVariant>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Async hits').last);
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.tap(find.byTooltip('Replay'));
    await tester.pump();
    pending.complete(<String>['stale']);
    await tester.pumpAndSettle();
    expect(find.text('stale', findRichText: true), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final action in CorpusAction.values) {
    testWidgets('${action.name} applies and replay restores its corpus',
        (tester) async {
      await tester.pumpWidget(_host(DemoCard(
          title: action.name,
          description: 'test',
          child: CorpusDemo(action: action))));
      final initialLength =
          action == CorpusAction.asyncBuild ? 0 : lifecycleItems.length;
      expect(find.text('Length: $initialLength'), findsOneWidget);
      await tester.tap(find.text('Run'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await _finish(tester);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Operation failed. Replay to retry.'), findsNothing);
      if (action == CorpusAction.dispose ||
          action == CorpusAction.asyncDispose) {
        expect(find.text('Disposed; further use throws StateError.'),
            findsOneWidget);
      } else {
        final expectedLength = switch (action) {
          CorpusAction.add || CorpusAction.addKey => 4,
          CorpusAction.addAll || CorpusAction.asyncAddAll => 5,
          CorpusAction.removeAt ||
          CorpusAction.removeWhere ||
          CorpusAction.refresh =>
            2,
          CorpusAction.clear => 0,
          _ => 3,
        };
        expect(find.text('Length: $expectedLength'), findsOneWidget);
      }
      if (action == CorpusAction.addKey) {
        expect(find.text('Matched kind code: 1'), findsOneWidget);
      }
      if (action == CorpusAction.removeWhere) {
        expect(find.text('Removed: 1'), findsOneWidget);
      }
      await tester.tap(find.byTooltip('Replay'));
      await tester.pumpAndSettle();
      expect(find.text('Length: $initialLength'), findsOneWidget);
      expect(find.text('Run'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('benchmark measures fresh input and can replay while building',
      (tester) async {
    await tester.pumpWidget(_host(const DemoCard(
        title: 'build',
        description: 'test',
        child: CorpusDemo(action: CorpusAction.asyncBuild, benchmark: true))));
    await tester.tap(find.text('Run'));
    await tester.tap(find.byTooltip('Replay'));
    await _finish(tester);
    expect(find.text('Length: 0'), findsOneWidget);
    await tester.tap(find.text('Run'));
    await _finish(tester);
    expect(find.text('Length: $benchmarkSize'), findsOneWidget);
    expect(find.textContaining('Build time:'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('invalid approximate query reports an error and replay recovers',
      (tester) async {
    final spec = searchSpecs.firstWhere((spec) => spec.name == 'approx');
    await tester.pumpWidget(_host(DemoCard(
        title: spec.name, description: 'test', child: SearchDemo(spec: spec))));
    await tester.enterText(find.byType(TextField), List.filled(65, 'a').join());
    await tester.pumpAndSettle();
    expect(find.text('Search failed. Check query limits and replay.'),
        findsOneWidget);
    await tester.tap(find.byTooltip('Replay'));
    await tester.pumpAndSettle();
    expect(find.text('Search failed. Check query limits and replay.'),
        findsNothing);
    expect(find.text('lib/src/widgets/scaffold.dart', findRichText: true),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'async results survive language and theme changes without reissuing',
      (tester) async {
    final pending = Completer<Object>();
    var calls = 0;
    final base = searchSpecs.first;
    final spec = SearchSpec(
        base.name, base.en, base.zh, base.query, base.hits, base.raws,
        (corpus, query) {
      calls++;
      return pending.future;
    }, null, base.code);
    final locale = DemoLocale(uri: Uri.parse('https://test/?lang=en'));
    await tester.pumpWidget(DemoApp(
        title: projectName,
        seedColor: Colors.blue,
        locale: locale,
        home: Scaffold(
            body: Builder(
                builder: (context) => Column(children: [
                      TextButton(
                          onPressed: DemoAppearance.of(context).toggle,
                          child: const Text('theme')),
                      DemoCard(
                          title: 'async',
                          description: tr(context, 'Description', '说明'),
                          child: SearchDemo(spec: spec)),
                    ])))));
    await tester.tap(find.byType(DropdownButtonFormField<SearchVariant>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Async hits').last);
    await tester.pumpAndSettle();
    locale.select('zh');
    await tester.tap(find.text('theme'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('搜索中…'), findsOneWidget);
    pending.complete(<String>['latest']);
    await tester.pumpAndSettle();
    expect(find.text('latest', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    locale.dispose();
  });

  for (final factory in CorpusFactory.values) {
    testWidgets('${factory.name} query survives rebuild and resets on replay',
        (tester) async {
      await tester.pumpWidget(_host(DemoCard(
          title: factory.name,
          description: 'test',
          child: FactoryDemo(factory: factory))));
      await tester.enterText(find.byType(TextField), 'zzzzzz');
      await tester.pumpAndSettle();
      expect(find.text('No matches'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'zzzzzz');
      await tester.tap(find.byTooltip('Replay'));
      await tester.pumpAndSettle();
      expect(find.text('No matches'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'Unicode highlights keep complete emoji and empty results translate',
      (tester) async {
    await tester.pumpWidget(_host(const UnicodeDemo()));
    expect(find.text('UTF-16: [0, 1, 3, 4, 5]'), findsOneWidget);
    final rich = tester.widget<Text>(find.byWidgetPredicate(
        (widget) => widget is Text && widget.textSpan != null));
    final spans = (rich.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(spans.map((span) => span.text).join(), UnicodeDemo.text);
    expect(
        spans
            .where((span) => span.style?.backgroundColor != null)
            .map((span) => span.text),
        ['😀', '中']);
    await tester.pumpWidget(_host(const SearchResults(result: <String>[])));
    expect(find.text('No matches'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
