import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/slot.dart';

/// 独立条带夹具：重排、重复、洞、空轮与短周期。
const SlotConfig _config = SlotConfig(prizes: [
  SlotPrize(),
  SlotPrize(),
  SlotPrize()
], reels: [
  SlotReel(order: [2, 0, 2, -1]),
  SlotReel(order: []),
  SlotReel(order: [1])
], blocks: [
  LuckyBoxBlock(padding: LuckyEdgeInsets.all(12))
]);

/// 足够容纳短条带多个循环的表面。
const Size _size = Size(240, 300);

/// 像素测试的窗口外背景。
const Color _background = Color(0xFF112233);

/// 像素测试的 Widget 颜色。
const Color _prizeColor = Color(0xFFCC4422);

/// 正反方向与跨周期的滚动样本。
const List<double> _scrolls = [-1000, 0, 1000];

/// 创建指定方向的布局。
SlotLayout _layout(SlotConfig config, [Size size = _size]) {
  final input = LuckyLayoutInput.headless(size);
  try {
    return const SlotGame().computeLayout(config, input);
  } finally {
    input.measurer.dispose();
  }
}

/// 带真实媒体环境的有界表面。
Widget _root(Widget child) => MediaQuery(
    data: const MediaQueryData(),
    child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox.fromSize(size: _size, child: child))));

