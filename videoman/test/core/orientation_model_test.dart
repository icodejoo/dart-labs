import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/model/orientation.dart';

void main() {
  group('VmOrientation.toggled', () {
    test('landscape toggles to portrait', () {
      expect(VmOrientation.landscape.toggled, VmOrientation.portrait);
    });

    test('portrait toggles to landscape', () {
      expect(VmOrientation.portrait.toggled, VmOrientation.landscape);
    });

    test('auto toggles to landscape (treated as "not yet landscape")', () {
      expect(VmOrientation.auto.toggled, VmOrientation.landscape);
    });
  });
}
