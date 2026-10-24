// Regression tests for the "child stuck after the parent takes over and the
// drag is reversed" bug in LinkScrollControllerMixin.linkActivedParent.
//
// 回归测试：子层滚到边界、父层接管后，同一次手势里反向拖回，子层应能重新滚动。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_scroll_library/sync_scroll_library.dart';

/// Width of both viewports. 两层视口的宽度。
const double _kViewportWidth = 400;

/// Height of both viewports. 两层视口的高度。
const double _kViewportHeight = 200;

/// Item extent of the child list. 子层单个条目的宽度。
const double _kChildItemExtent = 100;

/// Item count of a scrollable child: 800 wide, so its max extent is 400.
/// 可滚动子层的条目数：内容宽 800，最大滚动距离 400。
const int _kScrollableChildItemCount = 8;

/// Max scroll extent of the scrollable child. 可滚动子层的最大滚动距离。
const double _kChildMaxExtent = 400;

/// Offset the parent starts at; this is the anchor recorded on takeover.
/// 父层的初始偏移，也就是接管时记下的锚点。
const double _kAnchor = 100;

/// Distance of every simulated pointer move. 每次模拟指针移动的距离。
const double _kStep = 30;

/// How far the parent has to travel away from its anchor in each scenario.
/// 每个场景里父层需要离开锚点多远。
const double _kParentTravel = 60;

/// Upper bound of pointer moves per drag phase. 每个拖拽阶段最多移动多少次。
const int _kMaxSteps = 60;

/// Key of the parent list, used to locate the gesture start. 父层的 key，用来定位手势起点。
const Key _kOuterKey = Key('outer');

/// A horizontal list driven by [LinkScrollState], used as parent and child.
///
/// 由 [LinkScrollState] 驱动的横向列表，父层和子层共用。
class _LinkList extends StatefulWidget {
  const _LinkList({
    Key? key,
    required this.controller,
    required this.link,
    required this.itemCount,
    required this.itemExtent,
    required this.itemBuilder,
  }) : super(key: key);

  /// Controller of this list. 本列表的控制器。
  final LinkScrollController controller;

  /// Whether to link to the nearest ancestor [_LinkList]. 是否关联最近的祖先 [_LinkList]。
  final bool link;

  /// Number of items. 条目数。
  final int itemCount;

  /// Extent of every item. 单个条目的宽度。
  final double itemExtent;

  /// Builds an item. 构建条目。
  final IndexedWidgetBuilder itemBuilder;

  @override
  State<_LinkList> createState() => _LinkListState();
}

/// State of [_LinkList]; mirrors how extended_tabs wires its tab view.
///
/// [_LinkList] 的 State，接法与 extended_tabs 的 TabBarView 一致。
class _LinkListState extends LinkScrollState<_LinkList> {
  @override
  LinkScrollControllerMixin get linkScrollController => widget.controller;

  @override
  bool get link => widget.link;

  @override
  ScrollPhysics? get physics => null;

  @override
  Axis get scrollDirection => Axis.horizontal;

  // Binds the concrete types used to find the ancestor; same as extended_tabs.
  @override
  // ignore: unnecessary_overrides
  void linkParent<S extends StatefulWidget, T extends LinkScrollState<S>>() {
    super.linkParent<_LinkList, _LinkListState>();
  }

  @override
  Widget build(BuildContext context) {
    // The list never reacts to touches itself; the gesture detector below
    // forwards drags to the controller, exactly like ExtendedTabBarView.
    return buildGestureDetector(
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        controller: widget.controller,
        physics: const NeverScrollableClampingScrollPhysics(),
        itemExtent: widget.itemExtent,
        itemCount: widget.itemCount,
        itemBuilder: widget.itemBuilder,
      ),
    );
  }
}

