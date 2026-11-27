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

/// Number of bytes per raw RGBA8 pixel. / 每个原始 RGBA8 像素的字节数。
const _rgbaBytesPerPixel = 4;

/// Default full visible test width in physical pixels. / 测试使用的物理显示宽度。
const _width = 1024;

/// Test widget width at the default DPR. / 默认 DPR 下测试组件的逻辑宽度。
const double _logicalWidth = _width * 1.0;

/// The default viewport and capture height at DPR 1. / DPR 为 1 时默认视口及截图的高度。
const _defaultViewportHeight = 900;

/// Cache settings at native resolution. / 原分辨率缓存配置。
const _fullResolutionCache = XvgRasterCacheOverride.enabled;

/// White background for comparing composited output. / 用于对照合成结果的白色背景。
const _white = Color(0xffffffff);

/// A visible solid tint for testing post-cache color filtering. / 验证缓存后滤镜的实色。
const _tint = Color(0xff507c24);

/// Time between test animation frames. / 测试动画的帧间隔。
const _frameInterval = Duration(milliseconds: 16);

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

/// High-contrast translucent curve over opaque artwork. / 不透明插画上的高对比半透明曲线。
final _phaseArt = _complexArt().replaceFirst(
  '</svg>',
  '<path d="M4.4 40 Q24 15 93 87 L7 96Z" fill="#ee9" opacity=".6"/></svg>',
);

/// Places the same art under a stable or moving transform. / 在稳定或移动的变换下放置同一幅插画。
Widget _automaticArt(
  String source, {
  double extent = 100,
  double scale = 1,
  Offset offset = Offset.zero,
  ColorFilter? filter,
  XvgPixelSnap snap = XvgPixelSnap.auto,
  double opacity = 1,
}) => Align(
  alignment: Alignment.topLeft,
  child: Transform(
    transform: Matrix4.translationValues(offset.dx, offset.dy, 0)
      ..scaleByDouble(scale, scale, 1, 1),
    child: Opacity(
      opacity: opacity,
      child: StaticXvg(
        source,
        width: extent,
        height: extent,
        colorFilter: filter,
        pixelSnap: snap,
      ),
    ),
  ),
);

/// Time needed for a new raster grid to settle. / 新栅格停稳所需的时间。
const _gridSettleTime = Duration(milliseconds: 150);

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

