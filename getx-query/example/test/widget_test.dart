import 'package:flutter_test/flutter_test.dart';
import 'package:getx_query_example/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const GetxQueryDemoApp());
    await tester.pump();
    expect(find.text('useQuery'), findsWidgets);
  });
}
