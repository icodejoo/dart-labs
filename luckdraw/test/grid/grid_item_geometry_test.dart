import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/grid.dart';

/// 独立跨格夹具；覆盖内边距、间距、按钮排除及激活阴影。
const GridConfig _config = GridConfig(
    rows: 3,
    cols: 3,
    blocks: [LuckyBoxBlock(padding: LuckyEdgeInsets.all(10))],
    prizes: [GridPrize(x: 0, y: 0, col: 2, row: 2), GridPrize(x: 2, y: 2)],
    buttons: [GridButton(x: 2, y: 0)],
    activeStyle: LuckyCellStyle(
        background: LuckyFill.color(Color(0xFF112233)),
        shadow: LuckyShadow(offsetX: 4, offsetY: 6, color: Color(0xFF000000))));

/// 测试表面尺寸。
const Size _size = Size(300, 240);

/// 创建独立布局并释放测量资源。
GridLayout _layout([Size size = _size]) {
  final input = LuckyLayoutInput.headless(size);
  try {
    return const GridGame().computeLayout(_config, input);
  } finally {
    input.measurer.dispose();
  }
}

/// 验证奖品矩形与宿主叠加层接入。
void main() {
  group('GridGame itemGeometry', () {
    test('uses complete spanning prize rectangles and excludes buttons', () {
      final geometry = const GridGame().itemGeometry;
      final layout = _layout();
      final frame = GridFrame();
      expect(geometry.itemCount(layout), _config.prizes.length);
      for (var i = 0; i < geometry.itemCount(layout); i++) {
        final rect = layout.hitRect(i);
        expect(geometry.itemSize(layout, i), rect.size);
        final matrix = Matrix4.zero();
        expect(geometry.transformFor(layout, frame, i, matrix), isTrue);
        expect(MatrixUtils.transformPoint(matrix, Offset.zero), rect.topLeft);
        expect(
            MatrixUtils.transformPoint(
                matrix, rect.size.bottomRight(Offset.zero)),
            rect.bottomRight);
        frame.activeIndex = i;
        final active = Matrix4.zero();
        expect(geometry.transformFor(layout, frame, i, active), isTrue);
        expect(active, matrix);
      }
      expect(
          geometry.transformFor(_layout(Size.zero), frame, 0, Matrix4.zero()),
          isFalse);
    });

    testWidgets('overlayBuilder receives current geometry and allows cell taps',
        (tester) async {
      final controller = GridController();
      addTearDown(controller.dispose);
      int? tapped;
      LuckySurfaceData<GridConfig, GridLayout, GridFrame>? seen;
      await tester.pumpWidget(MediaQuery(
          data: const MediaQueryData(),
          child: Directionality(
              textDirection: TextDirection.ltr,
              child: Align(
                  alignment: Alignment.topLeft,
                  child: LuckyGrid(
                      config: _config,
                      controller: controller,
                      width: _size.width,
                      height: _size.height,
                      onCellTap: (index) => tapped = index,
                      overlayBuilder: (context, data) {
                        seen = data;
                        return LuckyItemOverlay(
                            geometry: const GridGame().itemGeometry,
                            layout: data.layout,
                            frame: data.frame,
                            frameListenable: data.frameListenable,
                            children: const [SizedBox(), SizedBox()]);
                      })))));
      expect(seen!.config, _config);
      expect(identical(seen!.frame, controller.frame), isTrue);
      await tester.tapAt(seen!.layout.hitRect(1).center);
      expect(tapped, 1);
      expect(
          find.byType(LuckyItemOverlay<GridLayout, GridFrame>), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
