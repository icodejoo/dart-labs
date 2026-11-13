import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/model/orient_mode.dart';
import 'package:mova/src/platform_impl/orient_impl.dart'
    show preferredOrientsFor, resolveOrients;

void main() {
  group('preferredOrientsFor', () {
    test('landscape video ⇒ landscape orientations', () {
      final o = preferredOrientsFor(1920, 1080);
      expect(o, contains(DeviceOrientation.landscapeLeft));
      expect(o, isNot(contains(DeviceOrientation.portraitUp)));
    });

    test('portrait video ⇒ portrait orientations', () {
      final o = preferredOrientsFor(1080, 1920);
      expect(o, contains(DeviceOrientation.portraitUp));
      expect(o, isNot(contains(DeviceOrientation.landscapeLeft)));
    });

    test('square video ⇒ landscape (width ≥ height)', () {
      expect(preferredOrientsFor(500, 500), contains(DeviceOrientation.landscapeLeft));
    });
  });

  group('resolveOrients', () {
    test('forced landscape wins over a portrait video', () {
      final o = resolveOrients(
        MovaOrientMode.landscape,
        fullscreen: true,
        width: 1080,
        height: 1920,
      );
      expect(o, contains(DeviceOrientation.landscapeLeft));
      expect(o, isNot(contains(DeviceOrientation.portraitUp)));
    });

    test('forced portrait wins over a landscape video', () {
      final o = resolveOrients(
        MovaOrientMode.portrait,
        fullscreen: true,
        width: 1920,
        height: 1080,
      );
      expect(o, contains(DeviceOrientation.portraitUp));
      expect(o, isNot(contains(DeviceOrientation.landscapeLeft)));
    });

    test('auto + fullscreen derives from aspect ratio', () {
      final o = resolveOrients(
        MovaOrientMode.auto,
        fullscreen: true,
        width: 1920,
        height: 1080,
      );
      expect(o, contains(DeviceOrientation.landscapeLeft));
    });

    test('auto + not fullscreen allows all orientations', () {
      final o = resolveOrients(
        MovaOrientMode.auto,
        fullscreen: false,
        width: 1920,
        height: 1080,
      );
      expect(o, DeviceOrientation.values);
    });
  });
}
