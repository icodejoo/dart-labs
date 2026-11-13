import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/animated_svg_painter.dart';
import 'package:xvg/src/animation/svg_document_parser.dart';
import 'package:xvg/xvg.dart';

import 'pixel_test_utils.dart';

/// Canvas side in logical pixels. / 画布的逻辑像素边长。
const _side = 200;
const _size = Size.square(_side * 1.0);
const _wide = 'width="$_side" height="${_side ~/ 2}" viewBox="0 0 100 100"';
const _offset = 'width="$_side" height="$_side" viewBox="50 50 100 100"';
const _shapes =
    '<rect x="0" y="0" width="100" height="100" fill="#123456"/>'
    '<rect x="10" y="20" width="25" height="60" fill="#e03010"/>'
    '<rect x="60" y="15" width="30" height="20" fill="#10b060"/>';
const _tolerance = 2;

/// Builds a source shared by both independent render paths.
/// 构造两条独立路径使用的同一份源。
String _source(String attributes, [String body = _shapes]) =>
    '<svg xmlns="http://www.w3.org/2000/svg" $attributes>$body</svg>';

/// Captures the actual widget at logical pixel resolution, without scene snap.
/// 按逻辑像素读取真实 widget，禁用场景对齐以便独立截图。
Future<ByteData> _capture(WidgetTester tester, Widget child) async {
  final key = GlobalKey();
  final scene = Center(
    child: RepaintBoundary(key: key, child: child),
  );
  await tester.pumpWidget(scene);
  await tester.pumpAndSettle();
  return captureBoundaryPixels(tester, key);
}

/// Compares every RGBA channel, including transparent and clipped regions.
/// 比较每个 RGBA 通道，包含透明区和被裁剪区域。
void _expectPixels(
  ByteData actual,
  ByteData reference, {
  int tolerance = _tolerance,
}) {
  expect(actual.lengthInBytes, reference.lengthInBytes);
  var maxDelta = 0;
  var maxIndex = 0;
  var visible = 0;
  for (var i = 0; i < actual.lengthInBytes; i++) {
    final delta = (actual.getUint8(i) - reference.getUint8(i)).abs();
    if (delta > maxDelta) {
      maxDelta = delta;
      maxIndex = i;
    }
    if (i % 4 == 3 && reference.getUint8(i) > 0) visible++;
  }
  expect(
    visible,
    greaterThan(0),
    reason: 'reference must contain visible content',
  );
  expect(
    maxDelta,
    lessThanOrEqualTo(tolerance),
    reason:
        'maximum RGBA difference at byte $maxIndex: '
        '${actual.getUint8(maxIndex)} vs ${reference.getUint8(maxIndex)}',
  );
}

