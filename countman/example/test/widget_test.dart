// Smoke tests for the countman example app.
//
// Verifies the home hub and every demo page builds and runs a few frames
// without throwing — the real meaning of "every API has a working demo".
//
// countman 示例应用的冒烟测试。
//
// 验证首页与每个 demo 页都能构建并运行数帧而不抛异常——即"每个 API 都有可运行
// demo"的真正含义。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:countman/countman.dart';

import 'package:example/main.dart';
import 'package:example/counter_page.dart';
import 'package:example/countdown_page.dart';
import 'package:example/elapsed_page.dart';
import 'package:example/provider_page.dart';
import 'package:example/card_demo_page.dart';
import 'package:example/countdown_demo_page.dart';
import 'package:example/digit_test_page.dart';

/// Pumps [page] under a MaterialApp, runs a few frames, asserts no exception,
/// then disposes it (cancelling timers/handles) and resets the shared ticker.
///
/// 在 MaterialApp 下 pump [page]，运行数帧，断言无异常，随后销毁它（取消定时器/
/// 句柄）并重置共享 ticker。
Future<void> _smoke(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(MaterialApp(home: page));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
  expect(tester.takeException(), isNull);
  // Dispose the page so its State.dispose cancels timers/handles.
  await tester.pumpWidget(const SizedBox());
  Countman.destroy();
}

void main() {
  testWidgets('home hub builds', (tester) async {
    await tester.pumpWidget(const CountmanDemoApp());
    await tester.pump();
    expect(find.byType(CountmanDemoApp), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    Countman.destroy();
  });

  testWidgets('CounterPage builds & runs', (t) => _smoke(t, const CounterPage()));
  testWidgets('CountdownPage builds & runs', (t) => _smoke(t, const CountdownPage()));
  testWidgets('ElapsedPage builds & runs', (t) => _smoke(t, const ElapsedPage()));
  testWidgets('ProviderPage builds & runs', (t) => _smoke(t, const ProviderPage()));
  testWidgets('CardDemoPage builds & runs', (t) => _smoke(t, const CardDemoPage()));
  testWidgets('CountdownDemoPage builds & runs', (t) => _smoke(t, const CountdownDemoPage()));
  testWidgets('DigitTestPage builds & runs', (t) => _smoke(t, const DigitTestPage()));
}
