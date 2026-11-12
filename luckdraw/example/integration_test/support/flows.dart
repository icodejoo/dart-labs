import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/luckdraw.dart';
import 'package:luckdraw_example/demo_shell.dart';
import 'package:luckdraw_example/main.dart';

/// 真实帧轮询间隔。
const Duration flowStep = Duration(milliseconds: 40);

/// 单局端到端测试的最长等待。
const Duration flowTimeout = Duration(seconds: 20);

/// 启动真实菜单并导航到 [title]；例如 `await openDemo(tester, '转盘')`。
Future<void> openDemo(WidgetTester tester, String title) async {
  await tester.pumpWidget(const LuckdrawExample());
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text(title), 180);
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

/// 等待 [condition] 在真实帧中成立，否则超时失败；例如等待结算阶段。
Future<void> waitFor(WidgetTester tester, bool Function() condition) async {
  final watch = Stopwatch()..start();
  while (!condition() && watch.elapsed < flowTimeout) {
    await tester.pump(flowStep);
  }
  expect(condition(), isTrue, reason: '真实帧未在 $flowTimeout 内达到目标');
  expect(tester.takeException(), isNull);
}

/// 点击模拟服务端结果按钮；例如 `await serverResult(tester)`。
Future<void> serverResult(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(serverKey));
  await tester.tap(find.byKey(serverKey));
  await tester.pump();
}

/// 断言 [phase] 结算及屏幕 [text]，然后卸载页面验证资源释放。
/// 例如 `await finishDemo(tester, () => controller.phase.value, '奖品：1')`。
Future<void> finishDemo(
    WidgetTester tester, LuckyPhase Function() phase, String text) async {
  await waitFor(tester, () => phase() == LuckyPhase.settled);
  await tester.pump();
  expect(find.text(text), findsOneWidget);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
  expect(tester.binding.transientCallbackCount, 0);
  expect(tester.takeException(), isNull);
}
