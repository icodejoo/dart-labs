import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/svgx.dart';
import 'package:svgx/src/rust_static_svg.dart';

const png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
const source =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><rect width="24" height="24" fill="red"/><image width="12" height="12" href="data:image/png;base64,$png"/><image x="12" width="12" height="12" href="data:image/png;base64,$png"/></svg>';
Future<ui.Image> image() async {
  final r = ui.PictureRecorder();
  Canvas(r);
  final p = r.endRecording();
  try {
    return await p.toImage(1, 1);
  } finally {
    p.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var available = true;
  setUpAll(() async {
    try {
      await RustLib.init();
    } catch (error) {
      available = false;
      // ignore: avoid_print
      print(
        'Skipping: native library not loadable in this test environment ($error)',
      );
    }
  });
  tearDown(() {
    RustSvgxPictureCache.instance
      ..debugDecodeImage = null
      ..maximumSize = 1000
      ..clear();
    RustSvgxPictureCache.debugWrapRecordingCanvas = null;
    ui.Image.onDispose = null;
    ui.Picture.onCreate = null;
  });
  for (final reattachEarly in [false, true]) {
    testWidgets(
      'static raster survives listener removal (reattach early: $reattachEarly)',
      (tester) async {
        if (!available) {
          markTestSkipped(
            'Native library not loadable in this test environment',
          );
          return;
        }
        const provider = StringSvgx(
          '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><rect width="24" height="24"/></svg>',
        );
        RustSvgxPictureCache.instance.getOrRender(provider.source);
        final completer = provider.loadImage(
          provider,
          (buffer, {getTargetSize}) => throw UnimplementedError(),
        );
        final handle = completer.keepAlive();
        var delivered = 0;
        final listener = ImageStreamListener((info, _) {
          delivered++;
          info.dispose();
        });
        completer.addListener(listener);
        var removed = false;
        ui.Picture.onCreate = (_) {
          ui.Picture.onCreate = null;
          removed = true;
          completer.removeListener(listener);
          if (reattachEarly) completer.addListener(listener);
        };
        try {
          await tester.runAsync(() async {
            await tester.pump();
            await Future<void>.delayed(const Duration(milliseconds: 150));
          });
          await tester.pump();
          expect(removed, isTrue);
          if (!reattachEarly) {
            expect(delivered, 0);
            completer.addListener(listener);
          }
          expect(delivered, 1);
        } finally {
          completer.removeListener(listener);
          handle.dispose();
        }
      },
    );
  }
  test(
    'async cache errors stay on the returned future and allow retry',
    () async {
      if (!available) {
        markTestSkipped('Native library not loadable in this test environment');
        return;
      }
      for (var i = 0; i < 2; i++) {
        await expectLater(
          RustSvgxPictureCache.instance.getOrRenderAsync('<invalid'),
          throwsA(anything),
        );
      }
    },
  );
  test('picture cache converges when its limit shrinks without disposing retained pictures', () {
    if (!available) {
      markTestSkipped('Native library not loadable in this test environment');
      return;
    }
    final c = RustSvgxPictureCache.instance;
    final first = c.getOrRender(
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"/>',
    );
    for (var i = 0; i < 8; i++) {
      c.getOrRender(
        '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><!--$i--></svg>',
      );
    }
    c.maximumSize = 1;
    c.getOrRender(
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><!--new--></svg>',
    );
    expect(c.length, 1);
    final r = ui.PictureRecorder();
    Canvas(r).drawPicture(first.picture);
    r.endRecording().dispose();
  });
  test(
    'a single bad bitmap is skipped and successful decodes are disposed',
    () async {
      if (!available) {
        markTestSkipped('Native library not loadable in this test environment');
        return;
      }
      final good = await image();
      final disposed = <ui.Image>[];
      ui.Image.onDispose = disposed.add;
      var calls = 0;
      RustSvgxPictureCache.instance.debugDecodeImage = (_) async {
        if (calls++ == 0) return good;
        throw StateError('bad bitmap');
      };
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      final RustSvgPictureInfo info;
      try {
        info = await RustSvgxPictureCache.instance.getOrRenderAsync(source);
      } finally {
        FlutterError.onError = previous;
      }
      expect(errors, hasLength(1));
      expect(errors.single.exception, isA<StateError>());
      expect(errors.single.library, 'svgx');
      expect(errors.single.context.toString(), contains('decoding'));
      expect(calls, 2);
      expect(info.size, const Size(24, 24));
      final raster = await rasterizeSvgPicture(info, width: 24, height: 24);
      try {
        final pixels = await raster.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        final offset = (23 * 24 + 23) * 4;
        expect(pixels!.buffer.asUint8List(offset, 4), [255, 0, 0, 255]);
      } finally {
        raster.dispose();
      }
      expect(disposed, contains(good));
    },
  );
  test('recording failure releases decoded images', () async {
    if (!available) {
      markTestSkipped('Native library not loadable in this test environment');
      return;
    }
    final decoded = <ui.Image>[];
    final disposed = <ui.Image>[];
    ui.Image.onDispose = disposed.add;
    RustSvgxPictureCache.instance.debugDecodeImage = (_) async {
      final value = await image();
      decoded.add(value);
      return value;
    };
    RustSvgxPictureCache.debugWrapRecordingCanvas = (_) =>
        throw StateError('record failed');
    await expectLater(
      RustSvgxPictureCache.instance.getOrRenderAsync(source),
      throwsStateError,
    );
    expect(decoded, hasLength(2));
    expect(disposed, containsAll(decoded));
  });
}
