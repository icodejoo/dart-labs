import 'dart:io';

import 'package:curved_dual_tab_bar/curved_dual_tab_bar.dart';
import 'package:curved_dual_tab_bar_example/demo_kit/demo_kit.dart';
import 'package:curved_dual_tab_bar_example/main.dart' as demo;
import 'package:curved_dual_tab_bar_example/tab_demos.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 英文重放提示。
const _replay = 'Replay';

/// 中文重放提示。
const _replayZh = '重放';

/// 中文语言代码。
const _chinese = 'zh';

/// 直接 appBar 卡片的标识。
const _appBarId = 'appbar';

/// 样式页的稳定卡片标识。
const _styleIds = ['theme', 'deposit', 'gradient', 'curve', 'outlines', 'glow'];

/// 控制器页的稳定卡片标识。
const _controllerIds = ['shared', 'native', _appBarId];

/// 默认语言，避免依赖测试机器的区域设置。
const _english = 'en';

/// 两侧常用的英文标签。
const _monthly = 'Monthly';

/// 第二侧常用的英文标签。
const _yearly = 'Yearly';

/// 测试页面入口。
const _styles = 'styles';

/// 控制器页面入口。
const _controllers = 'controllers';

/// 创建真实应用并固定视口、语言与初始 hash。
Future<DemoLocale> _mount(
  WidgetTester tester, {
  String page = _styles,
  String language = _english,
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  final locale = DemoLocale(
    uri: Uri.parse('https://demo.test/?lang=$language'),
  );
  await tester.pumpWidget(
    demo.CurvedDualTabBarExampleApp(
      locale: locale,
      initialFragment: '/pages/$page',
    ),
  );
  await tester.pumpAndSettle();
  return locale;
}

/// 查找指定卡片内部的标签，避免命中其他卡片或滑动内容。
Finder _tab(Finder card, String label) =>
    find.descendant(of: card, matching: find.widgetWithText(Tab, label));

/// 获取卡片内部原生 TabBar 使用的控制器。
TabController _controller(WidgetTester tester, Finder card) {
  final bar = tester.widget<TabBar>(
    find.descendant(of: card, matching: find.byType(TabBar)),
  );
  return bar.controller ??
      DefaultTabController.of(tester.element(_tab(card, _monthly)));
}

/// 验证当前版本、响应式布局、控制器联动与重放。
void main() {
  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher
        .clearPlatformBrightnessTestValue();
  });

  test('version and source links match the current package', () {
    final pubspec = File('../pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);
    expect(demo.demoVersion, version);
    expect(demo.demoPubUrl, 'https://pub.dev/packages/${demo.demoProject}');
    expect(demo.demoGithubUrl, contains('/tree/main/${demo.demoProject}'));
    expect(
      demo.demoReadmeUrl,
      contains('/blob/main/${demo.demoProject}/README.md'),
    );
  });

  testWidgets(
    'entry point opens the current version with six replayable styles',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      demo.main();
      await tester.pumpAndSettle();
      expect(find.text(demo.demoVersion), findsOneWidget);
      expect(find.byType(StyledTabs), findsNWidgets(_styleIds.length));
      expect(
        find.byIcon(Icons.replay_rounded),
        findsNWidgets(_styleIds.length),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final page in [_styles, _controllers]) {
    for (final language in [_english, _chinese]) {
      testWidgets(
        '$page: $language layouts remain inside 360–1600 widths in both themes',
        (tester) async {
          addTearDown(tester.view.reset);
          final locale = await _mount(tester, page: page, language: language);
          for (final brightness in Brightness.values) {
            tester.binding.platformDispatcher.platformBrightnessTestValue =
                brightness;
            for (final width in <double>[
              360,
              375,
              600,
              899,
              900,
              1000,
              1440,
              1600,
            ]) {
              tester.view.physicalSize = Size(width, width == 375 ? 667 : 900);
              await tester.pumpAndSettle();
              expect(
                tester.takeException(),
                isNull,
                reason: '$page $language $brightness $width',
              );
              final cards = find.byType(DemoCard);
              for (final element in cards.evaluate()) {
                final rect = tester.getRect(find.byWidget(element.widget));
                expect(rect.left, greaterThanOrEqualTo(0));
                expect(rect.right, lessThanOrEqualTo(width));
              }
              final body =
                  width -
                  (width >= DemoTokens.sidebarBreakpoint ? 224 : 0) -
                  DemoTokens.padding * 2;
              final columns = DemoGrid.columnsFor(
                body.clamp(0, DemoTokens.maxWidth - DemoTokens.padding * 2),
              );
              final first = tester.getTopLeft(cards.at(0));
              final second = tester.getTopLeft(cards.at(1));
              if (columns == 1) {
                expect(second.dy, greaterThan(first.dy));
              } else {
                expect(second.dy, first.dy);
                expect(second.dx, greaterThan(first.dx));
                expect(
                  tester.getSize(cards.at(0)).height,
                  tester.getSize(cards.at(1)).height,
                );
              }
              if (width == 375) {
                expect(second.dy + DemoTokens.cardHeaderHeight, lessThan(667));
                expect(
                  first.dy + tester.getSize(cards.at(0)).height,
                  lessThan(667),
                );
              }
            }
          }
          expect(
            find.byTooltip(language == _english ? _replay : _replayZh),
            findsNWidgets(
              page == _styles ? _styleIds.length : _controllerIds.length,
            ),
          );
          await tester.pumpWidget(const SizedBox());
          locale.dispose();
        },
      );
    }
  }

  testWidgets('each style replays its animation and leaves other cards alone', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final locale = await _mount(tester);
    for (final id in _styleIds) {
      final card = find.byKey(ValueKey(id));
      final styled = tester.widget<StyledTabs>(
        find.descendant(of: card, matching: find.byType(StyledTabs)),
      );
      final label = styled.style == TabStyle.theme
          ? _monthly
          : styled.style == TabStyle.deposit ||
                styled.style == TabStyle.gradient
          ? 'Deposit'
          : 'Left';
      await tester.ensureVisible(card);
      await tester.tap(_tab(card, label));
      await tester.pumpAndSettle();
      final oldController = _controllerForExplicitBar(tester, card);
      expect(oldController.index, 0);
      final others = find
          .byType(StyledTabs)
          .evaluate()
          .where((e) => !identical(e.widget, styled))
          .map((e) => e)
          .toList();
      final replay = find.descendant(
        of: card,
        matching: find.byTooltip(_replay),
      );
      expect(tester.getSize(replay).shortestSide, greaterThanOrEqualTo(40));
      await tester.tap(replay);
      await tester.pump();
      await tester.pump();
      final controller = _controllerForExplicitBar(tester, card);
      expect(identical(controller, oldController), isFalse);
      await tester.pump(const Duration(milliseconds: 150));
      expect(controller.animation!.value, inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(controller.index, 1);
      for (final element in others) {
        expect(element.mounted, isTrue);
      }
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    locale.dispose();
  });

  testWidgets('all controller cards support taps, swipes and a fresh replay', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final locale = await _mount(tester, page: _controllers);
    for (final id in _controllerIds) {
      final card = find.byKey(ValueKey(id));
      await tester.ensureVisible(card);
      final controller = _controller(tester, card);
      expect(controller.index, 1);
      await tester.tap(_tab(card, _monthly));
      await tester.pumpAndSettle();
      expect(controller.index, 0);
      final view = find.descendant(of: card, matching: find.byType(TabBarView));
      await tester.drag(view, const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(controller.index, 1);
      await tester.drag(view, const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(controller.index, 0);
      locale.select(_chinese);
      await tester.pumpAndSettle();
      expect(controller.index, 0);
      locale.select(_english);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: card, matching: find.byTooltip(_replay)),
      );
      await tester.pump();
      final fresh = _controller(tester, card);
      expect(identical(fresh, controller), isFalse);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(fresh.animation!.value, inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(fresh.index, 1);
      await tester.tap(_tab(card, _yearly));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    final appBar = tester.widget<CurvedDualTabBar>(
      find.descendant(
        of: find.byKey(const ValueKey(_appBarId)),
        matching: find.byType(CurvedDualTabBar),
      ),
    );
    expect(appBar.safeArea, isTrue);
    expect(appBar.preferredSize.height, appBar.height);
    await tester.pumpWidget(const SizedBox());
    locale.dispose();
  });

  testWidgets(
    'navigation, language, theme and header links work with a long project name',
    (tester) async {
      addTearDown(tester.view.reset);
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
      final locale = await _mount(tester, size: const Size(375, 667));
      await tester.tap(find.byTooltip('Open navigation'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Controllers & swipes'));
      await tester.pumpAndSettle();
      expect(find.byType(NativeTabs), findsOneWidget);
      await tester.tap(find.text('中文'));
      await tester.pumpAndSettle();
      expect(find.byTooltip(_replayZh), findsNWidgets(_controllerIds.length));
      await tester.tap(find.byTooltip('切换亮暗'));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(NativeTabs))).brightness,
        Brightness.dark,
      );
      for (final tooltip in ['pub.dev', 'GitHub', '阅读文档']) {
        await tester.tap(find.byTooltip(tooltip));
        await tester.pump();
      }
      expect(copied, [demo.demoPubUrl, demo.demoGithubUrl, demo.demoReadmeUrl]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      locale.dispose();
    },
  );

  testWidgets('reduced motion does not start an automatic transition', (
    tester,
  ) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );
    addTearDown(tester.view.reset);
    final locale = await _mount(tester, page: _controllers);
    for (final id in _controllerIds) {
      expect(_controller(tester, find.byKey(ValueKey(id))).index, 0);
    }
    await tester.pumpWidget(const SizedBox());
    locale.dispose();
  });
}

/// 获取受控外观卡片内部由组件创建的控制器。
TabController _controllerForExplicitBar(WidgetTester tester, Finder card) =>
    tester
        .widget<TabBar>(
          find.descendant(of: card, matching: find.byType(TabBar)),
        )
        .controller!;
