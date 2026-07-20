import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:example/main.dart';

void main() {
  testWidgets('demo app 加载 mock 数据后渲染出至少一张路子图卡片', (tester) async {
    await tester.pumpWidget(const RoadmapDemoApp());
    await tester.pump(); // 触发 rootBundle.loadString 的 Future。
    await tester.pump(); // 等 setState 生效后再渲染一帧。

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(Card), findsWidgets);
  });
}
