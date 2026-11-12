import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerman/layerman.dart';
import 'package:layerman_example/demo_kit/demo_kit.dart';
import 'package:layerman_example/demo_text.dart';

/// 验证运行时状态文案也随语言切换，覆盖全部结束原因。
void main() {
  testWidgets('runtime events and outcomes are translated', (tester) async {
    final locale = DemoLocale(uri: Uri.parse('https://example.test/?lang=en'));
    await tester.pumpWidget(
      DemoApp(
        title: 'labels',
        seedColor: Colors.blue,
        locale: locale,
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                for (final reason in OverlayEndReason.values)
                  Text(demoEndReason(context, reason)),
                for (final type in OverlayEventType.values)
                  Text(
                    demoEventLabel(
                      context,
                      OverlayEvent(type: type, id: 'A', slot: ''),
                    ),
                  ),
                Text(
                  demoEventLabel(
                    context,
                    const OverlayEvent(
                      type: OverlayEventType.ended,
                      id: 'A',
                      slot: '',
                      reason: OverlayEndReason.closed,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('closed'), findsOneWidget);
    locale.select('zh');
    await tester.pump();
    for (final reason in OverlayEndReason.values) {
      expect(find.text(reason.name), findsNothing);
    }
    expect(find.text('主动关闭'), findsOneWidget);
    expect(find.text('A: 已入队'), findsOneWidget);
    expect(find.text('A: 已展示'), findsOneWidget);
    expect(find.text('A: 已结束'), findsOneWidget);
    expect(find.text('A: 主动关闭'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    locale.dispose();
  });
}
