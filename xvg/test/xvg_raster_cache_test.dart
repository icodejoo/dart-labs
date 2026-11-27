import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:xvg/src/pixel_snap_layer.dart';
import 'package:xvg/src/xvg_raster_cache.dart';
import 'package:xvg/xvg.dart';

/// SVG with semi-transparent geometry, gradient detail and a real clip boundary.
/// 同时包含半透明图元、渐变细节和实际裁剪边界的 SVG。
const _art = '''
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="2048">
  <defs>
    <clipPath id="clip"><rect x="8" y="8" width="1008" height="2032" rx="17"/></clipPath>
    <linearGradient id="ink"><stop stop-color="#3ab"/><stop offset="1" stop-color="#ed9"/></linearGradient>
  </defs>
  <g clip-path="url(#clip)">
    <rect width="1024" height="2048" fill="url(#ink)"/>
    <path d="M20 32 Q 760 250 1000 980 L 660 1130 Q 340 720 20 218Z" fill="#542" opacity=".65"/>
    <rect x="230" y="790" width="580" height="280" rx="40" fill="#a52" opacity=".55"/>
  </g>
</svg>
''';

/// SVG with independently verifiable currentColor painting. / 可独立验证 currentColor 的 SVG。
const _flat = '''
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="2048">
  <rect width="1024" height="2048" fill="currentColor"/>
</svg>
''';

/// A blur crossing two tile seams. / 横跨两条分块边的模糊图形。
const _blur = '''
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="2048">
  <defs><filter id="b" x="-1" y="-1" width="3" height="3">
    <feGaussianBlur stdDeviation="24"/>
  </filter></defs>
  <rect width="1024" height="2048" fill="#142758"/>
  <circle cx="490" cy="498" r="80" fill="#f8b429" filter="url(#b)" opacity=".7"/>
</svg>
''';

/// Fixed image size used to test owner and DPR changes. / 测试缓存所有者和 DPR 变化的固定图像尺寸。
const _smallExtent = 400.0;

/// Color for the second owner and the source update. / 用于第二个缓存所有者及源更新的颜色。
const _secondColor = Color(0xff24507c);

/// Interior tile texture extent with two sampling pixels on each side.
/// 每边两像素采样边的内块纹理长度。
const _interiorExtent = XvgRasterCache.tileSize + 4;

/// Outer tile texture extent with two extra pixels at the artwork edge.
/// 插画边缘额外覆盖两像素的边缘块纹理长度。
const _edgeExtent = _interiorExtent + 2;

/// Number of bytes per raw RGBA8 pixel. / 每个原始 RGBA8 像素的字节数。
const _rgbaBytesPerPixel = 4;

/// Largest texture in the first test viewport. / 首屏测试视口中最大的纹理。
const _topTileBytes = _edgeExtent * _edgeExtent * _rgbaBytesPerPixel;

/// Texture spanning an edge in one direction. / 仅一个方向碰到插画边缘的纹理。
const _sideTileBytes = _edgeExtent * _interiorExtent * _rgbaBytesPerPixel;

/// Four textures in the first or last test viewport. / 测试首屏或末屏的四张纹理。
const _fourTileBytes = 2 * (_topTileBytes + _sideTileBytes);

/// Two half-resolution edge textures for the 512 × 1024 fitted artwork.
/// 512 × 1024 适配插画的两张半分辨率边缘纹理。
const _twoHalfTiles = 2 * (_edgeExtent + 2) * _edgeExtent;

/// Default full visible test width in physical pixels. / 测试使用的物理显示宽度。
const _width = 1024;

/// Test widget width at the default DPR. / 默认 DPR 下测试组件的逻辑宽度。
const double _logicalWidth = _width * 1.0;

/// The default viewport and capture height at DPR 1. / DPR 为 1 时默认视口及截图的高度。
const _defaultViewportHeight = 900;

/// Viewport tall enough to prefetch a third tile row. / 高度足以预取第三行分块的视口。
const _prefetchViewportHeight = 1000.0;

/// Byte stride of a captured image row. / 截图中每行的字节数。
const _rowBytes = _width * _rgbaBytesPerPixel;

/// Cache settings at native resolution. / 原分辨率缓存配置。
const _fullResolutionCache = XvgRasterCacheOverride.enabled;

/// Cache settings at half resolution. / 半分辨率缓存配置。
const _halfResolutionCache = XvgRasterCacheOverride.halfResolution;

/// White background for comparing composited output. / 用于对照合成结果的白色背景。
const _white = Color(0xffffffff);

/// A visible solid tint for testing post-cache color filtering. / 验证缓存后滤镜的实色。
const _tint = Color(0xff507c24);

/// Time between test animation frames. / 测试动画的帧间隔。
const _frameInterval = Duration(milliseconds: 16);

/// Expected admission threshold. / 自动缓存的预期重放门槛。
const _automaticFrames = 32;

/// Advances real composition frames. / 推进真实合成帧。
Future<void> _replay(WidgetTester tester, int frames) async {
  for (var index = 0; index < frames; index++) {
    tester.binding.scheduleFrame();
    await tester.pump(_frameInterval);
  }
}

/// Builds a contained illustration at the path threshold. / 创建刚达到路径门槛的框内插画。
String _complexArt({bool overflow = false}) =>
    '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">'
    '${List.filled(100, '<path fill="#507c24" d="M0 0 H100 V100 H0 Z"/>').join()}'
    '${overflow ? '<rect x="95" y="30" width="25" height="10"/>' : ''}</svg>';

/// Places the same art under a stable or moving transform. / 在稳定或移动的变换下放置同一幅插画。
Widget _automaticArt(
  String source, {
  double extent = 100,
  double scale = 1,
  Offset offset = Offset.zero,
  ColorFilter? filter,
  XvgPixelSnap snap = XvgPixelSnap.auto,
}) => Align(
  alignment: Alignment.topLeft,
  child: Transform(
    transform: Matrix4.translationValues(offset.dx, offset.dy, 0)
      ..scaleByDouble(scale, scale, 1, 1),
    child: StaticXvg(
      source,
      width: extent,
      height: extent,
      colorFilter: filter,
      pixelSnap: snap,
    ),
  ),
);

/// Time needed for a new raster grid to settle. / 新栅格停稳所需的时间。
const _gridSettleTime = Duration(milliseconds: 80);

/// Successive fractional scroll positions that stay in the same tile rows.
/// 保持在同一分块行内的连续小数滚动位置。
const _fractionalScrollOffsets = [1.25, 2.5, 3.75, 5.25, 6.5, 7.75];

