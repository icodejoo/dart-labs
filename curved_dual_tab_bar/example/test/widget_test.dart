import 'package:curved_dual_tab_bar_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('demo page renders the DEPOSIT/WITHDRAW header', (tester) async {
    await tester.pumpWidget(const CurvedDualTabBarExampleApp());

    expect(find.text('DEPOSIT'), findsOneWidget);
    expect(find.text('WITHDRAW'), findsOneWidget);
  });
}
