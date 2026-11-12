// Widget tests for the layerman example app.
// Full integration tests live in integration_test/orchestration_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:layerman_example/main.dart' as app;

void main() {
  testWidgets('App smoke test — AppRoot renders without crashing', (tester) async {
    app.main();
    await tester.pump();
    expect(find.byType(app.AppRoot), findsOneWidget);
  });
}