/// Paints a known-width SVG under a clipped, optionally scrolling viewport.
/// 在可裁剪、可滚动视口内绘制已知宽度的 SVG。
Widget _scene({
  XvgRasterCacheOverride? cache = XvgRasterCacheOverride.disabled,
  ScrollController? scroll,
  String source = _art,
  double imageHeight = 2048,
  double viewportHeight = _defaultViewportHeight * 1.0,
  Alignment alignment = Alignment.center,
  ColorFilter? filter,
  XvgTheme? theme,
  bool dispatch = false,
  XvgPixelSnap pixelSnap = XvgPixelSnap.auto,
}) {
  debugXvgRasterCacheOverride = cache;
  final child = dispatch
      ? Xvg.string(
          source,
          width: _logicalWidth,
          height: imageHeight,
          alignment: alignment,
          colorFilter: filter,
          theme: theme,
          pixelSnap: pixelSnap,
        )
      : StaticXvg(
          source,
          width: _logicalWidth,
          height: imageHeight,
          alignment: alignment,
          colorFilter: filter,
          theme: theme,
          pixelSnap: pixelSnap,
        );
  return Directionality(
    textDirection: TextDirection.ltr,
    child: ColoredBox(
      color: _white,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: _logicalWidth,
          height: viewportHeight,
          child: SingleChildScrollView(controller: scroll, child: child),
        ),
      ),
    ),
  );
}

/// Builds independent cached artwork with a stable render object. / 构建渲染对象稳定的独立缓存插画。
Widget _small({required Color color, String source = _flat}) => StaticXvg(
  source,
  width: _smallExtent,
  height: _smallExtent,
  fit: BoxFit.fill,
  theme: XvgTheme(currentColor: color),
);

/// Scales the same artwork from its top left. / 从左上角缩放同一幅插画。
Widget _zoomed(Widget artwork, double scale) => Align(
  alignment: Alignment.topLeft,
  child: Transform.scale(
    scale: scale,
    alignment: Alignment.topLeft,
    child: artwork,
  ),
);

/// Places siblings side by side, optionally keeping the first mounted offstage.
/// 把两幅插画并排摆放，可让第一幅保持挂载但不参与绘制。
Widget _siblings({required bool firstVisible}) => Align(
  alignment: Alignment.topLeft,
  child: Row(
    textDirection: TextDirection.ltr,
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: _smallExtent,
        child: Offstage(
          offstage: !firstVisible,
          child: _small(color: _tint),
        ),
      ),
      _small(color: _secondColor),
    ],
  ),
);

/// Configures a view with space beyond the inner scroll clip. / 设置大于内部滚动裁剪范围的屏幕。
void _screen(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(_logicalWidth, 1450);
  addTearDown(tester.view.reset);
}

/// Advances frames while allowing the engine's async image Future to complete.
/// 推进帧并等待引擎的异步图像 Future 完成。
Future<void> _waitTiles(WidgetTester tester, int count) async {
  for (var frame = 0; frame < 90; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 8)),
    );
    await tester.pump(_frameInterval);
    if (XvgRasterCache.tileCount == count && frame >= count) return;
  }
  expect(XvgRasterCache.tileCount, count);
}

/// Records one composition's canvas commands for inspection. / 录下单次合成的画布指令供检查。
class _RasterTestBinding extends AutomatedTestWidgetsFlutterBinding {
  /// When set, records commands separately from the engine canvas. / 设置后将命令单独录到测试画布上。
  TestRecordingCanvas? recording;

  /// Records the commands submitted by the cache layer. / 记录缓存图层提交的合成指令。
  TestRecordingCanvas recordComposition() {
    final canvas = TestRecordingCanvas();
    recording = canvas;
    try {
      renderViews.single.debugLayer!.buildScene(ui.SceneBuilder()).dispose();
    } finally {
      recording = null;
    }
    return canvas;
  }

  /// Opens the engine recorder even when collecting test commands. / 采集测试命令时仍开启引擎录制器。
  @override
  ui.Canvas createCanvas(ui.PictureRecorder recorder) {
    final canvas = super.createCanvas(recorder);
    return recording ?? canvas;
  }
}

/// Draws visible geometry without reporting bounds to the cache layer. / 绘制可见图形但不提供内容边界。
class _UnknownBoundsPainter extends CustomPainter {
  /// Draws a solid box so the fallback can be checked. / 画实色盒子以验证回退。
  @override
  void paint(Canvas canvas, Size size) =>
      canvas.drawRect(Offset.zero & size, Paint()..color = _tint);

  /// This fixture is immutable. / 测试图形固定。
  @override
  bool shouldRepaint(_UnknownBoundsPainter oldDelegate) => false;
}

/// Captures the physical root scene, including PixelSnapBoundary and clipping.
/// 捕获物理像素根场景，包含像素对齐边界和裁剪。
Future<Uint8List> _capture(WidgetTester tester) async {
  return (await tester.runAsync(() async {
    final layer = tester.binding.renderViews.single.debugLayer!;
    final scene = layer.buildScene(ui.SceneBuilder());
    try {
      return await _readScene(scene);
    } finally {
      scene.dispose();
    }
  }))!;
}

/// Reads pixels from a built scene. / 从已构建的场景读取像素。
Future<Uint8List> _readScene(ui.Scene scene) async {
  final image = await scene.toImage(_width, _defaultViewportHeight);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer
        .asUint8List();
  } finally {
    image.dispose();
  }
}

/// Sends the framework's memory pressure notification. / 发送框架的内存压力通知。
Future<void> _sendMemoryPressure(WidgetTester tester) =>
    tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/system',
      const JSONMessageCodec().encodeMessage(<String, String>{
        'type': 'memoryPressure',
      }),
      (_) {},
    );

/// Converts an 8-bit RGBA pixel to ARGB for direct color assertions. / 将 RGBA8 像素转成 ARGB。
int _pixel(Uint8List bytes, int x, int y) {
  final i = (y * _width + x) * _rgbaBytesPerPixel;
  return bytes[i + 3] << 24 | bytes[i] << 16 | bytes[i + 1] << 8 | bytes[i + 2];
}

