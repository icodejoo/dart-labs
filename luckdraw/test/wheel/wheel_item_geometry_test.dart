import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/wheel.dart';

/// 包含不等分、圆环内边距和按钮的独立奖品夹具。
const WheelConfig _config = WheelConfig(
    blocks: [WheelBlock(padding: 12)],
    prizes: [WheelPrize(sectorWeight: 1), WheelPrize(sectorWeight: 3)],
    buttons: [WheelButton(radius: LuckyLength.px(20))],
    options: WheelOptions(offsetDegree: 17));

/// 非正方形表面验证对齐偏移。
const Size _size = Size(320, 240);

/// 旋转边界包含负角与多周累计角。
const List<double> _angles = [-90, 0, 90, 720];

/// 提供 Widget 所需的媒体环境。
Widget _root(Widget child) => MediaQuery(
    data: const MediaQueryData(),
    child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(alignment: Alignment.topLeft, child: child)));

/// 验证圆心、扇区外缘锚点以及正向内的局部 y 轴。
void main() {
  group('WheelGame itemGeometry', () {
    test(
        'anchors weighted sectors at the outer edge and rotates with the frame',
        () {
      final input = LuckyLayoutInput(
          size: _size,
          devicePixelRatio: 1,
          alignment: Alignment.bottomRight,
          measurer: TextPainterMeasurer());
      final layout = const WheelGame().computeLayout(_config, input);
      input.measurer.dispose();
      final geometry = const WheelGame().itemGeometry;
      final frame = WheelFrame();
      expect(geometry.itemCount(layout), _config.prizes.length);
      expect(layout.center, const Offset(200, 120));
      for (final angle in _angles) {
        frame.rotateDeg = angle;
        for (var i = 0; i < geometry.itemCount(layout); i++) {
          final sector = layout.sectors[i];
          final size = geometry.itemSize(layout, i);
          expect(size, Size(sector.shortSide, layout.prizeRadius - 20));
          final matrix = Matrix4.zero();
          expect(geometry.transformFor(layout, frame, i, matrix), isTrue);
          final radialAngle = sector.middleRad + angle * math.pi / 180;
          final expected = layout.center +
              Offset(math.cos(radialAngle), math.sin(radialAngle)) *
                  layout.prizeRadius;
          final top =
              MatrixUtils.transformPoint(matrix, Offset(size.width / 2, 0));
          final inside = MatrixUtils.transformPoint(
              matrix, Offset(size.width / 2, size.height));
          expect((top - expected).distance, lessThan(1e-9));
          expect((inside - layout.center).distance, closeTo(20, 1e-9));
        }
      }
      expect(geometry.itemSize(layout, 1).width,
          closeTo(geometry.itemSize(layout, 0).width, 1e-9));
    });

    test('hides empty layouts and reports no items for an empty prize list',
        () {
      final input = LuckyLayoutInput.headless(Size.zero);
      final layout = const WheelGame().computeLayout(_config, input);
      final empty = const WheelGame().computeLayout(const WheelConfig(), input);
      input.measurer.dispose();
      final geometry = const WheelGame().itemGeometry;
      expect(geometry.transformFor(layout, WheelFrame(), 0, Matrix4.identity()),
          isFalse);
      expect(geometry.itemCount(empty), 0);
    });

    testWidgets(
        'overlayBuilder shares the applied layout and preserves button taps',
        (tester) async {
      final controller = WheelController();
      addTearDown(controller.dispose);
      var starts = 0;
      LuckySurfaceData<WheelConfig, WheelLayout, WheelFrame>? seen;
      await tester.pumpWidget(_root(LuckyWheel(
          config: _config,
          controller: controller,
          width: _size.width,
          height: _size.height,
          onStart: () => starts++,
          overlayBuilder: (context, data) {
            seen = data;
            return LuckyItemOverlay(
                geometry: const WheelGame().itemGeometry,
                layout: data.layout,
                frame: data.frame,
                frameListenable: data.frameListenable,
                children: const [SizedBox(), SizedBox()]);
          })));
      expect(seen!.config, _config);
      expect(identical(seen!.frame, controller.frame), isTrue);
      expect(find.byType(LuckyItemOverlay<WheelLayout, WheelFrame>),
          findsOneWidget);
      await tester.tapAt(seen!.layout.center);
      expect(starts, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
