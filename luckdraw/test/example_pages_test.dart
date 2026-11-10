// 独立 example 工程没有主包依赖声明；从主包测试其公开页面以纳入验收扫描。
// ignore_for_file: avoid_relative_lib_imports

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../example/lib/demo_shell.dart';
import '../example/lib/main.dart';
import '../example/lib/pages/capsule_page.dart';
import '../example/lib/pages/compat_page.dart';
import '../example/lib/pages/grid_page.dart';
import '../example/lib/pages/lever_page.dart';
import '../example/lib/pages/lots_page.dart';
import '../example/lib/pages/lotto_page.dart';
import '../example/lib/pages/number_wheel_page.dart';
import '../example/lib/pages/overlay_page.dart';
import '../example/lib/pages/slot_page.dart';
import '../example/lib/pages/wheel_page.dart';
import '../example/lib/theme/demo_theme.dart';
import 'support/fonts.dart';

/// 手机逻辑视口；截图固定以三倍像素密度输出。
const Size _phone = Size(390, 844);

/// 审计画布的定位键。
const Key _captureKey = ValueKey('style-capture');

/// 测试时注册系统中文字体；不复制、分发或声明字体资源。
Future<void> _loadChineseFont() async {
  final font = File('C:/Windows/Fonts/msyh.ttc');
  if (!font.existsSync()) return;
  final bytes = ByteData.sublistView(await font.readAsBytes());
  for (final family in ['Microsoft YaHei', 'sans-serif', 'Arial', 'Roboto']) {
    final loader = FontLoader(family)..addFont(Future.value(bytes));
    await loader.load();
  }
  final roboto = findLuckyTestFont(
    flutterRoot: Platform.environment['FLUTTER_ROOT'],
    executable: Platform.resolvedExecutable,
  );
  final icons =
      File.fromUri(roboto.parent.uri.resolve('materialicons-regular.otf'));
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(await icons.readAsBytes())));
  await loader.load();
}

/// 根据稳定的审计标识创建独立页面。
Widget _page(String name) => switch (name) {
      'wheel' => const WheelPage(),
      'grid' => const GridPage(),
      'slot' => const SlotPage(),
      'lever' => const LeverPage(),
      'capsule' => const CapsulePage(),
      'number_wheel' => const NumberWheelPage(),
      'lots' => const LotsPage(),
      'lotto' => const LottoPage(),
      'compat' => const CompatPage(),
      'overlay' => const OverlayPage(),
      _ => const LuckdrawExample(),
    };

/// 在显式审计模式保存自己的渲染结果，常规测试不写文件。
Future<void> _capture(WidgetTester tester, String name) async {
  final stage = Platform.environment['STYLE_CAPTURE'];
  if (stage == null) return;
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('docs/example_audit/$stage/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

/// 每页同时验证浅深主题、窄屏布局、业务控件和资源释放。
void main() {
  setUpAll(_loadChineseFont);
  for (final name in [
    'home',
    'wheel',
    'grid',
    'slot',
    'lever',
    'capsule',
    'number_wheel',
    'lots',
    'lotto',
    'compat',
    'overlay'
  ]) {
    testWidgets('example pages > $name fits phone in light and dark themes',
        (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = _phone * 3;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final brightness in Brightness.values) {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await tester.pumpWidget(RepaintBoundary(
            key: _captureKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: Platform.environment['STYLE_CAPTURE'] == 'before'
                  ? ThemeData(
                      brightness: brightness,
                      fontFamily: 'Roboto',
                      fontFamilyFallback: const ['Microsoft YaHei'])
                  : demoTheme(brightness),
              home: _page(name),
            )));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull, reason: '$name/$brightness 无溢出');
        if (name == 'home') {
          expect(find.text('luckdraw 示例'), findsOneWidget);
        } else {
          expect(find.byKey(startKey), findsOneWidget);
          expect(find.byKey(serverKey), findsOneWidget);
          expect(find.byKey(resultKey), findsOneWidget);
          expect(find.text('开始'), findsWidgets);
          expect(find.text('服务端返回'), findsOneWidget);
          if (name == 'compat') {
            expect(find.textContaining('兼容：'), findsNothing);
          }
        }
        await _capture(tester, '$name-${brightness.name}');
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      }
    });
  }
  testWidgets('example pages > result sheet and reset preserve wheel controls',
      (tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = _phone * 3;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: demoTheme(Brightness.light),
            home: const WheelPage())));
    await tester.tap(find.byKey(startKey));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(serverKey));
    for (var frame = 0; frame < 80; frame++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(find.text('奖品：1'), findsOneWidget);
    await tester.ensureVisible(find.byKey(resultKey));
    await tester.tap(find.byKey(resultKey));
    await tester.pumpAndSettle();
    expect(find.text('好运已揭晓'), findsOneWidget);
    await _capture(tester, 'result-sheet-light');
    await tester.tap(find.text('收下好运'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('重置'));
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(resultKey)).data, isEmpty);
    expect(find.text('阶段：idle'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    expect(tester.binding.transientCallbackCount, 0);
  });
}