/// Separates one-step compositing rounding from antialiasing at real edges.
/// 区分一色阶合成舍入和实际边缘上的抗锯齿覆盖差。
void _expectRoundingOrEdges(Uint8List raster, Uint8List vector) {
  var peak = 0;
  var changedEdges = 0;
  var changedInterior = 0;
  (int, int)? badPixel;
  for (var i = 0; i < raster.length; i += _rgbaBytesPerPixel) {
    var delta = 0;
    for (var channel = 0; channel < _rgbaBytesPerPixel; channel++) {
      final difference = (raster[i + channel] - vector[i + channel]).abs();
      if (difference > delta) delta = difference;
    }
    if (delta <= 1) continue;
    if (delta > peak) peak = delta;
    final pixel = i ~/ _rgbaBytesPerPixel;
    final x = pixel % _width;
    final y = pixel ~/ _width;
    final edge =
        [
          if (x > 0) i - _rgbaBytesPerPixel,
          if (x < _width - 1) i + _rgbaBytesPerPixel,
          if (y > 0) i - _rowBytes,
          if (i + _rowBytes < raster.length) i + _rowBytes,
        ].any(
          (neighbor) => Iterable<int>.generate(3).any(
            (channel) =>
                (vector[i + channel] - vector[neighbor + channel]).abs() > 8,
          ),
        );
    if (edge) {
      changedEdges++;
    } else {
      changedInterior++;
      badPixel = (x, y);
    }
  }
  debugPrint(
    'Pixel comparison: peak=$peak, edges=$changedEdges, interior=$changedInterior at $badPixel',
  );
  // A local jump of more than 8 8-bit levels marks a geometric edge. On the
  // chosen translucent fixture an AA coverage change can move up to 24
  // levels (about 9% of the full channel range). Interior pixels allow one
  // step of premultiplied compositing rounding.
  // 局部跳变超过 8 色阶视为图元边缘。半透明夹具允许边缘覆盖变化 24 色阶
  // （全通道约 9%），内部只允许预乘合成的一个舍入色阶。
  expect(changedInterior, 0, reason: 'last interior difference at $badPixel');
  expect(changedEdges, lessThan(raster.length ~/ _rgbaBytesPerPixel ~/ 200));
  expect(peak, lessThanOrEqualTo(24));
}

