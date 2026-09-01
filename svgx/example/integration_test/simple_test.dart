import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/svgx.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await Svgx.ensureInitialized());
  test('Native backend initializes without throwing', () async {
    await Svgx.ensureInitialized();
  });
}
