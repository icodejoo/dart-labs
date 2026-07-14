import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_stompsocket_example/main.dart';

void main() {
  testWidgets('App smoke test', (tester) async {
    main();
    await tester.pump();
    expect(find.byType(StompsocketDemoApp), findsOneWidget);
  });
}