/// Covers Rust/Dart parity plus effects and provider entry points.
/// 覆盖 Rust/Dart 对拍、效果及 provider 入口。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(RustLib.init);
  tearDown(() {
    XvgDocumentCache.instance.clear();
    RustXvgPictureCache.instance.clear();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  });

  for (final (name, attributes, body, size, fit, alignment) in [
    (
      'scale',
      'width="$_side" height="$_side" viewBox="0 0 100 100"',
      _shapes,
      _size,
      BoxFit.contain,
      Alignment.center,
    ),
    (
      'origin',
      _offset,
      '<g transform="translate(50 50)">$_shapes</g>',
      _size,
      BoxFit.contain,
      Alignment.center,
    ),
    ('default meet', _wide, _shapes, _size, BoxFit.contain, Alignment.center),
    (
      'center meet',
      '$_wide preserveAspectRatio="xMidYMid meet"',
      _shapes,
      _size,
      BoxFit.contain,
      Alignment.center,
    ),
    (
      'min meet',
      '$_wide preserveAspectRatio="xMinYMin meet"',
      _shapes,
      _size,
      BoxFit.contain,
      Alignment.center,
    ),
    (
      'max slice',
      '$_wide preserveAspectRatio="xMaxYMax slice"',
      _shapes,
      const Size(_side * 1.0, _side / 2),
      BoxFit.contain,
      Alignment.center,
    ),
    (
      'none',
      '$_wide preserveAspectRatio="none"',
      _shapes,
      _size,
      BoxFit.contain,
      Alignment.center,
    ),
    (
      'no viewBox',
      'width="100" height="100"',
      _shapes,
      _size,
      BoxFit.contain,
      Alignment.center,
    ),
    // The 24x24 geometry also gives usvg the same missing-size fallback bounds.
    // 24x24 几何同时为 usvg 提供与 Dart 缺省尺寸一致的边界。
    (
      'no dimensions',
      '',
      '<rect width="24" height="24" fill="#e03010"/>',
      _size,
      BoxFit.contain,
      Alignment.center,
    ),
    (
      'widget fit/alignment',
      '$_wide preserveAspectRatio="xMinYMin meet"',
      _shapes,
      const Size(_side * 1.5, _side * 1.0),
      BoxFit.contain,
      Alignment.bottomRight,
    ),
    (
      'widget fill',
      '$_wide preserveAspectRatio="none"',
      _shapes,
      _size,
      BoxFit.fill,
      Alignment.topLeft,
    ),
    (
      'px',
      'width="${_side}px" height="${_side ~/ 2}px" viewBox="0 0 100 100"',
      _shapes,
      _size,
      BoxFit.contain,
      Alignment.center,
    ),
    (
      'userSpace clip/mask',
      _offset,
      '<defs><clipPath id="c" clipPathUnits="userSpaceOnUse">'
          '<rect x="60" y="60" width="70" height="70"/></clipPath>'
          '<mask id="m" maskUnits="userSpaceOnUse" x="50" y="50" '
          'width="100" height="100" maskContentUnits="userSpaceOnUse">'
          '<rect x="70" y="70" width="60" height="60" fill="#fff"/></mask></defs>'
          '<rect x="50" y="50" width="100" height="100" fill="#e03010" '
          'clip-path="url(#c)" mask="url(#m)"/>',
      _size,
      BoxFit.contain,
      Alignment.center,
    ),
  ]) {
    testWidgets('StaticXvg and AnimatedXvg pixels: $name', (tester) async {
      final svg = _source(attributes, body);
      final reference = await _capture(
        tester,
        StaticXvg(
          svg,
          width: size.width,
          height: size.height,
          fit: fit,
          alignment: alignment,
          pixelSnap: XvgPixelSnap.never,
        ),
      );
      final actual = await _capture(
        tester,
        AnimatedXvg.string(
          svg,
          width: size.width,
          height: size.height,
          fit: fit,
          alignment: alignment,
          autoplay: false,
          pixelSnap: XvgPixelSnap.never,
        ),
      );
      _expectPixels(actual, reference);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Dart slice clips to viewport before outer letterboxing', (
    tester,
  ) async {
    final pixels = await _capture(
      tester,
      AnimatedXvg.string(
        _source('$_wide preserveAspectRatio="xMaxYMax slice"'),
        width: _size.width,
        height: _size.height,
        autoplay: false,
        pixelSnap: XvgPixelSnap.never,
      ),
    );
    var mismatches = 0;
    String? firstMismatch;
    for (var y = 0; y < _side; y++) {
      for (var x = 0; x < _side; x++) {
        final alpha = pixels.getUint8((y * _side + x) * 4 + 3);
        final expectedAlpha = y < _side ~/ 4 || y >= _side * 3 ~/ 4 ? 0 : 255;
        if (alpha != expectedAlpha) {
          mismatches++;
          firstMismatch ??= '($x, $y): alpha $alpha, expected $expectedAlpha';
        }
      }
    }
    expect(mismatches, 0, reason: 'first mismatching pixel: $firstMismatch');
  });

  testWidgets(
    'root background fills widget box including viewBox letterboxing',
    (tester) async {
      final pixels = await _capture(
        tester,
        AnimatedXvg.string(
          _source('$_wide style="background-color:#ff0000"'),
          width: _size.width,
          height: _size.height,
          autoplay: false,
          pixelSnap: XvgPixelSnap.never,
        ),
      );
      for (final (x, y) in [
        (1, 1),
        (_side - 1, _side - 1),
        (1, _side ~/ 2),
        (_side - 1, _side ~/ 2),
      ]) {
        expect(pixels.getUint32((y * _side + x) * 4, Endian.big), 0xff0000ff);
      }
    },
  );

  testWidgets(
    'SvgImageProvider text dispatch carries the nonzero root mapping',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      final svg = _source(
        _offset,
        '<rect x="50" y="50" width="100" height="100" fill="#e03010"/>'
        '<text x="60" y="90" font-size="20" fill="#000">I</text>',
      );
      final expected = await _capture(
        tester,
        AnimatedXvg.string(
          svg,
          width: _size.width * 2,
          height: _size.height * 2,
          autoplay: false,
          pixelSnap: XvgPixelSnap.never,
        ),
      );
      await tester.runAsync(() async {
        final completer = Completer<ImageInfo>();
        final stream = StringXvg(
          svg,
          width: _size.width,
          height: _size.height,
        ).resolve(const ImageConfiguration(devicePixelRatio: 1));
        final listener = ImageStreamListener(
          (info, _) => completer.complete(info),
          onError: (Object error, StackTrace? stack) =>
              completer.completeError(error, stack),
        );
        stream.addListener(listener);
        try {
          final info = await completer.future.timeout(
            const Duration(seconds: 5),
          );
          try {
            expect(
              (info.image.width, info.image.height, info.scale),
              (_side * 2, _side * 2, 2),
            );
            final bytes = (await info.image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            _expectPixels(bytes, expected);
          } finally {
            info.dispose();
          }
        } finally {
          stream.removeListener(listener);
        }
      });
    },
  );

  for (final (aspectRatio, expectedSigma) in [
    ('xMidYMid meet', '3'),
    ('none', '6 3'),
  ]) {
    testWidgets('blur sigma follows root scaling: $aspectRatio', (
      tester,
    ) async {
      final mapped = _source(
        '$_wide preserveAspectRatio="$aspectRatio"',
        '<defs><filter id="b" x="-100%" y="-100%" width="300%" height="300%">'
            '<feGaussianBlur stdDeviation="3"/></filter></defs>'
            '<rect x="30" y="30" width="40" height="40" fill="#123456" filter="url(#b)"/>',
      );
      final explicit = _source(
        'width="$_side" height="${_side ~/ 2}"',
        '<defs><filter id="b" x="-100%" y="-100%" width="300%" height="300%">'
            '<feGaussianBlur stdDeviation="$expectedSigma"/></filter></defs>'
            '<rect x="${aspectRatio == 'none' ? 60 : 80}" y="30" '
            'width="${aspectRatio == 'none' ? 80 : 40}" height="40" '
            'fill="#123456" filter="url(#b)"/>',
      );
      final expected = await _capture(
        tester,
        StaticXvg(
          explicit,
          width: _size.width,
          height: _size.height / 2,
          pixelSnap: XvgPixelSnap.never,
        ),
      );
      final actual = await _capture(
        tester,
        AnimatedXvg.string(
          mapped,
          width: _size.width,
          height: _size.height / 2,
          autoplay: false,
          pixelSnap: XvgPixelSnap.never,
        ),
      );
      _expectPixels(actual, expected);
    });
  }

  testWidgets('embedded raster image inherits root origin and scale', (
    tester,
  ) async {
    final png = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(const Color(0xffe03010), BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(4, 4);
      try {
        return base64Encode(
          (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
              .asUint8List(),
        );
      } finally {
        image.dispose();
        picture.dispose();
      }
    });
    final svg = _source(
      _offset,
      '<image x="60" y="70" width="30" height="30" '
      'href="data:image/png;base64,$png"/>',
    );
    // Native image decoding needs real async time before the cache warm hit.
    // 原生图像解码先在真实异步时间完成，再走缓存热路径。
    await tester.runAsync(
      () => RustXvgPictureCache.instance.getOrRenderAsync(svg),
    );
    final reference = await _capture(
      tester,
      StaticXvg(
        svg,
        width: _size.width,
        height: _size.height,
        pixelSnap: XvgPixelSnap.never,
      ),
    );
    await tester.runAsync(() async {
      final document = parseAnimatedSvgDocument(svg);
      await resolveImageNodes(document);
      final clock = ValueNotifier(Duration.zero);
      final recorder = ui.PictureRecorder();
      AnimatedSvgPainter(
        root: document.root,
        intrinsicSize: Size(document.width, document.height),
        rootViewBoxTransform: document.rootViewBoxTransform,
        clock: clock,
        theme: const XvgTheme(),
        fit: BoxFit.contain,
        alignment: Alignment.center,
      ).paint(Canvas(recorder), _size);
      final picture = recorder.endRecording();
      final image = await picture.toImage(_side, _side);
      try {
        final actual = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        _expectPixels(actual, reference);
      } finally {
        image.dispose();
        picture.dispose();
        clock.dispose();
        document.root.children.single.resolvedImage?.dispose();
      }
    });
  });
}
