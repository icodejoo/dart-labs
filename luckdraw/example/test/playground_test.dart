import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/wheel.dart';
import 'package:luckdraw_example/demo_kit/demo_kit.dart';
import 'package:luckdraw_example/main.dart' as app;
import 'package:luckdraw_example/online/localized_config.dart';
import 'package:luckdraw_example/pages/capsule_page.dart';
import 'package:luckdraw_example/pages/compat_page.dart';
import 'package:luckdraw_example/pages/grid_page.dart';
import 'package:luckdraw_example/pages/lever_page.dart';
import 'package:luckdraw_example/pages/lots_page.dart';
import 'package:luckdraw_example/pages/lotto_page.dart';
import 'package:luckdraw_example/pages/number_wheel_page.dart';
import 'package:luckdraw_example/pages/overlay_page.dart';
import 'package:luckdraw_example/pages/slot_page.dart';
import 'package:luckdraw_example/pages/wheel_page.dart';

/// 布局测试使用的固定版本；真实版本另由清单测试验证。
const _fixtureVersion = '0.1.1';

/// 通过 URL 参数固定测试语言。
const _testUrl = 'https://example.test/?lang=';

/// 只在显式截图模式下导出本次构建的真实 Widget 画面。
Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['DEMO_CAPTURE_DIR'];
  if (directory == null) return;
  final boundary = tester
      .renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File('$directory/$name.png')
          .writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

/// 覆盖每种玩法、物理模式和扩展演示。
const _scenarios = <(String, Widget)>[
  ('wheel', WheelPage()),
  ('grid', GridPage()),
  ('slot', SlotPage()),
  ('lever', LeverPage()),
  ('capsule', CapsulePage()),
  ('number', NumberWheelPage()),
  ('lots', LotsPage()),
  ('lotto', LottoPage()),
  ('capsule physics', CapsulePage(initialPhysics: true)),
  ('lotto physics', LottoPage(initialPhysics: true)),
  ('compat', CompatPage()),
  ('overlay', OverlayPage()),
];

/// 取出原页面拥有的公开控制器阶段，避免只验证界面文本。
ValueListenable<LuckyPhase> _phase(WidgetTester tester, Widget page) =>
    switch (page) {
      WheelPage() =>
        tester.state<WheelPageState>(find.byType(WheelPage)).controller.phase,
      GridPage() =>
        tester.state<GridPageState>(find.byType(GridPage)).controller.phase,
      SlotPage() =>
        tester.state<SlotPageState>(find.byType(SlotPage)).controller.phase,
      LeverPage() =>
        tester.state<LeverPageState>(find.byType(LeverPage)).controller.phase,
      CapsulePage() => tester
          .state<CapsulePageState>(find.byType(CapsulePage))
          .controller
          .phase,
      NumberWheelPage() => tester
          .state<NumberWheelPageState>(find.byType(NumberWheelPage))
          .controller
          .phase,
      LotsPage() =>
        tester.state<LotsPageState>(find.byType(LotsPage)).controller.phase,
      LottoPage() =>
        tester.state<LottoPageState>(find.byType(LottoPage)).controller.phase,
      _ => tester
          .widget<ValueListenableBuilder<LuckyPhase>>(
              find.byType(ValueListenableBuilder<LuckyPhase>))
          .valueListenable,
    };

