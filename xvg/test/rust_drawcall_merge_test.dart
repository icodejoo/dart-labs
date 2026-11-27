import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/rust/api/svg.dart';
import 'package:xvg/src/rust_static_svg.dart';
import 'package:xvg/src/xvg_raster_cache.dart';
import 'package:xvg/xvg.dart' show RustLib;

/// 夹具和像素对照共用的正方形边长。
const _fixtureEdge = 128;

/// 用原生路径门槛构造两条可合并的填充轮廓。
String _mergeFixture({bool separate = false}) =>
    '''
<svg xmlns="http://www.w3.org/2000/svg" width="$_fixtureEdge" height="$_fixtureEdge">
  <defs><clipPath id="c"><rect x="-40" y="-40" width="290" height="290"/></clipPath></defs>
  <path d="M2.1 3.2H36.4V16.5H2.1Z"/>
  ${separate ? '<g clip-path="url(#c)">' : ''}
  <path d="M18.2 28.3V64.1H61.4V28.3Z"/>
  ${separate ? '</g>' : ''}
  ${'<rect x="110" y="110" width="4" height="4" fill="#8b4315"/> ' * (xvgRasterMinPaths - 2)}
</svg>''';

/// 读取预乘 RGBA 字节并释放图像句柄。
Future<Uint8List> _pixels(RustSvgPictureInfo info) async {
  final image = await rasterizeSvgPicture(
    info,
    width: _fixtureEdge,
    height: _fixtureEdge,
  );
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    image.dispose();
  }
}

/// 验证自动判定、强制开关和缓存一致性。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cache = RustXvgPictureCache.instance;
  final source = _mergeFixture();
  setUpAll(RustLib.init);
  tearDown(() {
    debugPathMergeOverride = null;
    debugStaticSvgAsyncParseThreshold = null;
    cache.clear();
  });

  test('compares corresponding RGBA channels across every tile row', () {
    const edge = 2;
    const top = [3, 5, 7, 99, 11, 13, 17, 80];
    const bottom = [23, 29, 31, 76, 37, 41, 43, 84];
    final atlas = ByteData.sublistView(
      Uint8List.fromList([0, ...top, ...top, ...bottom, ...bottom]),
      1,
    );
    expect(debugComparePathMergeTiles(atlas, edge, edge), 0);
    atlas.setUint8(8, 4);
    expect(debugComparePathMergeTiles(atlas, edge, edge), 1);
    atlas
      ..setUint8(7, 84)
      ..setUint8(29, 10);
    expect(debugComparePathMergeTiles(atlas, edge, edge), 31);
    atlas.setUint8(31, 196);
    expect(debugComparePathMergeTiles(atlas, edge, edge), 112);
  });

  test('Windows skips even with shader filters supported', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(debugShouldProbePathMerge(shaderFilterSupported: true), isFalse);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(debugShouldProbePathMerge(shaderFilterSupported: true), isTrue);
    expect(debugShouldProbePathMerge(shaderFilterSupported: false), isFalse);
  });

  testWidgets('waits for a fresh 200 ms of quiet after a frame', (
    tester,
  ) async {
    final binding = tester.binding;
    final origin = binding.clock.now();
    final calls = <(bool, SchedulerPhase)>[];
    final result = debugRunPathMergeWhenIdle(binding, (timedOut) async {
      calls.add((timedOut, binding.schedulerPhase));
      return 7;
    }, now: () => binding.clock.now().difference(origin));
    await tester.idle();
    expect(calls, isEmpty);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 123));
    binding.scheduleFrame();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 226));
    expect(calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(await result, 7);
    await tester.pump(const Duration(seconds: 3));
    expect(calls, [(false, SchedulerPhase.idle)]);
    expect(binding.hasScheduledFrame, isFalse);
  });

  testWidgets('starts once at the deadline despite a live ticker', (
    tester,
  ) async {
    final binding = tester.binding;
    final origin = binding.clock.now();
    final calls = <(bool, SchedulerPhase, int)>[];
    final ticker = Ticker((_) {})..start();
    addTearDown(ticker.dispose);
    final result = debugRunPathMergeWhenIdle(binding, (timedOut) async {
      calls.add((
        timedOut,
        binding.schedulerPhase,
        binding.transientCallbackCount,
      ));
    }, now: () => binding.clock.now().difference(origin));
    await tester.pump();
    for (var i = 0; i < 150; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (i < 149) expect(calls, isEmpty);
    }
    await result;
    await tester.pump(const Duration(seconds: 1));
    expect(calls, [(true, SchedulerPhase.idle, 1)]);
  });

  test(
    'flutter_tester uses independent draws and skips GPU readback',
    () async {
      expect(ui.ImageFilter.isShaderFilterSupported, isFalse);
      final picture = cache.getOrRender(source);
      addTearDown(picture.picture.dispose);
      expect(picture.pathCount, xvgRasterMinPaths);
      final firstProbe = debugPathMergeProbeResult;
      final probe = await firstProbe;
      expect(probe?.allowed, isFalse);
      expect(probe?.elapsed, Duration.zero);
      expect(probe?.maxDelta, isNull);
      expect(probe?.startedUs, isNull);
      cache.clear();
      final next = await cache.getOrRenderAsync(_mergeFixture(separate: true));
      addTearDown(next.picture.dispose);
      expect(next.pathCount, xvgRasterMinPaths);
      expect(debugPathMergeProbeResult, same(firstProbe));
    },
  );

  test(
    'the sync renderer preserves the cached picture across a pass',
    () async {
      debugPathMergeOverride = false;
      final first = cache.getOrRender(source);
      addTearDown(first.picture.dispose);
      expect(first.pathCount, xvgRasterMinPaths);

      debugPathMergeOverride = true;
      expect(cache.peek(source), same(first));
      expect(cache.getOrRender(source), same(first));
      expect(await cache.getOrRenderAsync(source), same(first));

      cache.clear();
      final merged = cache.getOrRender(source);
      addTearDown(merged.picture.dispose);
      expect(merged.pathCount, xvgRasterMinPaths - 1);
    },
  );

  test(
    'worker uses the requested policy and off pixels match byte for byte',
    () async {
      debugStaticSvgAsyncParseThreshold = 0;
      debugPathMergeOverride = false;
      final pending = cache.getOrRenderAsync(source);
      debugPathMergeOverride = true;
      expect(cache.getOrRenderAsync(source), same(pending));
      final separate = await pending;
      final reference = await cache.getOrRenderAsync(
        _mergeFixture(separate: true),
      );
      addTearDown(separate.picture.dispose);
      addTearDown(reference.picture.dispose);
      expect(separate.pathCount, xvgRasterMinPaths);
      expect(reference.pathCount, xvgRasterMinPaths);
      final pixels = await _pixels(reference);
      expect(pixels.any((value) => value != 0), isTrue);
      expect(await _pixels(separate), orderedEquals(pixels));

      cache.clear();
      final merged = await cache.getOrRenderAsync(source);
      addTearDown(merged.picture.dispose);
      expect(merged.pathCount, xvgRasterMinPaths - 1);
      expect(parseSvg(data: source).paths, hasLength(xvgRasterMinPaths));
    },
  );
}
