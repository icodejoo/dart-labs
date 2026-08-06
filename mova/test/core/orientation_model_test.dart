import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/model/orientation.dart';

void main() {
  group('MovaOrient.toggled', () {
    test('landscape toggles to portrait', () {
      expect(MovaOrient.landscape.toggled, MovaOrient.portrait);
    });

    test('portrait toggles to landscape', () {
      expect(MovaOrient.portrait.toggled, MovaOrient.landscape);
    });

    test('auto toggles to landscape (treated as "not yet landscape")', () {
      expect(MovaOrient.auto.toggled, MovaOrient.landscape);
    });
  });
}
