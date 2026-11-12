import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/grid.dart';
import 'package:luckdraw/wheel.dart';

/// 叠加层测试尺寸。
const Size _size = Size(240, 180);

/// 测试奖品配置，按钮不应生成叠加条目。
const GridConfig _config = GridConfig(
    rows: 2,
    cols: 3,
    prizes: [GridPrize(x: 0, y: 0, col: 2), GridPrize(x: 2, y: 1)],
    buttons: [GridButton(x: 2, y: 0)]);

/// 提供有界盒子与文字方向。
Widget _root(Widget child) => Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox.fromSize(size: _size, child: child)));

/// 创建只用于几何测试的布局。
GridLayout _layout([Size size = _size]) {
  final input = LuckyLayoutInput.headless(size);
  try {
    return const GridGame().computeLayout(_config, input);
  } finally {
    input.measurer.dispose();
  }
}

/// 保留原始矩阵引用，模拟 Flow 的 TransformLayer 所有权。
final class _PaintContext implements FlowPaintingContext {
  /// 指定子节点数。
  _PaintContext(this.childCount);

  /// 记录矩阵引用而非副本。
  final Map<int, Matrix4> transforms = {};

  /// 子节点数。
  @override
  final int childCount;

  /// 测试表面大小。
  @override
  Size get size => _size;

  /// 返回固定子节点尺寸。
  @override
  Size? getChildSize(int i) => _size;

  /// 保存本次绘制矩阵，断言全部子节点都有独立实例。
  @override
  void paintChild(int i, {Matrix4? transform, double opacity = 1}) {
    expect(opacity, 1);
    transforms[i] = transform!;
  }
}

/// 验证奖品 Widget 的布局、矩阵所有权与独立重绘。
void main() {
  group('LuckyItemOverlay', () {
    testWidgets('places one child per item using the game item geometry',
        (tester) async {
      final layout = _layout();
      final notifier = ChangeNotifier();
      addTearDown(notifier.dispose);
      final geometry = const GridGame().itemGeometry;
      const first = ValueKey('first prize');
      const second = ValueKey('second prize');
      await tester.pumpWidget(_root(LuckyItemOverlay(
          geometry: geometry,
          layout: layout,
          frame: GridFrame(),
          frameListenable: notifier,
          children: const [SizedBox(key: first), SizedBox(key: second)])));

      expect(geometry.itemCount(layout), _config.prizes.length);
      expect(tester.getSize(find.byKey(first)), layout.hitRect(0).size);
      expect(tester.getSize(find.byKey(second)), layout.hitRect(1).size);
      expect(tester.getTopLeft(find.byKey(first)), layout.hitRect(0).topLeft);
      expect(tester.getTopLeft(find.byKey(second)), layout.hitRect(1).topLeft);
      final flow = tester.widget<Flow>(find.byType(Flow));
      final paint = _PaintContext(2);
      flow.delegate.paintChildren(paint);
      expect(paint.transforms.keys, [0, 1]);
      expect(identical(paint.transforms[0], paint.transforms[1]), isFalse);
      expect(paint.transforms[0]!.getTranslation().x, layout.hitRect(0).left);
      expect(paint.transforms[1]!.getTranslation().x, layout.hitRect(1).left);
    });

    testWidgets('repaints child transforms without rebuilding children',
        (tester) async {
      const config = WheelConfig(prizes: [WheelPrize(), WheelPrize()]);
      final input = LuckyLayoutInput.headless(_size);
      final layout = const WheelGame().computeLayout(config, input);
      input.measurer.dispose();
      final frame = WheelFrame();
      final notifier = ChangeNotifier();
      addTearDown(notifier.dispose);
      var builds = 0;
      const childKey = ValueKey('animated prize');
      await tester.pumpWidget(_root(LuckyItemOverlay(
          geometry: const WheelGame().itemGeometry,
          layout: layout,
          frame: frame,
          frameListenable: notifier,
          children: [
            Builder(builder: (_) {
              builds++;
              return const SizedBox(key: childKey);
            }),
            const SizedBox()
          ])));
      final before = tester.getTopLeft(find.byKey(childKey));
      final delegate = tester.widget<Flow>(find.byType(Flow)).delegate;
      final retained = _PaintContext(2);
      delegate.paintChildren(retained);
      final original = retained.transforms[0]!.clone();
      frame.rotateDeg = 90;
      notifier.notifyListeners();
      await tester.pump();
      expect(builds, 1);
      expect(tester.getTopLeft(find.byKey(childKey)), isNot(before));
      final next = _PaintContext(2);
      delegate.paintChildren(next);
      expect(retained.transforms[0], original);
      expect(identical(next.transforms[0], retained.transforms[0]), isFalse);
      expect(next.transforms[0], isNot(original));
    });

    testWidgets('updates constraints clipping and listeners on replacement',
        (tester) async {
      final geometry = const GridGame().itemGeometry;
      final notifier = ChangeNotifier();
      final replacement = ChangeNotifier();
      addTearDown(notifier.dispose);
      addTearDown(replacement.dispose);
      final frame = GridFrame();
      const children = [SizedBox(), SizedBox()];

      /// 用相同子树比较委托在输入替换前后的失效行为。
      Widget overlay(
              GridLayout layout, GridFrame frame, Listenable listenable) =>
          _root(LuckyItemOverlay(
              geometry: geometry,
              layout: layout,
              frame: frame,
              frameListenable: listenable,
              children: children));
      final layout = _layout();
      await tester.pumpWidget(overlay(layout, frame, notifier));
      final original = tester.widget<Flow>(find.byType(Flow)).delegate;
      await tester.pumpWidget(overlay(layout, frame, notifier));
      var current = tester.widget<Flow>(find.byType(Flow)).delegate;
      expect(current.shouldRelayout(original), isFalse);
      expect(current.shouldRepaint(original), isFalse);
      await tester
          .pumpWidget(overlay(_layout(const Size(180, 120)), frame, notifier));
      current = tester.widget<Flow>(find.byType(Flow)).delegate;
      expect(current.shouldRelayout(original), isTrue);
      expect(current.shouldRepaint(original), isTrue);
      await tester.pumpWidget(overlay(layout, GridFrame(), replacement));
      current = tester.widget<Flow>(find.byType(Flow)).delegate;
      expect(current.shouldRepaint(original), isTrue);
      final clippers = tester.widgetList<ClipRect>(find.byType(ClipRect));
      expect(clippers.single.clipper!.getClip(_size), Offset.zero & _size);
      expect(clippers.single.clipper!.shouldReclip(clippers.single.clipper!),
          isFalse);
      await tester.pumpWidget(_root(LuckyItemOverlay(
          geometry: geometry,
          layout: _layout(Size.zero),
          frame: frame,
          frameListenable: notifier,
          children: children)));
      final invisible = _PaintContext(2);
      tester.widget<Flow>(find.byType(Flow)).delegate.paintChildren(invisible);
      expect(invisible.transforms, isEmpty);
    });
  });
}
