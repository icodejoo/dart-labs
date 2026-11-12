import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/pixel_snap_layer.dart';

const _viewport = Rect.fromLTWH(7.3, 11.7, 63.6, 38.4);
const _offset = Offset(13.2, 17.3);
const _epsilon = 1e-8;

class _UnknownAnnotation extends AnnotatedRegionLayer<String> {
  _UnknownAnnotation() : super('unknown');
}

class _UnknownSnap extends PixelSnapLayer {}

void _integerRect(Rect rect) {
  for (final value in [rect.left, rect.top, rect.width, rect.height]) {
    expect(value, closeTo(value.roundToDouble(), _epsilon));
  }
}

Matrix4 _transform(ContainerLayer layer, Layer child) {
  final matrix = Matrix4.identity();
  layer.applyTransform(child, matrix);
  return matrix;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('audited annotation specializations preserve rendering coordinates', () {
    final annotations = <ContainerLayer>[
      AnnotatedRegionLayer<SystemUiOverlayStyle>(
        SystemUiOverlayStyle.dark,
        offset: _offset,
      ),
      AnnotatedRegionLayer<MouseCursor>(
        SystemMouseCursors.click,
        offset: _offset,
      ),
      AnnotatedRegionLayer<Object>(Object(), offset: _offset),
      AnnotatedRegionLayer<String>('value', offset: _offset),
      AnnotatedRegionLayer<int>(1, offset: _offset),
      AnnotatedRegionLayer<double>(1, offset: _offset),
      AnnotatedRegionLayer<bool>(true, offset: _offset),
    ];
    for (final annotation in annotations) {
      final root = OffsetLayer(offset: _offset)..append(annotation);
      final handle = LayerHandle<OffsetLayer>(root);
      final snap = PixelSnapLayer()..viewport = _viewport;
      final child = ContainerLayer();
      annotation.append(snap);
      snap.append(child);
      root.buildScene(ui.SceneBuilder()).dispose();
      expect(snap.debugDidSnap, isTrue, reason: '${annotation.runtimeType}');
      final world = _transform(root, annotation)
        ..multiply(_transform(snap, child));
      _integerRect(MatrixUtils.transformRect(world, _viewport));
      handle.layer = null;
    }
  });

  test('unknown annotation and snap subclasses remain conservative', () {
    for (final parent in <ContainerLayer>[
      _UnknownAnnotation(),
      _UnknownSnap(),
    ]) {
      final handle = LayerHandle<ContainerLayer>(parent);
      final snap = PixelSnapLayer()..viewport = _viewport;
      parent.append(snap);
      parent.buildScene(ui.SceneBuilder()).dispose();
      expect(snap.debugDidSnap, isFalse);
      expect(snap.debugSkipReason, startsWith('unknown:'));
      handle.layer = null;
    }
  });

  test(
    'nested snaps use current parent matrix after composition-only movement',
    () {
      final root = TransformLayer(transform: Matrix4.diagonal3Values(3, 3, 1));
      final handle = LayerHandle<TransformLayer>(root);
      final outer = PixelSnapLayer()..viewport = _viewport;
      final inner = PixelSnapLayer()
        ..viewport = const Rect.fromLTWH(2.7, 5.2, 19.6, 23.8)
        ..offset = const Offset(0.3, 1.1);
      final leaf = ContainerLayer();
      root.append(outer);
      outer.append(inner);
      inner.append(leaf);
      Matrix4? previous;
      for (final offset in [_offset, const Offset(8.7, 9.4)]) {
        outer.offset = offset;
        root.buildScene(ui.SceneBuilder()).dispose();
        final parentWorld = _transform(root, outer)
          ..multiply(_transform(outer, inner));
        _integerRect(MatrixUtils.transformRect(parentWorld, outer.viewport));
        final world = parentWorld..multiply(_transform(inner, leaf));
        _integerRect(MatrixUtils.transformRect(world, inner.viewport));
        if (previous != null) expect(world, isNot(previous));
        previous = world;
      }
      expect(outer.debugSceneCount, 2);
      expect(inner.debugSceneCount, 2);
      handle.layer = null;
    },
  );

  test(
    'applyTransform and annotation inverse match the actual scene matrix',
    () {
      final snap = PixelSnapLayer()
        ..viewport = _viewport
        ..offset = _offset;
      final handle = LayerHandle<PixelSnapLayer>(snap);
      final annotation = AnnotatedRegionLayer<String>(
        'inside',
        size: const Size(30, 30),
      );
      snap.append(annotation);
      for (final offset in [_offset, const Offset(2.6, 4.7)]) {
        snap.offset = offset;
        snap.buildScene(ui.SceneBuilder()).dispose();
        const point = Offset(10.1, 20.2);
        final projected = MatrixUtils.transformPoint(
          _transform(snap, annotation),
          point,
        );
        final result = snap.findAllAnnotations<String>(projected);
        expect(result.entries.single.annotation, 'inside');
        expect(
          result.entries.single.localPosition.dx,
          closeTo(point.dx, _epsilon),
        );
        expect(
          result.entries.single.localPosition.dy,
          closeTo(point.dy, _epsilon),
        );
      }
      handle.layer = null;
    },
  );

  test('linked follower sees snapped descendant leader on each scene', () {
    final root = OffsetLayer();
    final handle = LayerHandle<OffsetLayer>(root);
    final snap = PixelSnapLayer()..viewport = _viewport;
    final link = LayerLink();
    final leader = LeaderLayer(link: link, offset: const Offset(4.3, 5.7));
    final follower = FollowerLayer(
      link: link,
      showWhenUnlinked: false,
      unlinkedOffset: Offset.zero,
      linkedOffset: Offset.zero,
    );
    root.append(snap);
    snap.append(leader);
    root.append(follower);
    root.attach(Object());
    for (final offset in [_offset, const Offset(19.3, 23.4)]) {
      snap.offset = offset;
      root.buildScene(ui.SceneBuilder()).dispose();
      expect(snap.debugDidSnap, isTrue);
      final expected = _transform(snap, leader);
      leader.applyTransform(null, expected);
      final actual = follower.getLastTransform()!;
      expect(actual.storage, orderedEquals(expected.storage));
    }
    root.detach();
    handle.layer = null;
  });

  test(
    'half-pixel ties keep both near and far edge movement below one pixel',
    () {
      final layer = PixelSnapLayer()
        ..viewport = const Rect.fromLTWH(0, 0, 93.5, 65.5)
        ..offset = const Offset(13.5, 17.5);
      final handle = LayerHandle<PixelSnapLayer>(layer);
      final child = ContainerLayer();
      layer.append(child);
      layer.buildScene(ui.SceneBuilder()).dispose();
      final original = layer.viewport.shift(layer.offset);
      final snapped = MatrixUtils.transformRect(
        _transform(layer, child),
        layer.viewport,
      );
      _integerRect(snapped);
      for (final difference in [
        snapped.left - original.left,
        snapped.top - original.top,
        snapped.right - original.right,
        snapped.bottom - original.bottom,
      ]) {
        expect(difference.abs(), lessThan(1));
      }
      handle.layer = null;
    },
  );

  test('empty, subpixel and non-finite viewports fall back without invalid matrices', () {
    for (final viewport in [
      Rect.zero,
      const Rect.fromLTWH(0, 0, 0.1, 0.1),
      const Rect.fromLTWH(double.infinity, 0, 24, 24),
    ]) {
      final layer = PixelSnapLayer()..viewport = viewport;
      final handle = LayerHandle<PixelSnapLayer>(layer);
      layer.buildScene(ui.SceneBuilder()).dispose();
      expect(layer.debugDidSnap, isFalse);
      expect(layer.debugCorrection, Matrix4.identity());
      handle.layer = null;
    }
  });
}