/// Registers renderer and cache behavior tests. / 注册渲染器和缓存行为用例。
void main() {
  final binding = _RasterTestBinding();
  setUpAll(() async {
    await RustLib.init();
  });

  setUp(() {
    XvgRasterCache.byteBudget = XvgRasterCache.defaultByteBudget;
    debugXvgRasterCacheOverride = _fullResolutionCache;
  });
  tearDown(() => debugXvgRasterCacheOverride = null);

  testWidgets('kept-alive artwork repaints when scrolled back into view', (
    tester,
  ) async {
    _screen(tester);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: _white,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: _smallExtent,
              height: _smallExtent,
              child: ListView(
                controller: scroll,
                itemExtent: _smallExtent,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: false,
                addSemanticIndexes: false,
                children: [
                  KeepAlive(keepAlive: true, child: _small(color: _tint)),
                  const SizedBox.shrink(),
                  const SizedBox.shrink(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final artwork = find.byType(StaticXvg, skipOffstage: false);
    final original = tester.element(artwork);
    await _waitTiles(tester, 1);
    expect(_pixel(await _capture(tester), 100, 100), _tint.toARGB32());

    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    expect(tester.element(artwork), same(original));
    expect(XvgRasterCache.tileCount, 0);
    expect(_pixel(await _capture(tester), 100, 100), _white.toARGB32());

    scroll.jumpTo(0);
    await tester.pump();
    expect(tester.element(artwork), same(original));
    expect(_pixel(await _capture(tester), 100, 100), _tint.toARGB32());
  });

  testWidgets('brief scale change falls back and reuses the original grid', (
    tester,
  ) async {
    _screen(tester);
    final artwork = _small(color: _tint);
    final images = <ui.Image>[];
    final previousOnCreate = ui.Image.onCreate;
    ui.Image.onCreate = (image) {
      previousOnCreate?.call(image);
      if (image.width != _width) images.add(image);
    };
    addTearDown(() => ui.Image.onCreate = previousOnCreate);
    await tester.pumpWidget(_zoomed(artwork, 1));
    await _waitTiles(tester, 1);
    final tile = images.single;
    final disposed = XvgRasterCache.disposedTileCount;

    await tester.pumpWidget(_zoomed(artwork, 0.98), duration: _frameInterval);
    expect(debugXvgRasterTilesReady, isFalse);
    expect(XvgRasterCache.tileCount, 1);
    expect(XvgRasterCache.disposedTileCount, disposed);
    expect(_pixel(await _capture(tester), 100, 100), _tint.toARGB32());

    await tester.pumpWidget(_zoomed(artwork, 1), duration: _frameInterval);
    expect(debugXvgRasterTilesReady, isTrue);
    await tester.pump(_gridSettleTime);
    expect(images, [tile]);
    expect(tile.debugDisposed, isFalse);
    expect(XvgRasterCache.disposedTileCount, disposed);
  });

  testWidgets(
    'tiles evicted during scale motion can be regenerated on return',
    (tester) async {
      _screen(tester);
      final artwork = _small(color: _tint);
      await tester.pumpWidget(_zoomed(artwork, 1));
      await _waitTiles(tester, 1);
      final disposed = XvgRasterCache.disposedTileCount;

      await tester.pumpWidget(_zoomed(artwork, 0.98), duration: _frameInterval);
      expect(XvgRasterCache.tileCount, 1);
      await _sendMemoryPressure(tester);
      expect(XvgRasterCache.tileCount, 0);
      expect(XvgRasterCache.disposedTileCount, disposed + 1);

      await tester.pumpWidget(_zoomed(artwork, 1), duration: _frameInterval);
      expect(_pixel(await _capture(tester), 100, 100), _tint.toARGB32());
      await _waitTiles(tester, 1);
      expect(debugXvgRasterTilesReady, isTrue);
      expect(XvgRasterCache.disposedTileCount, disposed + 1);
    },
  );

  testWidgets(
    'infinite preferred width matches CustomPaint in IntrinsicWidth',
    (tester) async {
      _screen(tester);
      Widget app(XvgRasterCacheOverride? cache) {
        debugXvgRasterCacheOverride = cache ?? XvgRasterCacheOverride.disabled;
        return Align(
          alignment: Alignment.topLeft,
          child: IntrinsicWidth(
            child: StaticXvg(
              _flat,
              width: double.infinity,
              height: _smallExtent,
            ),
          ),
        );
      }

      await tester.pumpWidget(app(null));
      expect(tester.takeException(), isNull);
      final size = tester.getSize(find.byType(IntrinsicWidth));
      expect(size.width, 0);

      await tester.pumpWidget(app(_fullResolutionCache));
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(IntrinsicWidth)), size);
    },
  );

  testWidgets('the submitted composite survives until replacement or clear', (
    tester,
  ) async {
    _screen(tester);
    await tester.pumpWidget(_zoomed(_small(color: _tint), 1));
    await _waitTiles(tester, 1);
    final root = binding.renderViews.single.debugLayer!;
    final pictures = <ui.Picture>[];
    final previousOnCreate = ui.Picture.onCreate;
    ui.Picture.onCreate = (picture) {
      previousOnCreate?.call(picture);
      pictures.add(picture);
    };
    addTearDown(() => ui.Picture.onCreate = previousOnCreate);

    final scene = root.buildScene(ui.SceneBuilder());
    addTearDown(scene.dispose);
    final first = pictures.single;
    expect(first.debugDisposed, isFalse);

    root.buildScene(ui.SceneBuilder()).dispose();
    expect(pictures, hasLength(2));
    final second = pictures.last;
    expect(first.debugDisposed, isTrue);
    expect(second.debugDisposed, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(second.debugDisposed, isTrue);
    final bytes = (await tester.runAsync(() => _readScene(scene)))!;
    expect(_pixel(bytes, 100, 100), _tint.toARGB32());
  });

  testWidgets('complete small artwork composes tiles without vector replay', (
    tester,
  ) async {
    _screen(tester);
    await tester.pumpWidget(_zoomed(_small(color: _tint), 1));
    await _waitTiles(tester, 1);
    expect(debugXvgRasterTilesReady, isTrue);
    expect(_pixel(await _capture(tester), 100, 100), _tint.toARGB32());

    final draws = binding.recordComposition().invocations.map(
      (draw) => draw.invocation.memberName,
    );
    expect(draws, contains(#drawImageRect));
    expect(draws, isNot(contains(#drawPicture)));
  });

  testWidgets('tile padding covers subpixel overflow without vector replay', (
    tester,
  ) async {
    _screen(tester);
    const source = '''
<svg xmlns="http://www.w3.org/2000/svg" width="512" height="400">
  <path d="M-.0002 0H512.0002V400.0002H-.0002Z" fill="#507c24"/>
</svg>
''';
    Widget app(XvgRasterCacheOverride? cache) {
      debugXvgRasterCacheOverride = cache ?? XvgRasterCacheOverride.disabled;
      return Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: StaticXvg(source),
        ),
      );
    }

    await tester.pumpWidget(app(null));
    final vector = await _capture(tester);
    expect(_pixel(vector, 100, 100), _tint.toARGB32());

    await tester.pumpWidget(app(_fullResolutionCache));
    await _waitTiles(tester, 1);
    expect(debugXvgRasterTilesReady, isTrue);
    expect(await _capture(tester), vector);

    final draws = binding.recordComposition().invocations.map(
      (draw) => draw.invocation.memberName,
    );
    expect(draws.where((draw) => draw == #drawImageRect), hasLength(1));
    expect(draws, isNot(contains(#drawPicture)));
  });

  testWidgets('sparse artwork only generates tiles intersecting its content', (
    tester,
  ) async {
    _screen(tester);
    const source = '''
<svg xmlns="http://www.w3.org/2000/svg" width="400" height="325">
  <rect x="300" y="185" width="50" height="20" fill="#507c24"/>
</svg>
''';
    Widget app(XvgRasterCacheOverride? cache) {
      debugXvgRasterCacheOverride = cache ?? XvgRasterCacheOverride.disabled;
      return _zoomed(
        StaticXvg(
          source,
          width: 800,
          height: 850,
          alignment: Alignment.bottomCenter,
        ),
        1,
      );
    }

    await tester.pumpWidget(app(null));
    final vector = await _capture(tester);
    expect(_pixel(vector, 650, 590), _tint.toARGB32());

    await tester.pumpWidget(app(_fullResolutionCache));
    await _waitTiles(tester, 1);
    await tester.pump(_frameInterval);
    expect(XvgRasterCache.tileCount, 1);
    expect(debugXvgRasterTilesReady, isTrue);
    expect(await _capture(tester), vector);
  });

  testWidgets(
    'unknown bounds compose the full viewport without vector replay',
    (tester) async {
      _screen(tester);
      const source =
          '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="400"/>';
      await tester.pumpWidget(_zoomed(const StaticXvg(source), 1));
      await _waitTiles(tester, 1);
      expect(debugXvgRasterTilesReady, isTrue);
      final draws = binding.recordComposition().invocations.map(
        (draw) => draw.invocation.memberName,
      );
      expect(draws, contains(#drawImageRect));
      expect(draws, isNot(contains(#drawPicture)));
    },
  );

  testWidgets('complete small artwork clips overflow without vector replay', (
    tester,
  ) async {
    _screen(tester);
    const source = '''
<svg xmlns="http://www.w3.org/2000/svg" width="600" height="400">
  <rect width="600" height="400" fill="#507c24"/>
  <rect x="580" y="80" width="60" height="40" fill="#24507c"/>
</svg>
''';
    Widget app(XvgRasterCacheOverride? cache) {
      debugXvgRasterCacheOverride = cache ?? XvgRasterCacheOverride.disabled;
      return Align(alignment: Alignment.topLeft, child: StaticXvg(source));
    }

    await tester.pumpWidget(app(null));
    final vector = await _capture(tester);
    expect(_pixel(vector, 100, 100), _tint.toARGB32());
    expect(_pixel(vector, 590, 100), _secondColor.toARGB32());
    expect(_pixel(vector, 620, 100), 0);

    await tester.pumpWidget(app(_fullResolutionCache));
    await _waitTiles(tester, 2);
    expect(debugXvgRasterTilesReady, isTrue);
    expect(await _capture(tester), vector);

    final differenceClips = binding.recordComposition().invocations.where(
      (draw) =>
          draw.invocation.memberName == #clipRect &&
          draw.invocation.namedArguments[#clipOp] == ui.ClipOp.difference,
    );
    expect(differenceClips, isEmpty);
  });

  testWidgets('the SVG viewport clips Flutter blur expansion', (tester) async {
    _screen(tester);
    const source = '''
<svg xmlns="http://www.w3.org/2000/svg" width="400" height="400">
  <defs><filter id="blur" x="0" y="0" width="1" height="1">
    <feGaussianBlur stdDeviation="10"/>
  </filter></defs>
  <rect x="370" y="80" width="30" height="40" fill="#24507c" filter="url(#blur)"/>
</svg>
''';
    Widget app(XvgRasterCacheOverride? cache) {
      debugXvgRasterCacheOverride = cache ?? XvgRasterCacheOverride.disabled;
      return _zoomed(StaticXvg(source), 1);
    }

    await tester.pumpWidget(app(null));
    final vector = await _capture(tester);
    const overflowX = 410;
    const centerY = 100;
    expect(_pixel(vector, 399, centerY), isNot(0));
    expect(_pixel(vector, overflowX, centerY), 0);

    await tester.pumpWidget(app(_fullResolutionCache));
    await _waitTiles(tester, 1);
    expect(debugXvgRasterTilesReady, isTrue);
    expect(await _capture(tester), vector);
  });

  testWidgets('a recolor that fills transparent pixels keeps vector bounds', (
    tester,
  ) async {
    _screen(tester);
    const source = '''
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="2048">
  <rect x="150" y="150" width="200" height="100" fill="#14ab3e"/>
</svg>
''';
    const filter = ColorFilter.mode(Color(0x60502000), BlendMode.srcOver);
    await tester.pumpWidget(_scene(source: source, filter: filter));
    final vector = await _capture(tester);
    await tester.pumpWidget(
      _scene(source: source, filter: filter, cache: _fullResolutionCache),
    );
    await _waitTiles(tester, 4);
    final cached = await _capture(tester);
    expect(_pixel(vector, 250, 200), isNot(0xff14ab3e));
    expect(cached, vector);
  });

  testWidgets('automatic whole-viewport tiles match filtered vector pixels', (
    tester,
  ) async {
    _screen(tester);
    final source =
        '''
<svg xmlns="http://www.w3.org/2000/svg" width="600" height="600">
  <rect x="485" y="30" width="50" height="50" fill="#507c24" opacity=".63"/>
  ${List.filled(xvgRasterMinPaths, '<path d="M490 85 H500 V90 H490 Z"/>').join()}
</svg>
''';
    const filterOffset = ColorFilter.matrix([
      1,
      0,
      0,
      0,
      10,
      0,
      1,
      0,
      0,
      20,
      0,
      0,
      1,
      0,
      30,
      0,
      0,
      0,
      .5,
      96,
    ]);
    Widget artwork(XvgRasterCacheOverride? mode, ColorFilter filter) {
      debugXvgRasterCacheOverride = mode;
      return _automaticArt(
        source,
        extent: 600,
        offset: const Offset(16, 16),
        filter: filter,
        snap: XvgPixelSnap.never,
      );
    }

    for (final filter in [
      const ColorFilter.mode(_tint, BlendMode.srcIn),
      const ColorFilter.mode(Color(0x60502000), BlendMode.srcOver),
      filterOffset,
    ]) {
      await tester.pumpWidget(artwork(XvgRasterCacheOverride.disabled, filter));
      final vector = await _capture(tester);
      await tester.pumpWidget(artwork(null, filter));
      await _replay(tester, _automaticFrames);
      await _waitTiles(tester, 4);
      expect(debugXvgRasterTilesReady, isTrue);
      final cached = await _capture(tester);
      expect(_pixel(vector, 515, 60), isNot(0));
      expect(_pixel(vector, 10, 30), 0, reason: '$filter outside viewport');
      if (filter != const ColorFilter.mode(_tint, BlendMode.srcIn)) {
        expect(
          _pixel(vector, 50, 50),
          isNot(0),
          reason: '$filter colors transparency',
        );
      }
      expect(
        _pixel(cached, 50, 50),
        _pixel(vector, 50, 50),
        reason: '$filter in blank area',
      );
      expect(cached, vector, reason: '$filter');
    }
  });

  testWidgets(
    'source replaces tiles immediately and DPR waits for a stable grid',
    (tester) async {
      _screen(tester);
      Widget app(String source) => Align(
        alignment: Alignment.topLeft,
        child: _small(color: _tint, source: source),
      );
      await tester.pumpWidget(app(_flat));
      await _waitTiles(tester, 1);
      var released = XvgRasterCache.disposedTileCount;
      final changed = _flat.replaceFirst(
        'currentColor',
        '#${_secondColor.toARGB32().toRadixString(16).substring(2)}',
      );
      await tester.pumpWidget(app(changed));
      expect(XvgRasterCache.disposedTileCount, released + 1);
      await _waitTiles(tester, 1);
      expect(_pixel(await _capture(tester), 100, 100), _secondColor.toARGB32());

      released = XvgRasterCache.disposedTileCount;
      tester.view.devicePixelRatio = 2;
      await tester.pump();
      expect(debugXvgRasterTilesReady, isFalse);
      expect(XvgRasterCache.tileCount, 1);
      expect(XvgRasterCache.disposedTileCount, released);
      await tester.pump(_gridSettleTime);
      expect(XvgRasterCache.disposedTileCount, released + 1);
      await _waitTiles(tester, 4);
      expect(_pixel(await _capture(tester), 650, 650), _secondColor.toARGB32());
    },
  );

  testWidgets('a settled scale replaces the original grid', (tester) async {
    _screen(tester);
    final artwork = _small(color: _tint);
    Widget zoomed(double scale) => _zoomed(artwork, scale);

    await tester.pumpWidget(zoomed(1));
    await _waitTiles(tester, 1);
    final bytes = XvgRasterCache.bytesUsed;
    final disposed = XvgRasterCache.disposedTileCount;

    for (final scale in [1.04, 1.08, 1.12, 1.16, 1.20, 1.24]) {
      await tester.pumpWidget(zoomed(scale), duration: _frameInterval);
      expect(debugXvgRasterTilesReady, isFalse, reason: 'scale $scale');
      expect(XvgRasterCache.tileCount, 1);
      expect(XvgRasterCache.bytesUsed, bytes);
      expect(XvgRasterCache.disposedTileCount, disposed);
    }

    await tester.pump(_frameInterval * 3);
    expect(XvgRasterCache.disposedTileCount, disposed);
    await tester.pump(_gridSettleTime - _frameInterval * 3);
    expect(XvgRasterCache.disposedTileCount, disposed + 1);
    await _waitTiles(tester, 1);
    expect(debugXvgRasterTilesReady, isTrue);
    expect(XvgRasterCache.bytesUsed, greaterThan(bytes));
    expect(XvgRasterCache.disposedTileCount, disposed + 1);
  });

  testWidgets(
    'the shared budget reclaims an offstage owner before allocating',
    (tester) async {
      _screen(tester);
      const textureExtent = _smallExtent + 8;
      final pixels = textureExtent.toInt();
      final bytes = pixels * pixels * _rgbaBytesPerPixel;
      XvgRasterCache.byteBudget = bytes;
      await tester.pumpWidget(_siblings(firstVisible: true));
      await _waitTiles(tester, 1);
      expect(XvgRasterCache.bytesUsed, bytes);
      final disposed = XvgRasterCache.disposedTileCount;

      await tester.pumpWidget(_siblings(firstVisible: false));
      await _waitTiles(tester, 1);
      expect(XvgRasterCache.disposedTileCount, disposed + 1);
      expect(XvgRasterCache.bytesUsed, bytes);
      expect(_pixel(await _capture(tester), 600, 200), _secondColor.toARGB32());
    },
  );

  testWidgets('Xvg only applies tile caching on the static path', (
    tester,
  ) async {
    _screen(tester);
    final source = _flat.replaceFirst(
      '/>',
      '><animate attributeName="opacity" values="1;0" dur="1s" repeatCount="indefinite"/></rect>',
    );
    await tester.pumpWidget(
      _scene(source: source, dispatch: true, cache: _fullResolutionCache),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byType(AnimatedXvg), findsOneWidget);
    expect(XvgRasterCache.tileCount, 0);
  });

  testWidgets('filter coverage remains consistent across tile edges', (
    tester,
  ) async {
    _screen(tester);
    await tester.pumpWidget(_scene(source: _blur));
    final vector = await _capture(tester);
    await tester.pumpWidget(_scene(source: _blur, cache: _fullResolutionCache));
    await _waitTiles(tester, 4);
    final full = await _capture(tester);
    // A blur is continuous inside this fixture. The two seams allow one
    // 8-bit rounding step. / 模糊连续穿过两条拼缝，只容许一色阶的舍入。
    var worst = 0;
    const seam = XvgRasterCache.tileSize;
    for (var p = 375; p < 645; p++) {
      for (var offset = -2; offset <= 2; offset++) {
        for (final (x, y) in [(seam + offset, p), (p, seam + offset)]) {
          final start = (y * _width + x) * _rgbaBytesPerPixel;
          for (var i = start; i < start + _rgbaBytesPerPixel; i++) {
            final delta = (full[i] - vector[i]).abs();
            if (delta > worst) worst = delta;
          }
        }
      }
    }
    expect(worst, lessThanOrEqualTo(1));
  });

  testWidgets('automatic mode keeps low-complexity icons on CustomPaint', (
    tester,
  ) async {
    _screen(tester);
    await tester.pumpWidget(
      _scene(cache: null, source: _flat, imageHeight: 48),
    );
    expect(
      find.descendant(
        of: find.byType(StaticXvg),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
    await _replay(tester, _automaticFrames * 2);
    expect(XvgRasterCache.tileCount, 0);
    expect(XvgRasterCache.bytesUsed, 0);
  });

  group('automatic cache', () {
    setUp(() => debugXvgRasterCacheOverride = null);

    testWidgets('admits a contained illustration on its 32nd stable replay', (
      tester,
    ) async {
      _screen(tester);
      final source = _complexArt();
      final info = RustXvgPictureCache.instance.getOrRender(source);
      expect(info.pathCount, 100);
      expect(info.pointCount, lessThan(15000));
      await tester.pumpWidget(_automaticArt(source));
      await _replay(tester, _automaticFrames - 2);
      expect(XvgRasterCache.tileCount, 0);
      expect(XvgRasterCache.bytesUsed, 0);
      // Independent scene captures must not advance the replay counter.
      // 独立场景截图不能增加重放次数。
      binding.recordComposition();
      binding.recordComposition();
      expect(XvgRasterCache.tileCount, 0);
      await _replay(tester, 1);
      await tester.idle();
      expect(XvgRasterCache.tileCount, 1);
      expect(
        binding.recordComposition().invocations.map(
          (draw) => draw.invocation.memberName,
        ),
        contains(#drawImageRect),
      );
    });

    testWidgets('counts curve controls on the asynchronous picture cache path', (
      tester,
    ) async {
      _screen(tester);
      final source =
          '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">'
          '<path d="M0 0 ${List.filled(5000, 'C20 0 100 80 80 100').join(' ')} Z"/>'
          '</svg>';
      final cache = RustXvgPictureCache.instance;
      final info = (await tester.runAsync(
        () => cache.getOrRenderAsync(source),
      ))!;
      expect(cache.peek(source), same(info));
      expect(info.pathCount, 1);
      expect(info.pointCount, 15001);
      await tester.pumpWidget(_automaticArt(source));
      await _replay(tester, _automaticFrames);
      expect(XvgRasterCache.tileCount, 1);
    });

    testWidgets('caches complex overflow and matches clipped vector pixels', (
      tester,
    ) async {
      _screen(tester);
      const extent = 600.0;
      final source = _complexArt(overflow: true);
      final info = RustXvgPictureCache.instance.getOrRender(source);
      expect(info.pathCount, greaterThanOrEqualTo(xvgRasterMinPaths));
      expect(info.contentBounds!.right, greaterThan(info.size.width));
      final scene = _automaticArt(
        source,
        extent: extent,
        snap: XvgPixelSnap.never,
      );
      debugXvgRasterCacheOverride = XvgRasterCacheOverride.disabled;
      await tester.pumpWidget(scene);
      final vector = await _capture(tester);
      debugXvgRasterCacheOverride = null;
      await tester.pumpWidget(
        _automaticArt(source, extent: extent, snap: XvgPixelSnap.never),
      );
      await _replay(tester, _automaticFrames);
      await _waitTiles(tester, 4);
      expect(debugXvgRasterTilesReady, isTrue);
      expect(_pixel(vector, 590, 210), 0xff000000);
      expect(_pixel(vector, 610, 210), 0);
      expect(await _capture(tester), vector);
    });

    testWidgets(
      'uses the full viewport when the candidate has unknown bounds',
      (tester) async {
        _screen(tester);
        await tester.pumpWidget(
          Align(
            alignment: Alignment.topLeft,
            child: XvgRasterPaint(
              preferredSize: const Size.square(100),
              intrinsicSize: const Size.square(100),
              fit: BoxFit.contain,
              alignment: Alignment.center,
              painter: _UnknownBoundsPainter(),
              cacheOverride: null,
              snapWhenCached: true,
            ),
          ),
        );
        await _replay(tester, _automaticFrames * 2);
        expect(XvgRasterCache.tileCount, 1);
        expect(debugXvgRasterTilesReady, isTrue);
        expect(_pixel(await _capture(tester), 10, 10), _tint.toARGB32());
      },
    );

    testWidgets('releases tiles when scaled beyond 12 MiB or scrolled out', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size.square(2400);
      addTearDown(tester.view.reset);
      final source = _complexArt();
      await tester.pumpWidget(_automaticArt(source));
      await _replay(tester, _automaticFrames);
      expect(XvgRasterCache.tileCount, 1);
      final disposed = XvgRasterCache.disposedTileCount;
      await tester.pumpWidget(_automaticArt(source, scale: 21.12));
      expect(XvgRasterCache.tileCount, 0);
      expect(XvgRasterCache.disposedTileCount, disposed + 1);
      await _replay(tester, _automaticFrames * 2);
      expect(XvgRasterCache.tileCount, 0);
      expect(XvgRasterCache.bytesUsed, 0);
      await tester.pumpWidget(_automaticArt(source));
      await _replay(tester, _automaticFrames);
      expect(XvgRasterCache.tileCount, 1);
      await tester.pumpWidget(
        _automaticArt(source, offset: const Offset(0, -150)),
      );
      expect(XvgRasterCache.tileCount, 0);
      expect(XvgRasterCache.disposedTileCount, disposed + 2);
    });

    testWidgets(
      'releases the composite when mounted artwork leaves the scene',
      (tester) async {
        _screen(tester);
        final source = _complexArt();
        Widget artwork({required bool offstage}) =>
            Offstage(offstage: offstage, child: _automaticArt(source));
        await tester.pumpWidget(artwork(offstage: false));
        await _replay(tester, _automaticFrames);
        expect(XvgRasterCache.tileCount, 1);

        final pictures = <ui.Picture>[];
        final previous = ui.Picture.onCreate;
        ui.Picture.onCreate = (picture) {
          previous?.call(picture);
          pictures.add(picture);
        };
        try {
          binding.renderViews.single.debugLayer!
              .buildScene(ui.SceneBuilder())
              .dispose();
        } finally {
          ui.Picture.onCreate = previous;
        }
        final composite = pictures.single;
        expect(composite.debugDisposed, isFalse);
        await tester.pumpWidget(artwork(offstage: true));
        expect(find.byType(StaticXvg, skipOffstage: false), findsOneWidget);
        expect(composite.debugDisposed, isTrue);
        expect(XvgRasterCache.tileCount, 0);

        await tester.pumpWidget(artwork(offstage: false));
        await _replay(tester, _automaticFrames - 2);
        expect(XvgRasterCache.tileCount, 0);
        await _replay(tester, 1);
        expect(XvgRasterCache.tileCount, 1);
      },
    );

    testWidgets('does not generate tiles during continuous translation', (
      tester,
    ) async {
      _screen(tester);
      final source = _complexArt();
      final disposed = XvgRasterCache.disposedTileCount;
      for (var frame = 0; frame < _automaticFrames * 2; frame++) {
        await tester.pumpWidget(
          _automaticArt(source, offset: Offset(0, frame * 0.25)),
          duration: _frameInterval,
        );
        expect(XvgRasterCache.tileCount, 0);
      }
      expect(XvgRasterCache.disposedTileCount, disposed);
      await _replay(tester, _automaticFrames);
      expect(XvgRasterCache.tileCount, 1);
    });

    testWidgets('keeps pixelSnap auto vector pixels until a grid is admitted', (
      tester,
    ) async {
      _screen(tester);
      const origin = Offset(0.35, 0.4);
      final source = _complexArt();
      final overflow = _complexArt(overflow: true);
      for (final art in [source, overflow]) {
        debugXvgRasterCacheOverride = XvgRasterCacheOverride.disabled;
        await tester.pumpWidget(_automaticArt(art, offset: origin));
        final vector = await _capture(tester);
        await tester.pumpWidget(
          _automaticArt(art, offset: origin, snap: XvgPixelSnap.always),
        );
        final snapped = await _capture(tester);
        expect(snapped, isNot(equals(vector)));
        debugXvgRasterCacheOverride = null;
        await tester.pumpWidget(_automaticArt(art, offset: origin));
        expect(await _capture(tester), vector);
        await _replay(tester, _automaticFrames * 2);
        final automatic = await _capture(tester);
        expect(debugXvgRasterTilesReady, isTrue);
        if (art == source) {
          final alpha = _pixel(automatic, 0, 0) >>> 24;
          expect(alpha, closeTo(_pixel(snapped, 0, 0) >>> 24, 1));
          expect(alpha, greaterThan(_pixel(vector, 0, 0) >>> 24));
        } else {
          expect(_pixel(automatic, 99, 35), _pixel(snapped, 99, 35));
          expect(_pixel(automatic, 105, 35), 0);
        }
      }
    });
  });

  testWidgets('clipped scroll keeps nearby tiles and disposes distant rows', (
    tester,
  ) async {
    _screen(tester);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final images = <ui.Image>[];
    final previousOnCreate = ui.Image.onCreate;
    ui.Image.onCreate = (image) {
      previousOnCreate?.call(image);
      if (image.width <= _edgeExtent && image.height <= _edgeExtent) {
        images.add(image);
      }
    };
    addTearDown(() => ui.Image.onCreate = previousOnCreate);
    await tester.pumpWidget(
      _scene(cache: _fullResolutionCache, scroll: scroll),
    );

    expect(XvgRasterCache.tileCount, lessThanOrEqualTo(1));
    final first = await _capture(tester);
    expect(_pixel(first, 80, 80), isNot(_white.toARGB32()));

    await _waitTiles(tester, 4);
    expect(images.length, 4);
    expect(XvgRasterCache.bytesUsed, _fourTileBytes);
    final disposed = XvgRasterCache.disposedTileCount;

    scroll.jumpTo(160);
    await tester.pump();
    await _waitTiles(tester, 6);
    expect(images.length, 6);
    expect(images.any((image) => image.debugDisposed), isFalse);

    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    await _waitTiles(tester, 4);
    expect(images.length, 8);
    expect(images.where((image) => image.debugDisposed).length, 4);
    expect(XvgRasterCache.disposedTileCount - disposed, 4);
    expect(XvgRasterCache.bytesUsed, _fourTileBytes);

    final beforeUnmount = XvgRasterCache.disposedTileCount;
    await tester.pumpWidget(const SizedBox.shrink());
    expect(XvgRasterCache.bytesUsed, 0);
    expect(XvgRasterCache.disposedTileCount - beforeUnmount, 4);
    expect(images.every((image) => image.debugDisposed), isTrue);
  });

  testWidgets(
    'cached auto snaps filter artwork and reuses tiles during scroll',
    (tester) async {
      _screen(tester);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      expect(
        RustXvgPictureCache.instance.getOrRender(_blur).hasPixelSnapRisk,
        isFalse,
      );
      await tester.pumpWidget(
        _scene(source: _blur, scroll: scroll, cache: _fullResolutionCache),
      );
      await _waitTiles(tester, 4);
      expect(find.byType(PixelSnapBoundary), findsOneWidget);
      final snap = tester.binding.renderViews.single.debugLayer!
          .depthFirstIterateChildren()
          .whereType<PixelSnapLayer>()
          .single;
      final disposed = XvgRasterCache.disposedTileCount;

      for (final offset in _fractionalScrollOffsets) {
        scroll.jumpTo(offset);
        await tester.pump(_frameInterval);
        expect(snap.debugDidSnap, isTrue);
        expect(debugXvgRasterTilesReady, isTrue, reason: 'offset $offset');
        expect(XvgRasterCache.tileCount, 4);
        expect(XvgRasterCache.disposedTileCount, disposed);
      }
    },
  );

  testWidgets('cached never skips snapping and waits out fractional scroll', (
    tester,
  ) async {
    _screen(tester);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _scene(
        source: _blur,
        scroll: scroll,
        cache: _fullResolutionCache,
        pixelSnap: XvgPixelSnap.never,
      ),
    );
    await _waitTiles(tester, 4);
    expect(find.byType(PixelSnapBoundary), findsNothing);
    expect(
      tester.binding.renderViews.single.debugLayer!
          .depthFirstIterateChildren()
          .whereType<PixelSnapLayer>(),
      isEmpty,
    );
    expect(debugXvgRasterTilesReady, isTrue);
    final disposed = XvgRasterCache.disposedTileCount;

    for (final offset in _fractionalScrollOffsets) {
      scroll.jumpTo(offset);
      await tester.pump(_frameInterval);
      expect(debugXvgRasterTilesReady, isFalse, reason: 'offset $offset');
      expect(XvgRasterCache.tileCount, 4);
      expect(XvgRasterCache.disposedTileCount, disposed);
    }

    await tester.pump(_gridSettleTime);
    await _waitTiles(tester, 4);
    expect(debugXvgRasterTilesReady, isTrue);
    expect(XvgRasterCache.disposedTileCount, disposed + 4);
  });

  testWidgets(
    'memory pressure evicts adjacent tiles while keeping visible ones',
    (tester) async {
      _screen(tester);
      await tester.pumpWidget(
        _scene(
          cache: _fullResolutionCache,
          viewportHeight: _prefetchViewportHeight,
        ),
      );
      await _waitTiles(tester, 6);
      final before = XvgRasterCache.disposedTileCount;

      await _sendMemoryPressure(tester);
      await tester.pump();
      expect(XvgRasterCache.tileCount, 4);
      expect(XvgRasterCache.disposedTileCount - before, 2);
    },
  );

  testWidgets(
    'lower budget evicts offscreen first and paints missing tiles with vectors',
    (tester) async {
      _screen(tester);
      await tester.pumpWidget(_scene(viewportHeight: _prefetchViewportHeight));
      final vector = await _capture(tester);
      await tester.pumpWidget(
        _scene(
          cache: _fullResolutionCache,
          viewportHeight: _prefetchViewportHeight,
        ),
      );
      await _waitTiles(tester, 6);

      XvgRasterCache.byteBudget = _fourTileBytes;
      expect(XvgRasterCache.tileCount, 4);
      await tester.pump();

      XvgRasterCache.byteBudget = _topTileBytes;
      await tester.pump();
      await _waitTiles(tester, 1);
      expect(
        XvgRasterCache.bytesUsed,
        inInclusiveRange(_sideTileBytes, _topTileBytes),
      );
      _expectRoundingOrEdges(await _capture(tester), vector);

      XvgRasterCache.byteBudget = 0;
      await tester.pump();
      expect(XvgRasterCache.bytesUsed, 0);
      expect(await _capture(tester), vector);
    },
  );

  testWidgets('theme, size and resolution changes replace the static grid', (
    tester,
  ) async {
    _screen(tester);
    await tester.pumpWidget(
      _scene(source: _flat, cache: _fullResolutionCache, dispatch: true),
    );
    await _waitTiles(tester, 4);
    final disposed = XvgRasterCache.disposedTileCount;

    await tester.pumpWidget(
      _scene(
        source: _flat,
        cache: _halfResolutionCache,
        dispatch: true,
        imageHeight: 1024,
        theme: const XvgTheme(currentColor: _tint),
        alignment: Alignment.topCenter,
      ),
    );
    expect(XvgRasterCache.disposedTileCount - disposed, 4);
    await _waitTiles(tester, 2);
    expect(XvgRasterCache.bytesUsed, _twoHalfTiles);
    expect(_pixel(await _capture(tester), 300, 100), _tint.toARGB32());

    final beforeFilter = XvgRasterCache.disposedTileCount;
    await tester.pumpWidget(
      _scene(
        source: _flat,
        cache: _halfResolutionCache,
        dispatch: true,
        imageHeight: 1024,
        theme: const XvgTheme(currentColor: _tint),
        alignment: Alignment.topCenter,
        filter: const ColorFilter.mode(_white, BlendMode.srcIn),
      ),
    );
    expect(XvgRasterCache.disposedTileCount, beforeFilter);
    expect(XvgRasterCache.tileCount, 2);
    expect(_pixel(await _capture(tester), 300, 100), _white.toARGB32());
  });

  testWidgets(
    'scale 1 preserves snapped vector coverage and scale 0.5 has no tile seam',
    (tester) async {
      _screen(tester);
      Widget shifted([XvgRasterCacheOverride? cache]) => Transform.translate(
        offset: const Offset(0.25, 0.375),
        child: _scene(cache: cache),
      );
      await tester.pumpWidget(shifted());
      final vector = await _capture(tester);
      await tester.pumpWidget(shifted(_fullResolutionCache));
      await _waitTiles(tester, 4);
      final full = await _capture(tester);
      final fullBytes = XvgRasterCache.bytesUsed;
      _expectRoundingOrEdges(full, vector);

      await tester.pumpWidget(shifted(_halfResolutionCache));
      await _waitTiles(tester, 4);
      expect(XvgRasterCache.bytesUsed * 4, fullBytes);
      final half = await _capture(tester);
      // A smooth opaque gradient crosses both seam axes here. Bilinear sampling
      // must not create a transparent line or a color jump beyond one 8-bit step
      // over the neighboring vector gradient.
      // 两条拼缝穿过不透明平滑渐变，采样不应产生透明线或超过一色阶的偏差。
      for (final (x, y) in [
        for (var i = 506; i < 518; i++) (i, 50),
        for (var i = 506; i < 518; i++) (100, i),
      ]) {
        final start = (y * _width + x) * _rgbaBytesPerPixel;
        for (var i = start; i < start + _rgbaBytesPerPixel; i++) {
          expect((half[i] - vector[i]).abs(), lessThanOrEqualTo(1));
        }
      }
    },
  );
}
