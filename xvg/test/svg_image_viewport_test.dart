import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/xvg.dart';

/// Solid pixels shared by the fixtures. / 测试图形共用的不透明颜色。
const _red = Color(0xffff0000);
const _blue = Color(0xff0000ff);
const _background = Color(0xffeeeeee);

/// The canvas leaves room around the widget for overflow. / 画布在组件四周留出空间以检测溢出。
const _canvasSize = 240;
const _origin = Offset(40, 40);
const _containSize = Size(160, 80);
const _coverSize = Size.square(60);
const _captureKey = ValueKey('svg viewport scene');

/// A tall viewBox leaves horizontal space inside the SVG viewport. / 纵向 viewBox 在 SVG 视口内留下两侧留边。
const _meetSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="120" height="80" viewBox="0 0 40 80">
  <rect x="-25" y="10" width="20" height="20" fill="red"/>
</svg>
''';

/// The blue rectangle extends into the layout margin and beyond the widget. / 蓝色矩形延伸到布局留边及组件以外。
String _overflowSvg(String rootAttribute) =>
    '''
<svg xmlns="http://www.w3.org/2000/svg" width="120" height="80" $rootAttribute>
  <rect x="-30" y="40" width="38" height="20" fill="blue"/>
</svg>
''';

/// The right-aligned cover crop excludes the red half at the left. / 右对齐的 cover 裁剪排除左侧红色半区。
const _coverSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="120" height="60">
  <rect width="60" height="60" fill="red"/>
  <rect x="60" width="60" height="60" fill="blue"/>
</svg>
''';

/// Captures the rendered widget and its surrounding background. / 捕获绘制后的组件及其周围背景。
Future<ByteData> _capture(
  WidgetTester tester,
  String source, {
  required bool animated,
  Size size = _containSize,
  BoxFit fit = BoxFit.contain,
  Alignment alignment = Alignment.center,
  ColorFilter? colorFilter,
}) async {
  final widget = animated
      ? AnimatedXvg.string(
          source,
          width: size.width,
          height: size.height,
          fit: fit,
          alignment: alignment,
          pixelSnap: XvgPixelSnap.never,
          colorFilter: colorFilter,
          autoplay: false,
        )
      : StaticXvg(
          source,
          width: size.width,
          height: size.height,
          fit: fit,
          alignment: alignment,
          pixelSnap: XvgPixelSnap.never,
          colorFilter: colorFilter,
        );
  await tester.pumpWidget(
    Align(
      alignment: Alignment.topLeft,
      child: RepaintBoundary(
        key: _captureKey,
        child: ColoredBox(
          color: _background,
          child: SizedBox.square(
            dimension: _canvasSize.toDouble(),
            child: Stack(
              clipBehavior: Clip.none,
              textDirection: TextDirection.ltr,
              children: [
                Positioned(left: _origin.dx, top: _origin.dy, child: widget),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  return (await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureKey),
    );
    final image = await boundary.toImage();
    try {
      return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    } finally {
      image.dispose();
    }
  }))!;
}

/// Reads one opaque RGBA pixel relative to the widget origin. / 读取相对组件原点的不透明 RGBA 像素。
Color _pixel(ByteData bytes, int x, int y) {
  final index =
      ((_origin.dy.toInt() + y) * _canvasSize + _origin.dx.toInt() + x) *
      Uint32List.bytesPerElement;
  final rgba = bytes.getUint32(index);
  return Color((rgba >> 8) | ((rgba & 0xff) << 24));
}

void main() {
  setUpAll(() async => RustLib.init());
  tearDownAll(() => RustXvgPictureCache.instance.clear());

  for (final animated in [false, true]) {
    group(animated ? 'animated image viewport' : 'static image viewport', () {
      testWidgets('meet retains paint between the viewBox and SVG viewport', (
        tester,
      ) async {
        final pixels = await _capture(tester, _meetSvg, animated: animated);
        expect(_pixel(pixels, 40, 20), _red);
        expect(_pixel(pixels, 10, 20), _background);
      });

      for (final attribute in ['', 'overflow="visible"']) {
        final label = attribute.isEmpty ? 'default root overflow' : attribute;
        testWidgets('$label is clipped at the SVG viewport', (tester) async {
          final pixels = await _capture(
            tester,
            _overflowSvg(attribute),
            animated: animated,
          );
          expect(_pixel(pixels, 24, 50), _blue);
          expect(_pixel(pixels, 14, 50), _background);
          expect(_pixel(pixels, -5, 50), _background);
        });
      }

      testWidgets('cover scales proportionally and clips at the component', (
        tester,
      ) async {
        final pixels = await _capture(
          tester,
          _coverSvg,
          animated: animated,
          size: _coverSize,
          fit: BoxFit.cover,
          alignment: Alignment.centerRight,
        );
        expect(_pixel(pixels, -5, 30), _background);
        expect(_pixel(pixels, 5, 30), _blue);
        expect(_pixel(pixels, 55, 30), _blue);
        expect(_pixel(pixels, 65, 30), _background);
      });

      testWidgets('color filter is confined to the fitted SVG viewport', (
        tester,
      ) async {
        final pixels = await _capture(
          tester,
          _meetSvg,
          animated: animated,
          colorFilter: const ColorFilter.mode(_blue, BlendMode.srcOver),
        );
        expect(_pixel(pixels, -5, 45), _background);
        expect(_pixel(pixels, 10, 45), _background);
        expect(_pixel(pixels, 25, 45), _blue);
      });
    });
  }

  testWidgets('bounds proven inside the SVG viewport skip the canvas clip', (
    tester,
  ) async {
    for (final (source, clips) in [(_meetSvg, 0), (_overflowSvg(''), 1)]) {
      await _capture(tester, source, animated: false);
      final painter = tester
          .widget<CustomPaint>(find.byType(CustomPaint))
          .painter!;
      final canvas = TestRecordingCanvas();
      painter.paint(canvas, _containSize);
      final clipCommands = canvas.invocations.where(
        (call) => call.invocation.memberName == #clipRect,
      );
      expect(clipCommands, hasLength(clips));
    }
  });
}