/// 推进真实 Widget 帧直到本轮开奖，超时表示演示不能完成。
Future<void> _settleDraw(
    WidgetTester tester, ValueListenable<LuckyPhase> phase) async {
  for (var frame = 0;
      frame < 400 && phase.value != LuckyPhase.settled;
      frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(phase.value, LuckyPhase.settled);
}

/// 验证布局、双语、公开配置、资源释放与每种演示的重放闭环。
void main() {
  setUpAll(() async {
    if (Platform.environment['DEMO_CAPTURE_DIR'] == null) return;
    for (final (family, file) in [
      ('Roboto', 'C:/Windows/Fonts/msyh.ttc'),
      ('Microsoft YaHei', 'C:/Windows/Fonts/msyh.ttc'),
      (
        'MaterialIcons',
        'E:/sdk/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf'
      ),
    ]) {
      final path = File(file);
      if (path.existsSync()) {
        await (FontLoader(family)
              ..addFont(
                  Future.value(ByteData.sublistView(await path.readAsBytes()))))
            .load();
      }
    }
  });
  for (final width in [375.0, 1440.0]) {
    testWidgets('visual capture at $width', (tester) async {
      if (Platform.environment['DEMO_CAPTURE_DIR'] == null) return;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, width == 375 ? 667 : 900);
      addTearDown(tester.view.reset);
      for (final language in ['en', 'zh']) {
        final locale = DemoLocale(uri: Uri.parse('$_testUrl$language'));
        await tester.pumpWidget(RepaintBoundary(
            child: app.LuckdrawDemo(
          key: UniqueKey(),
          version: _fixtureVersion,
          locale: locale,
        )));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
        await _capture(tester, '${width.toInt()}-$language');
        await tester.pumpWidget(const SizedBox());
        locale.dispose();
      }
    });
  }

  testWidgets('version asset is the current package manifest', (tester) async {
    final expected = RegExp(r'^version:\s*(\S+)', multiLine: true)
        .firstMatch(File('../pubspec.yaml').readAsStringSync())!
        .group(1);
    expect(await app.loadPackageVersion(), expected);
  });

  for (final width in [375.0, 600.0, 900.0, 1000.0, 1440.0, 1600.0]) {
    for (final language in ['en', 'zh']) {
      testWidgets('all routes fit $width / $language in both themes',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, width == 375 ? 667 : 900);
        addTearDown(tester.view.reset);
        final locale = DemoLocale(uri: Uri.parse('$_testUrl$language'));
        for (final brightness in Brightness.values) {
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          for (final (route, count) in [
            ('games', 8),
            ('physics', 2),
            ('integration', 2)
          ]) {
            await tester.pumpWidget(app.LuckdrawDemo(
              key: UniqueKey(),
              version: _fixtureVersion,
              locale: locale,
              fragment: '/pages/$route',
            ));
            await tester.pump(const Duration(milliseconds: 100));
            expect(find.byType(DemoCard), findsNWidgets(count));
            expect(find.byTooltip(language == 'en' ? 'Replay' : '重放'),
                findsNWidgets(count));
            expect(tester.takeException(), isNull,
                reason: '$route/$brightness');
            for (final element in find.byType(Text).evaluate()) {
              final text = (element.widget as Text).data ?? '';
              expect(
                  RegExp(r'REL|B17b|STEADY|INSTR|DEVFIN|MET2').hasMatch(text),
                  isFalse);
              if (language == 'en' && text != '中文') {
                expect(RegExp(r'[\u4e00-\u9fff]').hasMatch(text), isFalse,
                    reason: text);
              }
            }
            if (route == 'games' && width == 375) {
              final second = tester.getTopLeft(find.byType(DemoCard).at(1));
              expect(second.dy, lessThan(667), reason: '首屏可见第二张卡片标题');
            }
            await tester.pumpWidget(const SizedBox());
            await tester.pump();
            expect(tester.binding.transientCallbackCount, 0);
          }
        }
        tester.platformDispatcher.clearPlatformBrightnessTestValue();
        locale.dispose();
      });
    }
  }

  for (final (name, page) in _scenarios) {
    testWidgets('$name settles, replays while moving, and starts another round',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 667);
      addTearDown(tester.view.reset);
      final locale = DemoLocale(uri: Uri.parse('${_testUrl}en'));
      await tester.pumpWidget(DemoApp(
        title: name,
        seedColor: Colors.blue,
        locale: locale,
        home: Scaffold(
            body: SingleChildScrollView(
                child: DemoCard(
          title: name,
          description: 'Draw and replay',
          child: page,
        ))),
      ));
      await tester.pump();
      var phase = _phase(tester, page);
      final originalOwner = tester.state(find.byType(page.runtimeType));
      expect(phase.value, LuckyPhase.idle);
      expect(
          tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
          isNull);
      await tester.tap(find.text('Start'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Server result'));
      await _settleDraw(tester, phase);
      expect(find.textContaining('Result: '), findsOneWidget);
      await tester.tap(find.text('Start'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byTooltip('Replay'));
      await tester.pump();
      expect(originalOwner.mounted, isFalse);
      phase = _phase(tester, page);
      expect(phase.value, LuckyPhase.idle);
      expect(find.textContaining('Result: '), findsNothing);
      await tester.tap(find.text('Start'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Server result'));
      await _settleDraw(tester, phase);
      expect(find.textContaining('Result: '), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      locale.dispose();
    });
  }

  testWidgets(
      'canvas translation preserves native config and switches language',
      (tester) async {
    final locale = DemoLocale(uri: Uri.parse('${_testUrl}en'));
    late WheelConfig translated;
    await tester.pumpWidget(DemoApp(
      title: 'canvas',
      seedColor: Colors.blue,
      locale: locale,
      home: Builder(builder: (context) {
        translated = demoConfig(context, WheelPageState.config);
        return const SizedBox();
      }),
    ));
    expect(translated.prizes.first.texts.first.text, 'Try again');
    expect(translated.buttons.last.texts.first.text, 'Start');
    expect(translated.prizes.first.painter,
        WheelPageState.config.prizes.first.painter);
    locale.select('zh');
    await tester.pump();
    expect(translated.prizes.first.texts.first.text, '谢谢参与');
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      expect(
          identical(demoConfig(context, WheelPageState.config),
              WheelPageState.config),
          isTrue);
      return const SizedBox();
    })));
    locale.dispose();
  });
}
