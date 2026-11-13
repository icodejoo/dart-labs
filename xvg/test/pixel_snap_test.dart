// ignore_for_file: avoid_print

// flutter test test/pixel_snap_test.dart --concurrency=1
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/pixel_snap_layer.dart';
import 'package:xvg/xvg.dart';

// Stable raster/benchmark dimensions. / 固定光栅及基准尺寸。
const _surfaceExtent = 200;
const _iconExtent = 93.6;
const _itemCount = 130;
const _framesPerBatch = 120;
const _batchCount = 9;
const _epsilon = 1e-8;
const _white = Color(0xffffffff);

// Black cutouts touch viewport edges; the white mask extends beyond them.
// 黑色挖空与 viewport 的左右边重合，白色 mask 伸出 viewport。
const _svg = '''<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
<defs><mask id="m" x="-10%" y="-10%" width="120%" height="120%" maskUnits="userSpaceOnUse">
<rect x="-1" y="-1" width="26" height="26" fill="white"/>
<path d="M0 0H6V24H0Z M18 0H24V24H18Z" fill="black"/>
</mask></defs><rect width="24" height="24" fill="black" mask="url(#m)"/></svg>''';
// Real timeline, paused at t=0. / 真正含时间线，autoplay=false 固定采样 t=0。
final _animatedSvg = _svg.replaceFirst(
  'mask="url(#m)"/>',
  'mask="url(#m)"><animate attributeName="opacity" from="1" to="0.5" '
      'dur="1s" repeatCount="indefinite"/></rect>',
);
const _plain =
    '<svg width="24" height="24"><rect width="24" height="24"/></svg>';

Widget _icon(bool animated, XvgPixelSnap mode, {String source = _svg}) =>
    animated
    ? AnimatedXvg.string(
        source == _svg ? _animatedSvg : source,
        width: _iconExtent,
        height: _iconExtent,
        autoplay: false,
        pixelSnap: mode,
      )
    : StaticXvg(
        source,
        width: _iconExtent,
        height: _iconExtent,
        pixelSnap: mode,
      );

void _view(WidgetTester tester, {double dpr = 1}) {
  tester.view.devicePixelRatio = dpr;
  tester.view.physicalSize = const Size(
    _surfaceExtent * 1.0,
    _surfaceExtent * 1.0,
  );
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Widget _scene(Widget icon, {bool translate = false, bool rotate = false}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: _white,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: translate ? 0 : 13.2,
              top: translate ? 0 : 13.2,
              child: rotate
                  ? Transform.rotate(angle: 0.17, child: icon)
                  : translate
                  ? Transform.translate(
                      offset: const Offset(13.2, 13.2),
                      child: icon,
                    )
                  : icon,
            ),
          ],
        ),
      ),
    );