/// Pumps a linked child list as the first page of a three-page parent list.
///
/// 把一个关联的子层列表放进三页父层列表的第一页。
Future<void> _pumpNested(
  WidgetTester tester, {
  required LinkScrollController outer,
  required LinkScrollController inner,
  required int childItemCount,
  required TextDirection textDirection,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: textDirection,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: _kViewportWidth,
            height: _kViewportHeight,
            child: _LinkList(
              key: _kOuterKey,
              controller: outer,
              link: false,
              itemCount: 3,
              itemExtent: _kViewportWidth,
              itemBuilder: (BuildContext context, int index) {
                if (index != 0) {
                  return const SizedBox.expand();
                }
                return _LinkList(
                  controller: inner,
                  link: true,
                  itemCount: childItemCount,
                  itemExtent: _kChildItemExtent,
                  itemBuilder: (BuildContext context, int index) =>
                      const SizedBox.expand(),
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
}

/// Puts a pointer down on the child list, away from the viewport edges.
///
/// 在子层上按下指针，位置避开视口边缘。
Future<TestGesture> _startGesture(WidgetTester tester) {
  return tester.startGesture(
    tester.getTopLeft(find.byKey(_kOuterKey)) + const Offset(200, 100),
  );
}

/// Moves [gesture] by [dx] once per frame for exactly [steps] frames.
///
/// 每帧移动 [dx]，共 [steps] 帧。
Future<void> _dragSteps(
  WidgetTester tester,
  TestGesture gesture,
  double dx,
  int steps,
) async {
  for (int i = 0; i < steps; i++) {
    await gesture.moveBy(Offset(dx, 0));
    await tester.pump();
  }
}

/// Moves [gesture] by [dx] per frame until [done] holds, failing with
/// [reason] if it never does.
///
/// 每帧移动 [dx]，直到 [done] 成立；一直不成立就以 [reason] 失败。
Future<void> _dragUntil(
  WidgetTester tester,
  TestGesture gesture,
  double dx,
  bool Function() done,
  String reason,
) async {
  for (int i = 0; i < _kMaxSteps && !done(); i++) {
    await gesture.moveBy(Offset(dx, 0));
    await tester.pump();
  }
  expect(done(), isTrue, reason: reason);
}

/// Releases [gesture] and lets every ballistic activity settle.
///
/// 抬起手指并等所有惯性动画结束。
Future<void> _release(WidgetTester tester, TestGesture gesture) async {
  await gesture.up();
  await tester.pumpAndSettle();
}

/// Runs the full reverse-drag scenario in one gesture:
/// child runs into a boundary, parent takes over, finger reverses, parent
/// unwinds to its anchor, child scrolls again.
///
/// Set [towardEnd] to push the child into its end boundary, or leave it false
/// to push it into its start boundary.
///
/// 在同一次手势里跑完整的反向拖拽场景：子层撞到边界、父层接管、手指反向、
/// 父层退回锚点、子层重新滚动。[towardEnd] 为 true 时撞末端边界，否则撞起点边界。
Future<void> _expectHandBack(
  WidgetTester tester, {
  required TextDirection textDirection,
  required bool towardEnd,
}) async {
  final LinkScrollController outer =
      LinkScrollController(initialScrollOffset: _kAnchor);
  final LinkScrollController inner = LinkScrollController();
  addTearDown(outer.dispose);
  addTearDown(inner.dispose);
  await _pumpNested(
    tester,
    outer: outer,
    inner: inner,
    childItemCount: _kScrollableChildItemCount,
    textDirection: textDirection,
  );

  // +1 when the boundary hit is the end of the content, -1 for the start.
  final double sign = towardEnd ? 1 : -1;
  // Offset of the child while it is stuck at the boundary.
  final double boundary = towardEnd ? _kChildMaxExtent : 0;
  // Finger moving left scrolls forward in ltr and backward in rtl.
  final bool ltr = textDirection == TextDirection.ltr;
  final double outward = (towardEnd == ltr) ? -_kStep : _kStep;
  final double inward = -outward;

  // How far the parent moved away from its anchor, in the outward direction.
  double parentTravel() => (outer.offset - _kAnchor) * sign;
  // How far the child moved back from its boundary. A child that was scrolled
  // out of the parent's viewport has no position left, which counts as stuck.
  double childTravel() => inner.hasClients
      ? (boundary - inner.offset) * sign
      : double.negativeInfinity;

  final TestGesture gesture = await _startGesture(tester);

  // 1. The child runs into its boundary and the parent takes over.
  await _dragUntil(
    tester,
    gesture,
    outward,
    () => parentTravel() >= _kParentTravel,
    'the parent never took over the drag',
  );
  expect(inner.offset, boundary);
  expect(inner.isSelf, isFalse);
  final double deepest = parentTravel();

  // 2. The finger reverses: the parent keeps the drag while it unwinds,
  // and the child must not move yet.
  await _dragSteps(tester, gesture, inward, 1);
  expect(inner.isSelf, isFalse, reason: 'the parent is still off its anchor');
  expect(inner.offset, boundary);
  expect(parentTravel(), lessThan(deepest));
  expect(parentTravel(), greaterThan(0));

  // 3. The parent is back at its anchor: the child scrolls again within the
  // same gesture (this is what used to be stuck).
  await _dragUntil(
    tester,
    gesture,
    inward,
    () => childTravel() >= 90,
    'the child stayed stuck after the parent unwound to its anchor',
  );
  expect(inner.isSelf, isTrue);
  // The parent stops within one pointer move of its anchor.
  expect(outer.offset, closeTo(_kAnchor, _kStep));

  await _release(tester, gesture);
}

void main() {
  group('reverse drag after the parent took over', () {
    for (final TextDirection direction in <TextDirection>[
      TextDirection.ltr,
      TextDirection.rtl,
    ]) {
      testWidgets(
        'hands the drag back to the child at its end boundary ($direction)',
        (WidgetTester tester) => _expectHandBack(
          tester,
          textDirection: direction,
          towardEnd: true,
        ),
      );

      testWidgets(
        'hands the drag back to the child at its start boundary ($direction)',
        (WidgetTester tester) => _expectHandBack(
          tester,
          textDirection: direction,
          towardEnd: false,
        ),
      );
    }

    testWidgets('lets the parent take over again in the same gesture',
        (WidgetTester tester) async {
      final LinkScrollController outer =
          LinkScrollController(initialScrollOffset: _kAnchor);
      final LinkScrollController inner = LinkScrollController();
      addTearDown(outer.dispose);
      addTearDown(inner.dispose);
      await _pumpNested(
        tester,
        outer: outer,
        inner: inner,
        childItemCount: _kScrollableChildItemCount,
        textDirection: TextDirection.ltr,
      );
      final TestGesture gesture = await _startGesture(tester);

      // First takeover, then reverse until the child is released.
      await _dragUntil(
        tester,
        gesture,
        -_kStep,
        () => outer.offset >= _kAnchor + _kParentTravel,
        'the parent never took over the drag',
      );
      await _dragUntil(
        tester,
        gesture,
        _kStep,
        () => inner.offset <= _kChildMaxExtent - 60,
        'the child stayed stuck after the parent unwound to its anchor',
      );
      expect(inner.isSelf, isTrue);
      final double afterRelease = outer.offset;

      // Turn around again: the child hits its end and the parent takes over
      // with a fresh anchor.
      await _dragUntil(
        tester,
        gesture,
        -_kStep,
        () => outer.offset >= afterRelease + _kParentTravel,
        'the parent did not take over a second time',
      );
      expect(inner.isSelf, isFalse);
      expect(inner.offset, _kChildMaxExtent);

      await _release(tester, gesture);
    });

    testWidgets('keeps the drag with the parent when the child cannot scroll',
        (WidgetTester tester) async {
      final LinkScrollController outer =
          LinkScrollController(initialScrollOffset: _kAnchor);
      final LinkScrollController inner = LinkScrollController();
      addTearDown(outer.dispose);
      addTearDown(inner.dispose);
      // 4 x 100 fills the viewport exactly, so the child has no extent at all.
      await _pumpNested(
        tester,
        outer: outer,
        inner: inner,
        childItemCount: 4,
        textDirection: TextDirection.ltr,
      );
      final TestGesture gesture = await _startGesture(tester);

      await _dragUntil(
        tester,
        gesture,
        -_kStep,
        () => outer.offset >= _kAnchor + _kParentTravel,
        'the parent never took over the drag',
      );
      expect(inner.isSelf, isFalse);

      // Reversing far past the anchor: the child has nothing to scroll, so
      // the parent keeps the drag and simply clamps at its own start.
      await _dragSteps(tester, gesture, _kStep, 20);
      expect(inner.isSelf, isFalse);
      expect(inner.offset, 0);
      expect(outer.offset, 0);

      await _release(tester, gesture);
    });
  });
}
