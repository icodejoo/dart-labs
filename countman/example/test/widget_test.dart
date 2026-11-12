import 'dart:io';
import 'package:countman/countman.dart';
import 'package:example/main.dart';
import 'package:example/demo_kit/demo_kit.dart';
import 'package:example/demo_samples.dart';
import 'package:example/sample_code.dart';
import 'package:example/bench_entry_native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 覆盖线上页面的真实组件、窄屏溢出与交互生命周期。
void main() {
  const pages = [
    'counter',
    'countdown',
    'elapsed',
    'renderers',
    'advanced',
    'providers',
  ];
  for (final width in <double>[375, 1440]) {
    for (final page in pages) {
      testWidgets('$page builds at $width', (tester) async {
        tester.view.physicalSize = Size(width, width == 375 ? 667 : 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final locale = DemoLocale(uri: Uri.parse('https://test/?lang=en'));
        await tester.pumpWidget(
          CountmanDemoApp(initialFragment: '/pages/$page', locale: locale),
        );
        await tester.pump(const Duration(milliseconds: 250));
        locale.select('zh');
        await tester.pump(const Duration(milliseconds: 250));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        Countman.destroy();
        locale.dispose();
      });
    }
  }

  testWidgets('counter and countdown controls respond', (tester) async {
    final locale = DemoLocale(uri: Uri.parse('https://test/?lang=en'));
    await tester.pumpWidget(CountmanDemoApp(locale: locale));
    await tester.pump();
    await tester.tap(find.text('Change value'));
    await tester.pump();
    expect(
      tester.widget<AnimatedCounter>(find.byType(AnimatedCounter).first).value,
      2469,
    );
    await tester.pumpWidget(const SizedBox());
    Countman.destroy();
    await tester.pumpWidget(
      CountmanDemoApp(initialFragment: '/pages/countdown', locale: locale),
    );
    await tester.pump();
    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(find.text('Resume'), findsOneWidget);
    await tester.tap(find.text('Restart'));
    await tester.pump();
    expect(find.text('Pause'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    Countman.destroy();
    locale.dispose();
  });

  test('displayed snippets match the compiled live source', () {
    final source = File(
      'lib/demo_samples.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final prelude = source.substring(0, source.indexOf('// sample:')).trim();
    final samples = RegExp(
      r'// sample:([^\n]+)\n(.*?)// end-sample',
      dotAll: true,
    ).allMatches(source);
    for (final sample in samples) {
      expect(
        sampleCode[sample.group(1)!.trim()],
        '$prelude\n\n${sample.group(2)!.trim()}',
      );
    }
    expect(
      sampleCode['pomodoro'],
      File(
        'lib/pomodoro_plugin.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n'),
    );
  });

  test('probe observes without requesting frames', () {
    var requests = 0;
    final probe = WakeProbePlugin();
    probe.onAttach(CountmanContext(requestFrame: () => requests++));
    expect(probe.tick(Duration.zero, Duration.zero), CountmanPlugin.idle);
    expect(probe.wakes, 1);
    expect(requests, 0);
    probe.onDetach();
    probe.dispose();
  });

  test('native benchmark routes preserve script compatibility', () {
    final app = buildBenchApp('/benchmark') as MaterialApp;
    expect(app.initialRoute, '/benchmark');
    expect(
      app.routes!.keys,
      containsAll(['/benchmark', '/perf', '/digit-test']),
    );
    expect((buildBenchApp('/') as MaterialApp).initialRoute, '/benchmark');
  });

  testWidgets(
    'advanced controls restore globals and deliver hidden completion',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final locale = DemoLocale(uri: Uri.parse('https://test/?lang=en'));
      Countman.fps = 30;
      Countman.muteWhenHidden = true;
      final previousClock = CountmanClock.system;
      final clock = ManualCountmanClock();
      CountmanClock.system = clock;
      addTearDown(() => CountmanClock.system = previousClock);
      await tester.pumpWidget(
        CountmanDemoApp(initialFragment: '/pages/advanced', locale: locale),
      );
      await tester.pump();
      await tester.tap(find.text('Read counts'));
      await tester.pump();
      expect(find.textContaining('Scheduler wakes:'), findsOneWidget);
      await tester.ensureVisible(find.byType(DropdownButton<double>));
      await tester.tap(find.byType(DropdownButton<double>));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('5 fps').last);
      await tester.pump();
      expect(Countman.fps, 5);
      await tester.ensureVisible(find.text('Hide timer'));
      await tester.tap(find.text('Hide timer'));
      clock.advance(const Duration(seconds: 9));
      await tester.pump(const Duration(seconds: 9));
      await tester.pump();
      expect(find.textContaining('Completions: 1'), findsOneWidget);
      await tester.tap(find.text('Show timer'));
      await tester.pump();
      await tester.ensureVisible(find.text('Start / restart'));
      await tester.tap(find.text('Start / restart'));
      await tester.pump();
      expect(find.textContaining('Focus ·'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(Countman.fps, 30);
      expect(Countman.muteWhenHidden, isTrue);
      Countman.fps = null;
      Countman.destroy();
      locale.dispose();
    },
  );

  test(
    'combined snippets retain one import prelude and cache API is callable',
    () {
      final code = combineSampleCode(['counter', 'text-counter']);
      expect('import '.allMatches(code), hasLength(2));
      setDemoFps(15);
      expect(Countman.fps, 15);
      setDemoFps(null);
      clearDemoBitmapCaches();
    },
  );
}
