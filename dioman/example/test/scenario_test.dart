import 'dart:io';
import 'package:dioman_demo/demo_kit/demo_kit.dart';
import 'package:dioman_demo/main.dart';
import 'package:dioman_demo/scenario_page.dart';
import 'package:dioman_demo/scenario_runtime.dart';
import 'package:dioman_demo/scenarios.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 测试使用的显式英文地址。
const _englishUrl = 'https://demo.invalid/?lang=en';

/// 模拟延迟逐帧推进，允许请求与后续微任务各自安排下一步。
Future<void> _finish(WidgetTester tester) async {
  for (var frame = 0; frame < 24; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 创建只有一个场景的真实可重放卡片。
Widget _card(DemoScenario scenario, {DemoLocale? locale}) => DemoApp(
      title: scenario.id,
      seedColor: Colors.blue,
      locale: locale,
      home: Scaffold(
          body: DemoCard(
        title: scenario.title.en,
        description: scenario.description.en,
        replayable: scenario.replayable,
        child: ScenarioView(scenario: scenario),
      )),
    );

/// 验证线上清单中的每个执行器、清理路径与响应式页面。
void main() {
  test('version chip exactly matches package pubspec', () {
    final version = RegExp(r'^version:\s*(\S+)', multiLine: true)
        .firstMatch(File('../pubspec.yaml').readAsStringSync())!
        .group(1);
    expect(demoVersion, version);
  });

  /// 各场景末条日志的实际行为断言。
  const expected = {
    'repath': '/users/42',
    'filter': 'page: 0, active: false',
    'mock': '204',
    'result': '10001',
    'decode': '42 / null / 200',
    'cache': '\n3',
    'share': '3 / 1',
    'retry': 'true',
    'auth': '1 / true',
    'loading': '\n0',
    'cancel': '\n3',
    'offline': 'true',
    'deadline': 'true',
    'envs': 'prod.example.invalid',
    'timeout': '0:00:03.000000',
    'breaker': '500 / breaker / 1',
    'notify': '2 / 1',
    'trace': 'demo:trace',
  };
  for (final group in demoGroups) {
    for (final scenario in group.scenarios) {
      testWidgets(
          '${scenario.id}: actual pipeline result, fresh replay and cleanup',
          (tester) async {
        final locale = DemoLocale(uri: Uri.parse(_englishUrl));
        await tester.pumpWidget(_card(scenario, locale: locale));
        await _finish(tester);
        expect(find.text('Completed'), findsOneWidget);
        expect(find.textContaining('Unexpected demo error'), findsNothing);
        final logFinder = find.descendant(
            of: find.byKey(ValueKey('log-${scenario.id}')),
            matching: find.byType(Text));
        final before = tester.widget<Text>(logFinder).data!;
        expect(before, contains(expected[scenario.id]!));
        if (scenario.id == 'deadline') {
          expect(before, contains('timeout / deadline'));
        }
        if (scenario.id == 'loading') {
          expect(before, contains('Active logical requests\n3'));
          expect(before, contains('Loading visibility\ntrue'));
          expect(before, contains('Loading visibility\nfalse'));
        }
        if (scenario.id == 'result') {
          expect(before, contains('false / 200 / 10001 / null'));
        }
        if (scenario.id == 'cache') {
          expect(
              before,
              contains(
                  'Server calls so far\n1\nServer calls so far\n1\nServer calls so far\n2'));
        }
        if (scenario.replayable) {
          await tester.tap(find.byTooltip('Replay'));
          await _finish(tester);
          expect(tester.widget<Text>(logFinder).data, before);
        } else {
          expect(find.byTooltip('Replay'), findsNothing);
        }
        locale.select('zh');
        await tester.pump();
        expect(find.text('已完成'), findsOneWidget);
        expect(find.byTooltip('重放'),
            scenario.replayable ? findsOneWidget : findsNothing);
        expect(tester.widget<Text>(logFinder).data, isNot(before));
        await tester.pumpWidget(const SizedBox());
        await _finish(tester);
        expect(tester.takeException(), isNull);
        locale.dispose();
      });
    }
  }

  for (final id in [
    'share',
    'retry',
    'auth',
    'loading',
    'cancel',
    'offline',
    'deadline'
  ]) {
    testWidgets(
        '$id: rapid replay and leaving while pending produces no stale output',
        (tester) async {
      final scenario =
          demoGroups.expand((g) => g.scenarios).firstWhere((s) => s.id == id);
      final locale = DemoLocale(uri: Uri.parse(_englishUrl));
      await tester.pumpWidget(_card(scenario, locale: locale));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byTooltip('Replay'));
      await tester.pump();
      await tester.tap(find.byTooltip('Replay'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await _finish(tester);
      expect(tester.takeException(), isNull);
      locale.dispose();
    });
  }

  for (final width in [360.0, 375.0, 667.0, 900.0, 1024.0, 1440.0, 1600.0]) {
    testWidgets('all pages and languages fit width $width', (tester) async {
      tester.view.physicalSize = Size(width, width < 600 ? 667 : 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final group in demoGroups) {
        final locale = DemoLocale(uri: Uri.parse(_englishUrl));
        await tester.pumpWidget(DiomanDemoApp(
          key: ValueKey('$width-${group.id}'),
          locale: locale,
          initialFragment: '/pages/${group.id}',
        ));
        await _finish(tester);
        expect(find.byType(DemoCard), findsNWidgets(group.scenarios.length));
        expect(find.byType(CodeBlock), findsOneWidget);
        expect(find.byTooltip('Replay'),
            findsNWidgets(group.scenarios.where((s) => s.replayable).length));
        final first = tester.getRect(find.byType(DemoCard).first);
        final second = tester.getRect(find.byType(DemoCard).at(1));
        expect(first.left, greaterThanOrEqualTo(0));
        expect(first.right, lessThanOrEqualTo(width));
        if (width == 375) expect(second.top, lessThan(667));
        if (width == 1440) {
          expect(first.top, second.top);
          expect(first.height, second.height);
          expect(tester.getRect(find.byType(DemoCard).at(2)).top, first.top);
        }
        locale.select('zh');
        await tester.pumpAndSettle();
        expect(find.text(group.title.zh), findsWidgets);
        expect(tester.takeException(), isNull,
            reason: '${group.id}, width $width');
        await tester.pumpWidget(const SizedBox());
        await _finish(tester);
        locale.dispose();
      }
    });
  }

  testWidgets('session waits and close are idempotent, late logs stay silent',
      (tester) async {
    final messages = <DemoText>[];
    final session = DemoSession(messages.add);
    final waiting = session.wait(const Duration(hours: 1));
    final closing = session.close();
    expect(session.close(), same(closing));
    await waiting;
    await closing;
    await session.wait(const Duration(hours: 1));
    session.log('late', '迟到');
    expect(messages, isEmpty);
    expect(session.closed, isTrue);
  });
}
