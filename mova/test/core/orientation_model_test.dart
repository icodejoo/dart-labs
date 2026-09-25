import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/model/orientation.dart';

void main() {
  group('MovaOrientation.toggled', () {
    test('landscape toggles to portrait', () {
      expect(MovaOrientation.landscape.toggled, MovaOrientation.portrait);
    });

    test('portrait toggles to landscape', () {
      expect(MovaOrientation.portrait.toggled, MovaOrientation.landscape);
    });

    test('auto toggles to landscape (treated as "not yet landscape")', () {
      expect(MovaOrientation.auto.toggled, MovaOrientation.landscape);
    });
  });
}