// Capture the root DPR and all ancestors, rather than a boundary image.
// 必须包含根 TransformLayer 的 DPR 及所有祖先；不能 boundary.toImage。
Future<Uint8List> _pixels(WidgetTester tester) async {
  return (await tester.runAsync(() async {
    final root = tester.binding.renderViews.single.debugLayer!;
    expect(root, isA<TransformLayer>());
    final scene = root.buildScene(ui.SceneBuilder());
    final image = await scene.toImage(_surfaceExtent, _surfaceExtent);
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

// Sample the two cutout columns, excluding corners; expect white background.
// 只采样左右挖空带，避开顶部/底部角点；阈值为一个 8bit 色阶。
int _leaks(Uint8List pixels, Rect bounds) {
  var count = 0;
  for (var y = bounds.top.ceil(); y < bounds.bottom.floor(); y++) {
    for (final x in [bounds.left.floor(), bounds.right.floor()]) {
      final i = (y * _surfaceExtent + x) * 4;
      if (pixels[i] != 255 || pixels[i + 1] != 255 || pixels[i + 2] != 255) {
        count++;
      }
    }
  }
  return count;
}

List<Layer> _layers(WidgetTester tester) =>
    tester.binding.renderViews.single.debugLayer!.depthFirstIterateChildren();

class _PaintCounter extends CustomPainter {
  _PaintCounter(this.delegate) : super(repaint: delegate);
  final CustomPainter delegate;
  int count = 0;
  @override
  void paint(Canvas canvas, Size size) {
    count++;
    delegate.paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _PaintCounter oldDelegate) =>
      delegate != oldDelegate.delegate;
}

Future<List<_PaintCounter>> _countPaints(WidgetTester tester) async {
  final result = <_PaintCounter>[];
  for (final element in find.byType(CustomPaint).evaluate()) {
    final render = element.renderObject! as RenderCustomPaint;
    if (render.painter == null) continue;
    final counter = _PaintCounter(render.painter!);
    render.painter = counter;
    result.add(counter);
  }
  await tester.pump();
  return result;
}

// An engine-backed child proves retained composition skips its scene walk.
// 具有自身 engineLayer 的子容器，验证 addRetained 确实跳过子树 addToScene。
class _RetainProbe extends OffsetLayer {
  int calls = 0;
  @override
  void addToScene(ui.SceneBuilder builder) {
    calls++;
    super.addToScene(builder);
  }
}

class _UnknownLayer extends OffsetLayer {}

class _NaiveAlwaysLayer extends OffsetLayer {
  @override
  bool get alwaysNeedsAddToScene => true;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await RustLib.init(); // 加载失败必须失败，不能 skip。
  });

  for (final animated in [false, true]) {
    final path = animated ? 'animated' : 'static';
    testWidgets('$path root viewBox origin/scale keeps viewport snapping', (
      tester,
    ) async {
      _view(tester);
      final mapped = _svg
          .replaceFirst('viewBox="0 0 24 24"', 'viewBox="50 50 48 48"')
          .replaceFirst(
            '<defs>',
            '<g transform="translate(50 50) scale(2)"><defs>',
          )
          .replaceFirst('</svg>', '</g></svg>');
      // Capture the full scene so composition-time correction is included.
      // 读取完整场景，把合成阶段修正纳入像素比较。
      final reference = <int>[];
      for (final source in [_svg, mapped]) {
        await tester.pumpWidget(
          _scene(_icon(animated, XvgPixelSnap.auto, source: source)),
        );
        await tester.pumpAndSettle();
        final snap = _layers(tester).whereType<PixelSnapLayer>().single;
        expect(snap.viewport.left, closeTo(0, _epsilon));
        expect(snap.viewport.top, closeTo(0, _epsilon));
        expect(snap.viewport.width, closeTo(_iconExtent, _epsilon));
        expect(snap.viewport.height, closeTo(_iconExtent, _epsilon));
        final pixels = await _pixels(tester);
        expect(snap.debugDidSnap, isTrue, reason: snap.debugSkipReason);
        if (reference.isEmpty) {
          reference.addAll(pixels);
        } else {
          expect(pixels, reference);
        }
      }
    });
    for (final translate in [false, true]) {
      testWidgets(
        '$path ${translate ? 'parent translate' : 'fractional still'} 184 to zero',
        (tester) async {
          _view(tester);
          final counts = <int>[];
          for (final mode in [XvgPixelSnap.never, XvgPixelSnap.auto]) {
            await tester.pumpWidget(
              _scene(_icon(animated, mode), translate: translate),
            );
            await tester.pump();
            final pixels = await _pixels(tester);
            counts.add(
              _leaks(
                pixels,
                const Rect.fromLTWH(13.2, 13.2, _iconExtent, _iconExtent),
              ),
            );
            if (mode == XvgPixelSnap.auto) {
              final layer = _layers(tester).whereType<PixelSnapLayer>().single;
              expect(layer.debugDidSnap, isTrue, reason: layer.debugSkipReason);
            }
          }
          print('$path translate=$translate leaks=$counts');
          expect(counts.first, 184);
          expect(counts.last, 0);
        },
      );
    }

    testWidgets(
      '$path annotated ancestor and contain letterbox align painted viewport',
      (tester) async {
        _view(tester);
        for (final alignment in [Alignment.center, Alignment.bottomRight]) {
          final icon = animated
              ? AnimatedXvg.string(
                  _animatedSvg,
                  width: _iconExtent,
                  height: 145.8,
                  alignment: alignment,
                  autoplay: false,
                )
              : StaticXvg(
                  _svg,
                  width: _iconExtent,
                  height: 145.8,
                  alignment: alignment,
                );
          await tester.pumpWidget(
            _scene(
              AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle.dark,
                child: icon,
              ),
            ),
          );
          final snap = _layers(tester).whereType<PixelSnapLayer>().single;
          final original = svgPaintViewport(
            const Size(24, 24),
            const Size(_iconExtent, 145.8),
            BoxFit.contain,
            alignment,
          );
          expect(snap.viewport, original);
          final pixels = await _pixels(tester);
          expect(snap.debugDidSnap, isTrue, reason: snap.debugSkipReason);
          final world = Matrix4.identity();
          snap.applyTransform(snap.firstChild, world);
          Layer node = snap;
          while (node.parent != null) {
            final parent = node.parent!;
            final local = Matrix4.identity();
            parent.applyTransform(node, local);
            world.setFrom(local..multiply(world));
            node = parent;
          }
          final actual = MatrixUtils.transformRect(world, original);
          for (final value in [
            actual.left,
            actual.top,
            actual.width,
            actual.height,
          ]) {
            expect(value, closeTo(value.roundToDouble(), _epsilon));
          }
          expect(_leaks(pixels, actual), 0);
        }
      },
    );

    testWidgets('$path scroll recomposes without icon repaint', (tester) async {
      _view(tester);
      final leaks = <int>[];
      for (final mode in [XvgPixelSnap.never, XvgPixelSnap.auto]) {
        final controller = ScrollController();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: ColoredBox(
              color: _white,
              child: ListView(
                controller: controller,
                padding: EdgeInsets.zero,
                children: [
                  SizedBox(
                    height: 160,
                    child: Stack(
                      children: [
                        Positioned(
                          left: 13.2,
                          top: 33.2,
                          child: _icon(animated, mode),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 500),
                ],
              ),
            ),
          ),
        );
        final counters = await _countPaints(tester);
        expect(counters, hasLength(1));
        final before = counters.single.count;
        final pictures = _layers(tester)
            .whereType<PictureLayer>()
            .map((l) => l.picture)
            .toList();
        controller.jumpTo(20.6);
        await tester.pump();
        leaks.add(
          _leaks(
            await _pixels(tester),
            const Rect.fromLTWH(13.2, 12.6, _iconExtent, _iconExtent),
          ),
        );
        expect(counters.single.count, before);
        expect(
          _layers(tester)
              .whereType<PictureLayer>()
              .map((l) => l.picture)
              .toList(),
          pictures,
        );
        if (mode == XvgPixelSnap.auto) {
          final snap = _layers(tester).whereType<PixelSnapLayer>().single;
          expect(snap.debugDidSnap, isTrue, reason: snap.debugSkipReason);
          expect(snap.debugCorrection.storage[13], closeTo(0.4, _epsilon));
        }
        print(
          '$path scroll mode=$mode paint=$before->${counters.single.count}',
        );
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
      print('$path scroll leaks=$leaks');
      expect(leaks.first, 186);
      expect(leaks.last, 0);
    });

    testWidgets('$path rotated parent falls back byte-identically', (
      tester,
    ) async {
      _view(tester);
      await tester.pumpWidget(
        _scene(_icon(animated, XvgPixelSnap.never), rotate: true),
      );
      final off = await _pixels(tester);
      await tester.pumpWidget(
        _scene(_icon(animated, XvgPixelSnap.always), rotate: true),
      );
      final on = await _pixels(tester);
      final snap = _layers(tester).whereType<PixelSnapLayer>().single;
      expect(snap.debugDidSnap, isFalse);
      expect(snap.debugSkipReason, 'non-axis:TransformLayer');
      expect(on, orderedEquals(off));
      print('$path rotation differing bytes=0 / ${on.length}');
    });

    testWidgets('$path auto always never gating', (tester) async {
      _view(tester);
      for (final source in [
        _plain,
        _svg,
        '<svg width="24" height="24"><defs><clipPath id="c"><rect width="24" height="24"/></clipPath></defs><rect width="24" height="24" clip-path="url(#c)"/></svg>',
      ]) {
        for (final mode in XvgPixelSnap.values) {
          await tester.pumpWidget(
            _scene(_icon(animated, mode, source: source)),
          );
          final enabled =
              mode == XvgPixelSnap.always ||
              (mode == XvgPixelSnap.auto && source != _plain);
          expect(
            _layers(tester).whereType<PixelSnapLayer>().length,
            enabled ? 1 : 0,
          );
          expect(
            find.byType(PixelSnapBoundary),
            enabled ? findsOneWidget : findsNothing,
          );
        }
      }
    });
  }

  testWidgets('root DPR participates in physical pixel snapping', (
    tester,
  ) async {
    print('flutter_test initial DPR=${tester.view.devicePixelRatio}');
    _view(tester, dpr: 3);
    final counts = <int>[];
    for (final mode in [XvgPixelSnap.never, XvgPixelSnap.auto]) {
      await tester.pumpWidget(
        Transform.scale(
          scale: 1 / 3,
          alignment: Alignment.topLeft,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            maxWidth: _surfaceExtent.toDouble(),
            maxHeight: _surfaceExtent.toDouble(),
            child: SizedBox(
              width: _surfaceExtent.toDouble(),
              height: _surfaceExtent.toDouble(),
              child: _scene(_icon(false, mode)),
            ),
          ),
        ),
      );
      counts.add(
        _leaks(
          await _pixels(tester),
          const Rect.fromLTWH(13.2, 13.2, _iconExtent, _iconExtent),
        ),
      );
    }
    print('DPR=3 with parent scale=1/3 leaks=$counts');
    expect(counts, [184, 0]);
  });

  test('SDK API contracts and alwaysNeedsAddToScene offset assertion', () {
    final naive = _NaiveAlwaysLayer();
    expect(() => naive.offset = const Offset(1.2, 2.3), throwsAssertionError);
    naive.dispose();
    final render = RenderPixelSnapBoundary();
    final first = render.updateCompositedLayer(oldLayer: null);
    expect(first, isA<PixelSnapLayer>());
    expect(render.updateCompositedLayer(oldLayer: first), same(first));
    expect(() => first.offset = const Offset(1.2, 2.3), returnsNormally);
    first.dispose();
    render.dispose();
    print(
      'SDK custom OffsetLayer reuse=true; naive setter asserts; custom setter passes',
    );
  });

  test('layer chain transforms, conservative fallback and retained children', () {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 24, 24), Paint());
    final picture = recorder.endRecording();
    final root = TransformLayer(transform: Matrix4.diagonal3Values(3, 3, 1));
    final handle = LayerHandle<TransformLayer>(root);
    final opacity = OpacityLayer(alpha: 180, offset: const Offset(1.1, 2.2));
    final filter = ImageFilterLayer(
      imageFilter: ui.ImageFilter.blur(sigmaX: 0, sigmaY: 0),
      offset: const Offset(0.1, 0.2),
    );
    final transform = TransformLayer(
      transform: Matrix4.diagonal3Values(2, 0.5, 1),
      offset: const Offset(0.2, 0.4),
    );
    final snap = PixelSnapLayer()
      ..viewport = const Rect.fromLTWH(0, 0, 15.6, 62.4)
      ..offset = const Offset(0.3, 0.6);
    final probe = _RetainProbe()
      ..append(
        PictureLayer(const Rect.fromLTWH(0, 0, 24, 24))..picture = picture,
      );
    root.append(opacity);
    opacity.append(filter);
    filter.append(transform);
    transform.append(snap);
    snap.append(probe);
    for (var i = 0; i < 10; i++) {
      opacity.offset = Offset(1.1 + i * 0.13, 2.2);
      root.buildScene(ui.SceneBuilder()).dispose();
      expect(snap.debugDidSnap, isTrue);
      final correction = snap.debugCorrection.storage;
      final originX = 3 * (opacity.offset.dx + 0.1 + 0.2 + 2 * 0.3);
      expect(
        originX + 6 * correction[12],
        closeTo(originX.roundToDouble(), _epsilon),
      );
      expect(15.6 * 6 * correction[0], closeTo(94, _epsilon));
      expect(62.4 * 1.5 * correction[5], closeTo(94, _epsilon));
    }
    expect(snap.debugSceneCount, 10);
    expect(probe.calls, 1);
    print(
      'retention snap addToScene=10 child container addToScene=${probe.calls}',
    );
    handle.layer = null;

    for (final parent in <ContainerLayer>[
      _UnknownLayer(),
      LeaderLayer(link: LayerLink()),
      FollowerLayer(link: LayerLink()),
      TransformLayer(transform: Matrix4.rotationZ(0.1)),
      TransformLayer(transform: Matrix4.skewX(0.1)),
      TransformLayer(transform: Matrix4.diagonal3Values(-1, 1, 1)),
      TransformLayer(transform: Matrix4.identity()..setEntry(3, 0, 0.01)),
    ]) {
      final layer = PixelSnapLayer()
        ..viewport = const Rect.fromLTWH(0, 0, 24, 24);
      final owner = LayerHandle<ContainerLayer>(parent);
      parent.append(layer);
      // Call the child directly: an unlinked follower can omit its subtree.
      // 单独调用子层 addToScene，避免 Follower 没有 link 时跳过整个子树。
      final builder = ui.SceneBuilder();
      layer.addToScene(builder);
      builder.build().dispose();
      expect(layer.debugDidSnap, isFalse, reason: '${parent.runtimeType}');
      print('fallback ${parent.runtimeType}: ${layer.debugSkipReason}');
      owner.layer = null;
    }
    // The layer handle releases its picture; do not dispose it twice.
    // PictureLayer.dispose 随 handle 释放 picture，不再次 dispose。
  });

  testWidgets(
    'N130 real SVG scene composition benchmark and no picture rerecord',
    (tester) async {
      _view(tester);
      final output = <String, Object>{};
      for (final mode in [
        XvgPixelSnap.never,
        XvgPixelSnap.always,
        XvgPixelSnap.auto,
      ]) {
        final key = GlobalKey();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: RepaintBoundary(
              key: key,
              child: Stack(
                clipBehavior: Clip.none,
                children: List.generate(
                  _itemCount,
                  (i) => Positioned(
                    left: (i % 13) * 10 + 0.2,
                    top: (i ~/ 13) * 10 + 0.2,
                    child: StaticXvg(
                      mode == XvgPixelSnap.auto ? _plain : _svg,
                      width: 9.6,
                      height: 9.6,
                      pixelSnap: mode,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final counters = await _countPaints(tester);
        expect(counters, hasLength(_itemCount));
        final before = counters.map((c) => c.count).toList();
        final pictureLayers = _layers(tester)
            .whereType<PictureLayer>()
            .toList();
        final pictures = pictureLayers.map((l) => l.picture).toList();
        final root = tester.binding.renderViews.single.debugLayer!;
        final moving =
            (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
                    .debugLayer!
                as OffsetLayer;
        final snaps = _layers(tester).whereType<PixelSnapLayer>().toList();
        expect(snaps.length, mode == XvgPixelSnap.always ? _itemCount : 0);
        final samples = <double>[];
        for (var batch = 0; batch < _batchCount; batch++) {
          final watch = Stopwatch()..start();
          for (var frame = 0; frame < _framesPerBatch; frame++) {
            moving.offset = Offset((frame % 11) * 0.13, (frame % 7) * 0.17);
            root.buildScene(ui.SceneBuilder()).dispose();
          }
          watch.stop();
          if (batch > 1) {
            samples.add(watch.elapsedMicroseconds / _framesPerBatch);
          }
        }
        samples.sort();
        final addSamples = <double>[];
        for (var batch = 0; batch < _batchCount; batch++) {
          var micros = 0;
          final watch = Stopwatch();
          for (var frame = 0; frame < _framesPerBatch; frame++) {
            moving.offset = Offset((frame % 11) * 0.13, (frame % 7) * 0.17);
            root.updateSubtreeNeedsAddToScene();
            final builder = ui.SceneBuilder();
            watch.reset();
            watch.start();
            root.addToScene(builder);
            watch.stop();
            micros += watch.elapsedMicroseconds;
            builder.build().dispose();
          }
          if (batch > 1) {
            addSamples.add(micros / _framesPerBatch);
          }
        }
        addSamples.sort();
        expect(counters.map((c) => c.count).toList(), before);
        expect(
          _layers(tester)
              .whereType<PictureLayer>()
              .map((l) => l.picture)
              .toList(),
          pictures,
        );
        if (snaps.isNotEmpty) {
          expect(snaps.first.debugSceneCount, greaterThanOrEqualTo(2160));
        }
        output[mode.name] = {
          'median_us_frame': samples[samples.length ~/ 2],
          'add_to_scene_median_us_frame': addSamples[addSamples.length ~/ 2],
          'add_to_scene_min_us_frame': addSamples.first,
          'add_to_scene_max_us_frame': addSamples.last,
          'min_us_frame': samples.first,
          'max_us_frame': samples.last,
          'paint_calls_before': before.reduce((a, b) => a + b),
          'paint_calls_after': counters.fold<int>(0, (a, b) => a + b.count),
          'same_picture_count': pictures.length,
          'snap_scene_calls_first': snaps.isEmpty
              ? 0
              : snaps.first.debugSceneCount,
        };
      }
      print('BENCHMARK ${jsonEncode(output)}');
    },
  );
}
