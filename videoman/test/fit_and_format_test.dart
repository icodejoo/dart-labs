import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/controls/player.dart' show preferredOrientationsFor;

void main() {
  group('preferredOrientationsFor', () {
    test('landscape video ⇒ landscape orientations', () {
      final o = preferredOrientationsFor(1920, 1080);
      expect(o, contains(DeviceOrientation.landscapeLeft));
      expect(o, isNot(contains(DeviceOrientation.portraitUp)));
    });

    test('portrait video ⇒ portrait orientations', () {
      final o = preferredOrientationsFor(1080, 1920);
      expect(o, contains(DeviceOrientation.portraitUp));
      expect(o, isNot(contains(DeviceOrientation.landscapeLeft)));
    });

    test('square video ⇒ landscape (width ≥ height)', () {
      expect(preferredOrientationsFor(500, 500), contains(DeviceOrientation.landscapeLeft));
    });
  });
}
