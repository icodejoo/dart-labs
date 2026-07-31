import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/model/orientation.dart';
import 'package:videoman/src/platform_impl/orientation_impl.dart'
    show preferredOrientationsFor, resolveOrientations;

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

  group('resolveOrientations', () {
    test('forced landscape wins over a portrait video', () {
      final o = resolveOrientations(
        VmOrientation.landscape,
        fullscreen: true,
        width: 1080,
        height: 1920,
      );
      expect(o, contains(DeviceOrientation.landscapeLeft));
      expect(o, isNot(contains(DeviceOrientation.portraitUp)));
    });

    test('forced portrait wins over a landscape video', () {
      final o = resolveOrientations(
        VmOrientation.portrait,
        fullscreen: true,
        width: 1920,
        height: 1080,
      );
      expect(o, contains(DeviceOrientation.portraitUp));
      expect(o, isNot(contains(DeviceOrientation.landscapeLeft)));
    });

    test('auto + fullscreen derives from aspect ratio', () {
      final o = resolveOrientations(
        VmOrientation.auto,
        fullscreen: true,
        width: 1920,
        height: 1080,
      );
      expect(o, contains(DeviceOrientation.landscapeLeft));
    });

    test('auto + not fullscreen allows all orientations', () {
      final o = resolveOrientations(
        VmOrientation.auto,
        fullscreen: false,
        width: 1920,
        height: 1080,
      );
      expect(o, DeviceOrientation.values);
    });
  });
}