/// Waits for a known number of tiles to be submitted. / 等待指定数量的纹理提交。
Future<void> _waitTiles(WidgetTester tester, int count) async {
  for (var frame = 0; frame < 90; frame++) {
    await tester.pump(_frameInterval);
    if (XvgRasterCache.tileCount == count && frame >= count) return;
  }
  expect(XvgRasterCache.tileCount, count);
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

/// Checks every interior pixel for missing coverage or a seam. / 逐像素检查内部有无空洞或拼缝。
void _expectSolid(Uint8List frame, Rect interior) {
  final color = _tint.toARGB32();
  var missing = 0;
  for (var y = interior.top.toInt(); y < interior.bottom; y++) {
    for (var x = interior.left.toInt(); x < interior.right; x++) {
      if (_pixel(frame, x, y) != color) missing++;
    }
  }
  expect(missing, 0);
}

/// Registers renderer and cache behavior tests. / 注册渲染器和缓存行为用例。
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await RustLib.init();
  });

  setUp(() {
    XvgRasterCache.byteBudget = XvgRasterCache.defaultByteBudget;
    debugXvgRasterCacheOverride = _fullResolutionCache;
  });
  tearDown(() => debugXvgRasterCacheOverride = null);

  group('image-space raster cache', () {
    late List<(int, int)> requests;

    setUp(() {
      debugXvgRasterCacheOverride = null;
      requests = [];
      debugXvgRasterRequest = (started, width, height) {
        if (started) requests.add((width, height));
      };
    });
    tearDown(() => debugXvgRasterRequest = null);

    testWidgets('aligned 1:1 matches vector RGBA', (tester) async {
      _screen(tester);
      debugXvgRasterCacheOverride = XvgRasterCacheOverride.disabled;
      await tester.pumpWidget(_automaticArt(_phaseArt));
      final vector = await _capture(tester);

      debugXvgRasterCacheOverride = null;
      await tester.pumpWidget(_automaticArt(_phaseArt));
      expect(requests, [(100, 100)]);
      expect(XvgRasterCache.tileCount, 1);
      expect(await _capture(tester), vector);
    });

    testWidgets('settled fractional phase matches vector pixels', (
      tester,
    ) async {
      _screen(tester);
      const offset = Offset(0.25, 0.375);
      const zoom = 4.0;
      const zoomOffset = Offset(0.375, 0.25);
      debugXvgRasterCacheOverride = XvgRasterCacheOverride.disabled;
      await tester.pumpWidget(_automaticArt(_phaseArt, offset: offset));
      final vector1 = await _capture(tester);
      await tester.pumpWidget(
        _automaticArt(_phaseArt, offset: zoomOffset, scale: zoom),
      );
      final vector4 = await _capture(tester);

      debugXvgRasterCacheOverride = null;
      await tester.pumpWidget(_automaticArt(_phaseArt, offset: offset));
      expect(requests, [(101, 101)]);
      expect(await _capture(tester), vector1);
      await tester.pumpWidget(
        _automaticArt(_phaseArt, offset: zoomOffset, scale: zoom),
      );
      expect(requests, hasLength(1));
      await tester.pump(_gridSettleTime);
      expect(requests, [(101, 101), (401, 401)]);
      expect(await _capture(tester), vector4);
    });

    testWidgets('fractional translation and opacity reuse the same image', (
      tester,
    ) async {
      _screen(tester);
      final source = _complexArt();
      await tester.pumpWidget(_automaticArt(source));
      final disposed = XvgRasterCache.disposedTileCount;
      for (final dx in _fractionalScrollOffsets) {
        await tester.pumpWidget(
          _automaticArt(source, offset: Offset(dx, 10), opacity: 0.5 + dx / 20),
          duration: _frameInterval,
        );
      }
      expect(requests, [(100, 100)]);
      expect(XvgRasterCache.disposedTileCount, disposed);
      expect(_pixel(await _capture(tester), 40, 40) >>> 24, greaterThan(190));
    });

    testWidgets('retains old pixels until both zoom directions settle', (
      tester,
    ) async {
      _screen(tester);
      tester.view.devicePixelRatio = 2;
      final source = _complexArt();
      await tester.pumpWidget(_automaticArt(source));
      await tester.pumpWidget(_automaticArt(source, scale: 1.25));
      await tester.pump(const Duration(milliseconds: 160));
      expect(requests, [(200, 200)]);

      await tester.pumpWidget(_automaticArt(source, scale: 1.6));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(_automaticArt(source, scale: 2));
      await tester.pump(const Duration(milliseconds: 149));
      expect(requests, [(200, 200)]);
      expect(XvgRasterCache.bytesUsed, 200 * 200 * 4);
      expect(_pixel(await _capture(tester), 320, 320), _tint.toARGB32());
      await tester.pump(const Duration(milliseconds: 1));
      expect(requests, [(200, 200), (400, 400)]);
      expect(XvgRasterCache.bytesUsed, 400 * 400 * 4);

      await tester.pumpWidget(_automaticArt(source, scale: 1.6));
      await tester.pump(const Duration(milliseconds: 160));
      expect(requests, hasLength(2));
      await tester.pumpWidget(_automaticArt(source));
      expect(XvgRasterCache.bytesUsed, 400 * 400 * 4);
      await tester.pump(const Duration(milliseconds: 150));
      expect(requests, [(200, 200), (400, 400), (200, 200)]);
      expect(XvgRasterCache.bytesUsed, 200 * 200 * 4);
    });

    testWidgets('layout and DPR changes keep a preview then replace it', (
      tester,
    ) async {
      _screen(tester);
      final source = _complexArt();
      await tester.pumpWidget(_automaticArt(source));
      await tester.pumpWidget(_automaticArt(source, extent: 150));
      expect(requests, [(100, 100)]);
      expect(_pixel(await _capture(tester), 130, 130), _tint.toARGB32());
      await tester.pump(const Duration(milliseconds: 150));
      expect(requests.last, (150, 150));
      tester.view.devicePixelRatio = 2;
      await tester.pump();
      expect(XvgRasterCache.bytesUsed, 150 * 150 * 4);
      await tester.pump(const Duration(milliseconds: 150));
      expect(requests, [(100, 100), (150, 150), (300, 300)]);
    });

    testWidgets('keeps an existing image under an unsupported matrix', (
      tester,
    ) async {
      _screen(tester);
      final artwork = _automaticArt(_complexArt());
      await tester.pumpWidget(Transform.rotate(angle: 0, child: artwork));
      await tester.pumpWidget(Transform.rotate(angle: .2, child: artwork));
      await tester.pump(const Duration(seconds: 1));
      expect(requests, [(100, 100)]);
      expect(XvgRasterCache.tileCount, 1);
    });

    testWidgets('large images retain tiles across fractional scroll and back', (
      tester,
    ) async {
      _screen(tester);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final source = _complexArt().replaceFirst(
        'width="100" height="100"',
        'width="100" height="5000" viewBox="0 0 100 100" preserveAspectRatio="none"',
      );
      await tester.pumpWidget(
        _scene(
          cache: null,
          scroll: controller,
          source: source,
          imageHeight: 5000,
        ),
      );
      expect(requests, hasLength(1));
      await tester.pumpAndSettle();
      final initial = requests.length;
      expect(initial, 4);
      controller.jumpTo(14.25);
      await tester.pumpAndSettle();
      expect(requests, hasLength(initial));
      controller.jumpTo(1100.25);
      await tester.pumpAndSettle();
      final afterScroll = requests.length;
      expect(afterScroll, greaterThan(initial));
      controller.jumpTo(0);
      await tester.pumpAndSettle();
      expect(requests, hasLength(afterScroll));
    });

    testWidgets('visible-only tiles leave no holes during zoom and scroll', (
      tester,
    ) async {
      _screen(tester);
      final source = _complexArt();
      Widget viewport(double scale, Offset offset) => Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 360,
          height: 300,
          child: ClipRect(
            child: _automaticArt(
              source,
              extent: 300,
              scale: scale,
              offset: offset,
            ),
          ),
        ),
      );

      await tester.pumpWidget(viewport(1, Offset.zero));
      expect(requests, [(300, 300)]);
      const initialPan = Offset(-15.25, -28.5);
      await tester.pumpWidget(viewport(4, initialPan));
      const interior = Rect.fromLTWH(2, 2, 356, 296);
      _expectSolid(await _capture(tester), interior);
      await tester.pump(_gridSettleTime);
      expect(requests, hasLength(2));
      _expectSolid(await _capture(tester), interior);
      await tester.pumpAndSettle();
      expect(requests, hasLength(5));

      const distantPan = Offset(-560.375, -624.25);
      await tester.pumpWidget(viewport(4, distantPan));
      _expectSolid(await _capture(tester), interior);
      await tester.pumpAndSettle();

      // Discard the overview and offscreen tiles, then expose uncached content.
      // 清掉预览及屏外块，再露出尚未缓存的区域。
      await _sendMemoryPressure(tester);
      await tester.pumpWidget(viewport(4, initialPan));
      expect(debugXvgRasterTilesReady, isFalse);
      _expectSolid(await _capture(tester), interior);
      await tester.pumpAndSettle();
      expect(debugXvgRasterTilesReady, isTrue);
    });

    testWidgets('icons and unaffordable visible tiles stay vector', (
      tester,
    ) async {
      _screen(tester);
      await tester.pumpWidget(_automaticArt(_flat));
      expect(find.byType(XvgRasterPaint), findsNothing);
      XvgRasterCache.byteBudget = 4096;
      await tester.pumpWidget(_automaticArt(_complexArt()));
      await tester.pumpAndSettle();
      expect(requests, isEmpty);
      expect(XvgRasterCache.tileCount, 0);
      expect(_pixel(await _capture(tester), 20, 20), _tint.toARGB32());
    });
  });

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
    expect(debugXvgRasterTilesReady, isFalse);
    expect(_pixel(await _capture(tester), 100, 100), _white.toARGB32());

    scroll.jumpTo(0);
    await tester.pump();
    expect(tester.element(artwork), same(original));
    expect(_pixel(await _capture(tester), 100, 100), _tint.toARGB32());
  });

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
    final pictures = <ui.Picture>[];
    final previous = ui.Picture.onCreate;
    ui.Picture.onCreate = (picture) {
      previous?.call(picture);
      pictures.add(picture);
    };
    addTearDown(() => ui.Picture.onCreate = previous);
    await tester.pumpWidget(_automaticArt(_complexArt()));
    final first = pictures.last;
    final root = binding.renderViews.single.debugLayer!;
    final scene = root.buildScene(ui.SceneBuilder());
    addTearDown(scene.dispose);
    expect(first.debugDisposed, isFalse);
    final creations = pictures.length;

    root.buildScene(ui.SceneBuilder()).dispose();
    expect(pictures, hasLength(creations));
    expect(first.debugDisposed, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(first.debugDisposed, isTrue);
    final bytes = (await tester.runAsync(() => _readScene(scene)))!;
    expect(_pixel(bytes, 30, 30), _tint.toARGB32());
  });

  testWidgets('complete small artwork composes a whole texture', (
    tester,
  ) async {
    _screen(tester);
    await tester.pumpWidget(_zoomed(_small(color: _tint), 1));
    await _waitTiles(tester, 1);
    expect(debugXvgRasterTilesReady, isTrue);
    expect(_pixel(await _capture(tester), 100, 100), _tint.toARGB32());
  });

  testWidgets('a whole texture preserves subpixel overflow clipping', (
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

  testWidgets('unknown bounds use the full viewport', (tester) async {
    _screen(tester);
    const source =
        '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="400"/>';
    await tester.pumpWidget(_zoomed(const StaticXvg(source), 1));
    await _waitTiles(tester, 1);
    expect(debugXvgRasterTilesReady, isTrue);
  });

  testWidgets('a whole texture preserves viewport clipping', (tester) async {
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
    await _waitTiles(tester, 1);
    expect(debugXvgRasterTilesReady, isTrue);
    expect(await _capture(tester), vector);
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
    await _waitTiles(tester, 1);
    final cached = await _capture(tester);
    expect(_pixel(vector, 250, 200), isNot(0xff14ab3e));
    expect(cached, vector);
  });

  testWidgets('automatic sparse texture matches filtered vector pixels', (
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
      await _waitTiles(tester, 1);
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
      expect(debugXvgRasterTilesReady, isTrue);
      expect(XvgRasterCache.tileCount, 1);
      expect(XvgRasterCache.disposedTileCount, released);
      await tester.pump(_gridSettleTime);
      expect(XvgRasterCache.disposedTileCount, released + 1);
      await _waitTiles(tester, 1);
      expect(_pixel(await _capture(tester), 650, 650), _secondColor.toARGB32());
    },
  );

  testWidgets(
    'the shared budget reclaims an offstage owner before allocating',
    (tester) async {
      _screen(tester);
      const textureExtent = _smallExtent;
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
    await _waitTiles(tester, 16);
    final full = await _capture(tester);
    // A blur is continuous inside this fixture. The two seams allow one
    // 8-bit rounding step. / 模糊连续穿过两条拼缝，只容许一色阶的舍入。
    var worst = 0;
    const seam = XvgRasterCache.tileSize * 2;
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
    await _replay(tester, 2);
    expect(XvgRasterCache.tileCount, 0);
    expect(XvgRasterCache.bytesUsed, 0);
  });

  group('automatic cache', () {
    setUp(() => debugXvgRasterCacheOverride = null);

    testWidgets('admits a complex illustration in its first composition', (
      tester,
    ) async {
      _screen(tester);
      await tester.pumpWidget(
        _automaticArt(_complexArt(), offset: const Offset(.25, .375)),
      );
      expect(XvgRasterCache.tileCount, 1);
      expect(debugXvgRasterTilesReady, isTrue);
      expect(find.byType(PixelSnapBoundary), findsNothing);
      final bytes = XvgRasterCache.bytesUsed;
      await tester.pumpWidget(
        _automaticArt(_complexArt(), offset: const Offset(5.375, 9.25)),
      );
      expect(XvgRasterCache.bytesUsed, bytes);
      expect(find.byType(PixelSnapBoundary), findsNothing);
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
      await _waitTiles(tester, 1);
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
            ),
          ),
        );
        await _replay(tester, 2);
        expect(XvgRasterCache.tileCount, 1);
        expect(debugXvgRasterTilesReady, isTrue);
        expect(_pixel(await _capture(tester), 10, 10), _tint.toARGB32());
      },
    );

    testWidgets(
      'releases the composite when mounted artwork leaves the scene',
      (tester) async {
        _screen(tester);
        final pictures = <ui.Picture>[];
        final previous = ui.Picture.onCreate;
        ui.Picture.onCreate = (picture) {
          previous?.call(picture);
          pictures.add(picture);
        };
        addTearDown(() => ui.Picture.onCreate = previous);
        final source = _complexArt();
        Widget artwork({required bool offstage}) =>
            Offstage(offstage: offstage, child: _automaticArt(source));
        await tester.pumpWidget(artwork(offstage: false));
        expect(XvgRasterCache.tileCount, 1);

        final composite = pictures.last;
        expect(composite.debugDisposed, isFalse);
        await tester.pumpWidget(artwork(offstage: true));
        expect(find.byType(StaticXvg, skipOffstage: false), findsOneWidget);
        expect(composite.debugDisposed, isTrue);
        expect(debugXvgRasterTilesReady, isFalse);
        expect(XvgRasterCache.tileCount, 1);

        await tester.pumpWidget(artwork(offstage: false));
        expect(XvgRasterCache.tileCount, 1);
        expect(debugXvgRasterTilesReady, isTrue);
      },
    );
  });

  testWidgets('memory pressure evicts visited offscreen tiles', (tester) async {
    _screen(tester);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _scene(cache: _fullResolutionCache, scroll: scroll),
    );
    await _waitTiles(tester, 16);
    scroll.jumpTo(1024);
    await tester.pumpAndSettle();
    expect(XvgRasterCache.tileCount, 32);
    final before = XvgRasterCache.disposedTileCount;

    await _sendMemoryPressure(tester);
    expect(XvgRasterCache.tileCount, 16);
    expect(XvgRasterCache.disposedTileCount - before, 16);
    expect(debugXvgRasterTilesReady, isTrue);
  });

  testWidgets('lower budget evicts offscreen first and falls back to vectors', (
    tester,
  ) async {
    _screen(tester);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(_scene(source: _flat, scroll: scroll));
    scroll.jumpTo(1024);
    await tester.pump();
    final vector = await _capture(tester);
    await tester.pumpWidget(
      _scene(source: _flat, cache: _fullResolutionCache, scroll: scroll),
    );
    await _waitTiles(tester, 16);
    final visibleBytes = XvgRasterCache.bytesUsed;
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    scroll.jumpTo(1024);
    await tester.pumpAndSettle();
    expect(XvgRasterCache.tileCount, 32);

    XvgRasterCache.byteBudget = visibleBytes;
    await tester.pump();
    expect(XvgRasterCache.tileCount, 16);
    expect(debugXvgRasterTilesReady, isTrue);
    expect(await _capture(tester), vector);

    XvgRasterCache.byteBudget = visibleBytes ~/ 4;
    await tester.pump();
    expect(debugXvgRasterTilesReady, isFalse);
    expect(await _capture(tester), vector);
    XvgRasterCache.byteBudget = 0;
    await tester.pump();
    expect(XvgRasterCache.bytesUsed, 0);
  });

  testWidgets('theme replaces textures and changing ColorFilter reuses them', (
    tester,
  ) async {
    _screen(tester);
    Widget artwork(Color color, ColorFilter? filter) => _scene(
      source: _flat,
      cache: _fullResolutionCache,
      dispatch: true,
      imageHeight: 1024,
      theme: XvgTheme(currentColor: color),
      filter: filter,
    );
    await tester.pumpWidget(artwork(_secondColor, null));
    await _waitTiles(tester, 1);
    final disposed = XvgRasterCache.disposedTileCount;
    await tester.pumpWidget(artwork(_tint, null));
    expect(XvgRasterCache.disposedTileCount - disposed, 1);
    await _waitTiles(tester, 1);
    expect(_pixel(await _capture(tester), 300, 100), _tint.toARGB32());

    final beforeFilter = XvgRasterCache.disposedTileCount;
    await tester.pumpWidget(
      artwork(_tint, const ColorFilter.mode(_white, BlendMode.srcIn)),
    );
    expect(XvgRasterCache.disposedTileCount, beforeFilter);
    expect(XvgRasterCache.tileCount, 1);
    expect(_pixel(await _capture(tester), 300, 100), _white.toARGB32());
  });
}
