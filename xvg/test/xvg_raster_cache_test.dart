import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:xvg/src/pixel_snap_layer.dart';
import 'package:xvg/src/xvg_raster_cache.dart' show debugXvgRasterTilesReady;
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
const _fullResolutionCache = XvgRasterCache();

/// Cache settings at half resolution. / 半分辨率缓存配置。
const _halfResolutionCache = XvgRasterCache(resolutionScale: 0.5);

/// White background for comparing composited output. / 用于对照合成结果的白色背景。
const _white = Color(0xffffffff);

/// A visible solid tint for testing post-cache color filtering. / 验证缓存后滤镜的实色。
const _tint = Color(0xff507c24);

/// Time between test animation frames. / 测试动画的帧间隔。
const _frameInterval = Duration(milliseconds: 16);

/// Successive fractional scroll positions that stay in the same tile rows.
/// 保持在同一分块行内的连续小数滚动位置。
const _fractionalScrollOffsets = [1.25, 2.5, 3.75, 5.25, 6.5, 7.75];

/// Paints a known-width SVG under a clipped, optionally scrolling viewport.
/// 在可裁剪、可滚动视口内绘制已知宽度的 SVG。
Widget _scene({
  XvgRasterCache? cache,
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
  final child = dispatch
      ? Xvg.string(
          source,
          width: _logicalWidth,
          height: imageHeight,
          alignment: alignment,
          colorFilter: filter,
          theme: theme,
          rasterCache: cache,
          pixelSnap: pixelSnap,
        )
      : StaticXvg(
          source,
          width: _logicalWidth,
          height: imageHeight,
          alignment: alignment,
          colorFilter: filter,
          theme: theme,
          rasterCache: cache,
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
  rasterCache: _fullResolutionCache,
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

/// Captures the physical root scene, including PixelSnapBoundary and clipping.
/// 捕获物理像素根场景，包含像素对齐边界和裁剪。
Future<Uint8List> _capture(WidgetTester tester) async {
  return (await tester.runAsync(() async {
    final layer = tester.binding.renderViews.single.debugLayer!;
    final scene = layer.buildScene(ui.SceneBuilder());
    final image = await scene.toImage(_width, _defaultViewportHeight);
    try {
      return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List();
    } finally {
      image.dispose();
      scene.dispose();
    }
  }))!;
}

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
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await RustLib.init();
  });

  setUp(() => XvgRasterCache.byteBudget = XvgRasterCache.defaultByteBudget);

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

  testWidgets('changing only the source and then DPR invalidates prior tiles', (
    tester,
  ) async {
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
    expect(XvgRasterCache.disposedTileCount, released + 1);
    await _waitTiles(tester, 4);
    expect(_pixel(await _capture(tester), 650, 650), _secondColor.toARGB32());
  });

  testWidgets('scale animation waits for a stable grid before rasterizing', (
    tester,
  ) async {
    _screen(tester);
    final artwork = _small(color: _tint);
    Widget zoomed(double scale) => Align(
      alignment: Alignment.topLeft,
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.topLeft,
        child: artwork,
      ),
    );

    await tester.pumpWidget(zoomed(1));
    await _waitTiles(tester, 1);
    final bytes = XvgRasterCache.bytesUsed;
    final disposed = XvgRasterCache.disposedTileCount;

    for (final scale in [1.04, 1.08, 1.0, 1.12, 1.16, 1.20, 1.24]) {
      await tester.pumpWidget(zoomed(scale), duration: _frameInterval);
      expect(XvgRasterCache.tileCount, 0, reason: 'scale $scale');
      expect(XvgRasterCache.disposedTileCount, disposed + 1);
    }

    await tester.pump(_frameInterval * 3);
    expect(XvgRasterCache.tileCount, 0);
    await _waitTiles(tester, 1);
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

  testWidgets('Xvg ignores cache settings on the animated path', (
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

  testWidgets('default leaves the render tree and texture cache alone', (
    tester,
  ) async {
    _screen(tester);
    await tester.pumpWidget(_scene());
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(StaticXvg),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
    expect(XvgRasterCache.tileCount, 0);
    expect(XvgRasterCache.bytesUsed, 0);
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

    await tester.pump(const Duration(milliseconds: 80));
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

      final message = tester.binding.defaultBinaryMessenger
          .handlePlatformMessage(
            'flutter/system',
            const JSONMessageCodec().encodeMessage(<String, String>{
              'type': 'memoryPressure',
            }),
            (_) {},
          );
      await message;
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

  testWidgets(
    'Xvg forwards the cache, then changes in theme, size and scale replace it',
    (tester) async {
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
    },
  );

  testWidgets(
    'scale 1 preserves snapped vector coverage and scale 0.5 has no tile seam',
    (tester) async {
      _screen(tester);
      Widget shifted([XvgRasterCache? cache]) => Transform.translate(
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