/// 验证循环条带、横纵轴、边缘裁剪及实际 Widget 接入。
void main() {
  group('SlotGame itemGeometry', () {
    test('matches visible strip positions across modes wraps holes and repeats',
        () {
      final geometry = const SlotGame().itemGeometry;
      for (final mode in SlotMode.values) {
        final config = _config.copyWith(
            options: SlotOptions(
                mode: mode,
                rowSpacing: 6,
                colSpacing: 8,
                cellAspectRatio: 1.5));
        final layout = _layout(config);
        final frame = SlotFrame()..scroll = Float64List(layout.reels.length);
        final vertical = mode == SlotMode.vertical;
        final extent = vertical ? layout.cellHeight : layout.cellWidth;
        for (final scroll in _scrolls) {
          frame.scroll.fillRange(0, frame.scroll.length, scroll);
          var base = 0;
          for (var r = 0; r < layout.reels.length; r++) {
            final reel = layout.reels[r];
            final count = reel.stripPrizes.length;
            final copies = reel.period > 0
                ? (layout.windowLength / reel.period).ceil() + 1
                : 0;
            final expected = <double>[];
            if (count > 0) {
              // 独立枚举窗口前后足够多的完整周期作为几何基准。
              final centerCycle =
                  ((scroll + layout.windowStart) / reel.period).floor();
              for (var j = (centerCycle - 1) * count;
                  j < (centerCycle + copies + 1) * count;
                  j++) {
                final strip = j % count;
                final start = reel.stripStart[strip] +
                    ((j - strip) ~/ count) * reel.period -
                    (scroll + layout.windowStart);
                if (start < layout.windowLength &&
                    start + extent > 0 &&
                    reel.stripPrizes[strip] >= 0) {
                  expected.add(start);
                }
              }
            }
            final actual = <double>[];
            for (var i = base; i < base + count * copies; i++) {
              expect(geometry.itemSize(layout, i),
                  Size(layout.cellWidth, layout.cellHeight));
              final clipper = geometry as LuckyItemClipGeometry<SlotLayout>;
              expect(clipper.clipRectFor(layout, i), reel.clipRect);
              final matrix = Matrix4.zero();
              if (geometry.transformFor(layout, frame, i, matrix)) {
                final position =
                    MatrixUtils.transformPoint(matrix, Offset.zero);
                expect(vertical ? position.dx : position.dy,
                    vertical ? reel.clipRect.left : reel.clipRect.top);
                actual.add(vertical
                    ? position.dy - reel.clipRect.top
                    : position.dx - reel.clipRect.left);
              }
            }
            actual.sort();
            expected.sort();
            expect(actual.length, expected.length);
            for (var i = 0; i < actual.length; i++) {
              expect(actual[i], closeTo(expected[i], 1e-9));
            }
            base += count * copies;
          }
          expect(geometry.itemCount(layout), base);
        }
        expect(
            () => geometry.transformFor(
                layout, frame, geometry.itemCount(layout), Matrix4.zero()),
            throwsRangeError);
      }
      final empty = _layout(_config, Size.zero);
      expect(geometry.itemCount(empty), 0);
      expect(geometry.transformFor(empty, SlotFrame(), 0, Matrix4.zero()),
          isFalse);
    });

    test('distinguishes horizontal motion in a single square reel', () {
      final geometry = const SlotGame().itemGeometry;
      final config = _config.copyWith(
          blocks: const [],
          reels: const [SlotReel()],
          options: const SlotOptions(mode: SlotMode.horizontal, colSpacing: 0));
      final layout = _layout(config, const Size(120, 120));
      final frame = SlotFrame()..scroll = Float64List.fromList([20]);
      final matrix = Matrix4.zero();
      expect(geometry.transformFor(layout, frame, 0, matrix), isTrue);
      expect(MatrixUtils.transformPoint(matrix, Offset.zero),
          const Offset(-20, 0));
    });

    test('retains overlapping loop copies when spacing is negative', () {
      final geometry = const SlotGame().itemGeometry;
      final config = _config.copyWith(blocks: const [], reels: const [
        SlotReel(order: [0])
      ], options: const SlotOptions(rowSpacing: -60, colSpacing: 0));
      final layout = _layout(config, const Size(100, 300));
      final frame = SlotFrame()..scroll = Float64List.fromList([130]);
      final positions = <double>[];
      for (var i = 0; i < geometry.itemCount(layout); i++) {
        final matrix = Matrix4.zero();
        if (geometry.transformFor(layout, frame, i, matrix)) {
          positions.add(MatrixUtils.transformPoint(matrix, Offset.zero).dy);
        }
      }
      expect(positions, List.generate(10, (index) => -70.0 + index * 40));
      expect(
          positions.last + layout.cellHeight, greaterThan(layout.windowLength));
    });

    testWidgets('overlayBuilder clips repeated widgets to their reel windows',
        (tester) async {
      final controller = SlotController();
      addTearDown(controller.dispose);
      final geometry = const SlotGame().itemGeometry;
      const boundaryKey = ValueKey('overlay pixels');
      LuckySurfaceData<SlotConfig, SlotLayout, SlotFrame>? seen;
      await tester.pumpWidget(_root(RepaintBoundary(
          key: boundaryKey,
          child: ColoredBox(
              color: _background,
              child: LuckySlotMachine(
                  config: _config,
                  controller: controller,
                  overlayBuilder: (context, data) {
                    seen = data;
                    return LuckyItemOverlay(
                        geometry: geometry,
                        layout: data.layout,
                        frame: data.frame,
                        frameListenable: data.frameListenable,
                        children: [
                          for (var i = 0;
                              i < geometry.itemCount(data.layout);
                              i++)
                            const ColoredBox(color: _prizeColor)
                        ]);
                  })))));
      expect(seen!.config, _config);
      expect(identical(seen!.frame, controller.frame), isTrue);
      expect(
          find.byType(LuckyItemOverlay<SlotLayout, SlotFrame>), findsOneWidget);
      final boundary =
          tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        final pixelOffset = (20 * image.width + 2) * 4;
        expect(bytes.getUint8(pixelOffset), 0x11);
        expect(bytes.getUint8(pixelOffset + 1), 0x22);
        final window = seen!.layout.reels.last.clipRect;
        final prizeOffset = (window.center.dy.toInt() * image.width +
                window.center.dx.toInt()) *
            4;
        expect(bytes.getUint8(prizeOffset), 0xCC);
        expect(bytes.getUint8(prizeOffset + 1), 0x44);
        image.dispose();
      });
      final oldClipper = tester
          .widgetList<ClipRect>(find.byType(ClipRect))
          .firstWhere((clip) => clip.clipper != null)
          .clipper!;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_root(LuckySlotMachine(
          config: _config.copyWith(blocks: const []),
          controller: controller,
          overlayBuilder: (context, data) => LuckyItemOverlay(
                  geometry: geometry,
                  layout: data.layout,
                  frame: data.frame,
                  frameListenable: data.frameListenable,
                  children: [
                    for (var i = 0; i < geometry.itemCount(data.layout); i++)
                      const SizedBox()
                  ]))));
      final clip = tester
          .widgetList<ClipRect>(find.byType(ClipRect))
          .firstWhere((clip) => clip.clipper != null)
          .clipper!;
      expect(clip.shouldReclip(oldClipper), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
