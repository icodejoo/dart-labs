// Smoke test for the countman example app.
//
// countman 示例应用的冒烟测试。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:example/main.dart';

void main() {
  testWidgets('CountmanDemoApp builds without error', (WidgetTester tester) async {
    // Build the demo app and pump a frame — verifies the widget tree
    // constructs cleanly (no throws) with the current countman API.
    //
    // 构建示例应用并 pump 一帧——验证 widget 树能以当前 countman API 干净构建
    // （不抛异常）。
    await tester.pumpWidget(const CountmanDemoApp());
    await tester.pump();

    expect(find.byType(CountmanDemoApp), findsOneWidget);
  });
}
