// Locks down the per-icon widget/render-object tree shape, which is a
// build-phase cost multiplied by every mounted cell in a scrolling grid.
//
// Why a *count* test and not only a timing benchmark: an element and a render
// object per icon are what the framework has to inflate, attach, lay out and
// walk on every mount, and unlike a duration a count is exact and noise-free.
// The `LIB=anim_fps ITEMS=1000` acceptance scenario mounts and unmounts cells
// continuously, so a redundant layer is paid once per cell per appearance.
//
// 锁定单图标的控件/渲染对象树形状——这是 build 阶段的开销，且要乘上滚动网格里
// 每一个已挂载的格子。
//
// 为什么用*计数*测试而不只用计时基准：每个图标多一个 element 加一个 render
// object，就是框架每次挂载都要多 inflate、多 attach、多布局、多遍历的东西；而与
// 耗时不同，计数是精确且无噪声的。`LIB=anim_fps ITEMS=1000` 验收场景会持续挂载
// 与卸载格子，因此一层冗余每格每次出现都要付一次。

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/svgx.dart';

const _animatedSource =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
    '<path d="M2 12h20" stroke="#000" stroke-width="2" '
    'stroke-dasharray="24" stroke-dashoffset="24">'
    '<animate attributeName="stroke-dashoffset" dur="1s" values="24;0" '
    'fill="freeze"/></path></svg>';

const _staticSource =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
    '<path d="M2 12h20" stroke="#000" stroke-width="2"/></svg>';

/// Names of every [RenderObject] in the subtree rooted at [finder]'s element,
/// in depth-first order.
///
/// [finder] 对应 element 所在子树中每个 [RenderObject] 的类型名，按深度优先序。
///
/// Returns the runtime type names. / 返回运行时类型名列表。
List<String> _renderChain(WidgetTester tester, Finder finder) {
  final names = <String>[];
  void visit(RenderObject object) {
    names.add(object.runtimeType.toString());
    object.visitChildren(visit);
  }

  visit(tester.renderObject(finder));
  return names;
}

/// Runtime type names of every [Element] in the subtree rooted at [finder].
///
/// [finder] 所在子树中每个 [Element] 的运行时类型名。
///
/// Returns widget type names (not element type names), which is what reads as
/// the widget tree. / 返回控件类型名（而非 element 类型名），读起来就是控件树。
List<String> _widgetChain(WidgetTester tester, Finder finder) {
  final names = <String>[];
  void visit(Element element) {
    names.add(element.widget.runtimeType.toString());
    element.visitChildren(visit);
  }

  visit(tester.element(finder));
  return names;
}

void main() {
  testWidgets('animated icon builds no redundant sizing layer', (tester) async {
    await tester.pumpWidget(
      const Center(
        child: SvgXAnimated.string(_animatedSource, width: 32, height: 32),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    // RenderConstrainedBox is what a `SizedBox` inflates to. `CustomPaint`
    // already sizes itself to its `size` argument when it has no child
    // (`RenderCustomPaint.computeSizeForNoChild` -> `constraints.constrain(
    // preferredSize)`), so wrapping it in a `SizedBox` of the same dimensions
    // adds a layer that cannot change the outcome.
    //
    // RenderConstrainedBox 就是 `SizedBox` 生成的渲染对象。`CustomPaint` 在没有
    // child 时本就会把自己撑到 `size` 参数（`RenderCustomPaint.
    // computeSizeForNoChild` -> `constraints.constrain(preferredSize)`），因此再
    // 用同尺寸的 `SizedBox` 包一层，是加了一层不可能改变结果的层级。
    expect(
      _renderChain(tester, find.byType(SvgXAnimated)),
      isNot(contains('RenderConstrainedBox')),
    );
    expect(
      _widgetChain(tester, find.byType(SvgXAnimated)),
      isNot(contains('SizedBox')),
    );
  });

  testWidgets('static icon builds no redundant sizing layer', (tester) async {
    await tester.pumpWidget(
      const Center(child: SvgXStatic(_staticSource, width: 32, height: 32)),
    );
    await tester.pump();
    expect(
      _renderChain(tester, find.byType(SvgXStatic)),
      isNot(contains('RenderConstrainedBox')),
    );
  }, skip: true); // needs the Rust FFI library / 需要 Rust FFI 动态库

  // The layer being removed is a sizing layer, so the thing that must be
  // proven unchanged is the resulting size, under every constraint regime a
  // caller can impose: tighter than the icon, looser than it, and unbounded.
  // A grid cell is the first case, a `Center` the second, a scrollable's cross
  // axis the third.
  //
  // 被移除的是一层"定尺寸"的层级，因此必须证明不变的正是最终尺寸，且要覆盖调用方
  // 可能施加的每一种约束状态：比图标更紧、更松、以及无界。网格格子是第一种，
  // `Center` 是第二种，可滚动组件的交叉轴是第三种。
  for (final (label, constraints, expected) in <(String, BoxConstraints, Size)>[
    (
      'tight smaller than icon',
      BoxConstraints.tight(const Size(20, 20)),
      Size(20, 20),
    ),
    (
      'loose larger than icon',
      BoxConstraints.loose(const Size(100, 100)),
      Size(32, 32),
    ),
    ('loose to parent', BoxConstraints(), Size(32, 32)),
    (
      'tight larger than icon',
      BoxConstraints.tight(const Size(64, 64)),
      Size(64, 64),
    ),
  ]) {
    testWidgets('animated icon size under $label', (tester) async {
      await tester.pumpWidget(
        Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: constraints,
            child: const SvgXAnimated.string(
              _animatedSource,
              width: 32,
              height: 32,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.getSize(find.byType(CustomPaint).last), expected);
    });
  }
}
