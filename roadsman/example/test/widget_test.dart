import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:example/main.dart';

void main() {
  testWidgets('demo app 加载 mock 数据后渲染出至少一张路子图卡片', (tester) async {
    await tester.pumpWidget(const RoadmapDemoApp());
    await tester.pump(); // triggers the rootBundle.loadString Future.
    await tester.pump(); // renders one more frame after setState takes effect.

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(Card), findsWidgets);
  });
}
