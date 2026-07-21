import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:example/main.dart';

void main() {
  testWidgets('demo app renders at least one road chart card after loading mock data', (tester) async {
    await tester.pumpWidget(const RoadmapDemoApp());
    await tester.pump(); // triggers the rootBundle.loadString Future.
    await tester.pump(); // renders one more frame after setState takes effect.

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(Card), findsWidgets);
  });
}
