// Unit tests for paint callbacks (before/after hooks for grid tiles / draw commands).
//
// Constructs a [RoadPainter] directly and calls [RoadPainter.paint] (with a
// PictureRecorder backing the canvas), bypassing the widget tree -- the callbacks
// themselves are unrelated to the widget lifecycle, so this only cares about the
// firing order and payload correctness during paint().

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadsman/roadsman.dart';

/// Paints one frame with [RoadPainter] onto a throwaway [Canvas] (the result doesn't
/// matter -- this only cares about which callbacks fire).
void _paintOnce(RoadPainter painter, {Size size = const Size(200, 200)}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  painter.paint(canvas, size);
  recorder.endRecording().dispose();
}

void main() {
  group('onBeforePaintGridCell / onAfterPaintGridCell', () {
    test('tile 网格逐格触发，先 before 后 after，且携带正确的矩形/颜色/行列号', () {
      final calls = <String>[];
      Rect? firstRect;

      final painter = RoadPainter(
        commands: const [],
        contentWidth: 100,
        viewportOffset: Offset.zero,
        viewportScale: 1,
        background: 0xFF000000,
        grid: const GridSpec(cellSize: 20, style: GridStyle.tile, tileFill: 0xFFFF0000),
        onBeforePaintGridCell: (info) {
          calls.add('before(${info.row},${info.col})');
          firstRect ??= info.rect;
          expect(info.color, const Color(0xFFFF0000));
        },
        onAfterPaintGridCell: (info) {
          calls.add('after(${info.row},${info.col})');
        },
      );

      _paintOnce(painter);

      expect(calls, isNotEmpty);
      // Each cell must fire before then after, never interleaved.
      for (var i = 0; i < calls.length; i += 2) {
        final row = calls[i].substring(calls[i].indexOf('(') + 1, calls[i].indexOf(','));
        final col = calls[i].substring(calls[i].indexOf(',') + 1, calls[i].indexOf(')'));
        expect(calls[i], 'before($row,$col)');
        expect(calls[i + 1], 'after($row,$col)');
      }
      expect(firstRect, isNotNull);
      expect(firstRect!.width, greaterThan(0));
      expect(firstRect!.height, greaterThan(0));
    });

    test('line 样式网格不触发瓷砖回调（没有离散格子）', () {
      var called = false;
      final painter = RoadPainter(
        commands: const [],
        contentWidth: 100,
        viewportOffset: Offset.zero,
        viewportScale: 1,
        background: 0xFF000000,
        grid: const GridSpec(cellSize: 20, style: GridStyle.line),
        onBeforePaintGridCell: (_) => called = true,
      );

      _paintOnce(painter);

      expect(called, isFalse);
    });

    test('设置瓷砖回调后绕过 gridCache——即使传了缓存也逐帧触发', () {
      final gridCache = GridLayerCache();
      addTearDown(gridCache.dispose);
      var callCount = 0;

      RoadPainter painter() => RoadPainter(
        commands: const [],
        contentWidth: 100,
        viewportOffset: Offset.zero,
        viewportScale: 1,
        background: 0xFF000000,
        grid: const GridSpec(cellSize: 20, style: GridStyle.tile),
        gridCache: gridCache,
        onBeforePaintGridCell: (_) => callCount++,
      );

      _paintOnce(painter());
      final afterFirstPaint = callCount;
      expect(afterFirstPaint, greaterThan(0));

      _paintOnce(painter()); // second frame: if the Picture cache hits, the callback won't fire again
      expect(callCount, afterFirstPaint * 2);
    });
  });

  group('onBeforePaintCommand / onAfterPaintCommand', () {
    test('每条 commands/overlayCommands 各触发一次，先 before 后 after，携带原始指令', () {
      final before = <DrawCommand>[];
      final after = <DrawCommand>[];

      const circle = CircleCommand(x: 10, y: 10, r: 5, fill: 0xFFFFFFFF);
      const dot = DotCommand(x: 20, y: 20, r: 3, fill: 0xFF00FF00);

      final painter = RoadPainter(
        commands: const [circle],
        overlayCommands: const [dot],
        contentWidth: 100,
        viewportOffset: Offset.zero,
        viewportScale: 1,
        background: 0xFF000000,
        onBeforePaintCommand: (info) => before.add(info.command),
        onAfterPaintCommand: (info) => after.add(info.command),
      );

      _paintOnce(painter);

      expect(before, [circle, dot]);
      expect(after, [circle, dot]);
    });

    test('设置指令回调后绕过 layerCache——即使传了缓存也逐帧触发', () {
      final layerCache = CommandLayerCache();
      addTearDown(layerCache.dispose);
      var callCount = 0;
      const commands = [CircleCommand(x: 1, y: 1, r: 1, fill: 0xFFFFFFFF)];

      RoadPainter painter() => RoadPainter(
        commands: commands,
        contentWidth: 100,
        viewportOffset: Offset.zero,
        viewportScale: 1,
        background: 0xFF000000,
        layerCache: layerCache,
        onBeforePaintCommand: (_) => callCount++,
      );

      _paintOnce(painter());
      expect(callCount, 1);

      _paintOnce(painter()); // same commands reference: if replayed from cache, the callback won't fire again
      expect(callCount, 2);
    });

    test('未设置任何回调时行为不变（不抛异常，路径与之前一致）', () {
      const commands = [
        CircleCommand(x: 1, y: 1, r: 1, fill: 0xFFFFFFFF),
        RectCommand(x: 0, y: 0, w: 5, h: 5, fill: 0xFF000000),
      ];
      final painter = RoadPainter(
        commands: commands,
        contentWidth: 100,
        viewportOffset: Offset.zero,
        viewportScale: 1,
        background: 0xFF000000,
        grid: const GridSpec(cellSize: 20, style: GridStyle.tile),
      );

      expect(() => _paintOnce(painter), returnsNormally);
    });
  });
}
