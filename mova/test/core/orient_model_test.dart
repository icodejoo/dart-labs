import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/model/orient_mode.dart';

void main() {
  group('MovaOrientMode.toggled', () {
    test('landscape toggles to portrait', () {
      expect(MovaOrientMode.landscape.toggled, MovaOrientMode.portrait);
    });

    test('portrait toggles to landscape', () {
      expect(MovaOrientMode.portrait.toggled, MovaOrientMode.landscape);
    });

    test('auto toggles to landscape (treated as "not yet landscape")', () {
      expect(MovaOrientMode.auto.toggled, MovaOrientMode.landscape);
    });
  });
}
