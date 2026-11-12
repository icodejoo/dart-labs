import 'package:countman/countman.dart';
import 'package:example/benchmark_common.dart';
import 'package:example/benchmark_demo_page.dart';
import 'package:example/benchmark_page.dart';
import 'package:example/benchmark_panel_stub.dart' as web;
import 'package:example/bench_entry_native.dart';
import 'package:example/demo_kit/demo_kit.dart';
import 'package:example/digit_test_page.dart';
import 'package:example/main.dart';
import 'package:example/perf_page.dart';
import 'package:example/stress_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 测试用的英文语言地址。
const _englishUrl = 'https://test/?lang=en';

/// 共用显式开始标签。
const _startLabel = 'Start / restart';

/// 共用停止标签。
const _stopLabel = 'Stop';

/// 在完整语言和主题作用域内挂载待测页面。
Widget _app(Widget page, DemoLocale locale) => DemoApp(
  title: 'benchmarks',
  seedColor: Colors.blue,
  locale: locale,
  home: Scaffold(body: page),
);

/// 验证线上入口、空闲状态、显式控制与原生采样取消。
void main() {
  for (final page in <Widget>[
    const StressPage(),
    const PerfPage(),
    const DigitTestPage(),
  ]) {
    testWidgets(
      '${page.runtimeType} stays idle, starts and stops immediately',
      (tester) async {
        final locale = DemoLocale(uri: Uri.parse(_englishUrl));
        await tester.pumpWidget(_app(page, locale));
        await tester.pumpAndSettle();
        expect(find.byType(BenchmarkNotice), findsOneWidget);
        expect(
          tester
              .widgetList<AnimatedCounter>(find.byType(AnimatedCounter))
              .every((w) => w.value == 0),
          isTrue,
        );
        expect(tester.binding.transientCallbackCount, 0);
        await tester.ensureVisible(find.text(_startLabel));
        await tester.tap(find.text(_startLabel));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          tester
              .widgetList<AnimatedCounter>(find.byType(AnimatedCounter))
              .every((w) => (w.value ?? 0) > 0),
          isTrue,
        );
        expect(tester.binding.transientCallbackCount, greaterThan(0));
        await tester.ensureVisible(find.text(_stopLabel));
        await tester.tap(find.text(_stopLabel));
        await tester.pumpAndSettle();
        expect(
          tester
              .widgetList<AnimatedCounter>(find.byType(AnimatedCounter))
              .every((w) => w.value == 0),
          isTrue,
        );
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
        locale.select('zh');
        await tester.pump();
        expect(find.text('开始 / 重来'), findsOneWidget);
        expect(find.text('停止'), findsOneWidget);
        expect(find.textContaining('浏览器里的数字仅供参考'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        Countman.destroy();
        locale.dispose();
      },
    );
  }

  testWidgets('benchmark group is navigable in both languages', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final locale = DemoLocale(uri: Uri.parse(_englishUrl));
    await tester.pumpWidget(CountmanDemoApp(locale: locale));
    await tester.pump();
    expect(find.text('Benchmarks'), findsOneWidget);
    final shell = tester.widget<DemoShell>(find.byType(DemoShell));
    const ids = ['stress', 'perf', 'digit-test', 'benchmark'];
    expect(
      shell.destinations
          .where((d) => d.sectionEn == 'Benchmarks')
          .map((d) => d.id),
      ids,
    );
    for (final id in ids) {
      final item = shell.destinations.singleWhere((d) => d.id == id);
      await tester.ensureVisible(find.text(item.en));
      await tester.tap(find.text(item.en));
      await tester.pump();
      expect(find.byType(DemoPage), findsOneWidget);
      expect(find.byType(BenchmarkNotice), findsOneWidget);
    }
    locale.select('zh');
    await tester.pump();
    expect(find.text('压测'), findsOneWidget);
    expect(find.text('原生基准'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
    Countman.destroy();
    locale.dispose();
  });

  testWidgets('web fallback translates native desktop requirement', (
    tester,
  ) async {
    final locale = DemoLocale(uri: Uri.parse(_englishUrl));
    expect(web.nativeBenchmarkAvailable, isFalse);
    await tester.pumpWidget(_app(const web.BenchmarkUnavailable(), locale));
    expect(
      find.textContaining('This page requires a native desktop app.'),
      findsOneWidget,
    );
    locale.select('zh');
    await tester.pump();
    expect(find.textContaining('该页需桌面原生运行'), findsOneWidget);
    expect(find.byType(BenchmarkPage), findsNothing);
    expect(web.buildBenchmarkPanel(), isA<SizedBox>());
    await tester.pumpWidget(const SizedBox());
    locale.dispose();
  });

  for (final elapsed in [
    Duration.zero,
    const Duration(seconds: 1),
    const Duration(seconds: 4),
    const Duration(seconds: 20),
  ]) {
    testWidgets('native benchmark cancels safely after $elapsed', (
      tester,
    ) async {
      final locale = DemoLocale(uri: Uri.parse(_englishUrl));
      await tester.pumpWidget(_app(const BenchmarkDemoPage(), locale));
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(BenchmarkPage), findsNothing);
      await tester.tap(find.text(_startLabel));
      await tester.pump();
      expect(find.byType(BenchmarkPage), findsOneWidget);
      await tester.pump(elapsed);
      // 跨过预热边界后再 pump，使测试覆盖实际采样阶段。
      if (elapsed >= const Duration(seconds: 4)) {
        await tester.pump(const Duration(seconds: 3));
        await tester.pump(const Duration(milliseconds: 1));
      }
      await tester.ensureVisible(find.text(_stopLabel));
      await tester.tap(find.text(_stopLabel));
      await tester.pump();
      expect(find.byType(BenchmarkPage), findsNothing);
      await tester.pump(const Duration(seconds: 30));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      Countman.destroy();
      locale.dispose();
    });
  }

  testWidgets(
    'direct native benchmark is idle unless script explicitly opts in',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: BenchmarkPage()));
      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining('Press "Run A/B"'), findsOneWidget);
      expect(find.byType(CardCountdown), findsNothing);
      final app = buildBenchApp('/benchmark') as MaterialApp;
      final page =
          app.routes!['/benchmark']!(tester.element(find.byType(BenchmarkPage)))
              as BenchmarkPage;
      expect(page.autoStart, isTrue);
      expect(page.scripted, isTrue);
      expect((buildBenchApp('/') as MaterialApp).initialRoute, '/benchmark');
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'moving formatter stays exact at endpoints and for ordinary targets',
    () {
      final formatter = movingFormatter(benchmarkTarget, 1000);
      expect(formatter(0), '0');
      expect(formatter(benchmarkTarget), '${benchmarkTarget.toInt()}');
      const value = 123456.0;
      final displayed = int.parse(formatter(value));
      expect(value - displayed, inInclusiveRange(0, 999));
      expect(movingFormatter(value, 1000)(42), '42');
    },
  );
}
