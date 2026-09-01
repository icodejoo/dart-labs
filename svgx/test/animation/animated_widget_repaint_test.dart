// Guards the 2026-08-26 optimization that stopped [SvgxAnimated] calling
// setState once per Ticker tick.
//
// The timeline position is now published through a [ValueNotifier] wired to
// [AnimatedSvgPainter]'s `clock`, which [CustomPainter.repaint] turns into a
// paint-only invalidation — per Flutter's CustomPainter docs the render object
// then "repaint[s] whenever the animation ticks, avoiding both the build and
// layout phases of the pipeline". A future refactor that reintroduces a
// per-tick setState would silently give the build phase back its per-frame,
// per-icon cost, which in the 1000-animated-icon benchmark is the single
// largest number there — hence a test rather than a comment.
//
// 守护 2026-08-26 那项优化：[SvgxAnimated] 不再每次 Ticker tick 调用一次
// setState。
//
// 时间线位置现在通过一个绑定到 [AnimatedSvgPainter] `clock` 的 [ValueNotifier]
// 发布，[CustomPainter.repaint] 把它变成"只重绘"的失效——按 Flutter
// CustomPainter 文档，渲染对象此时会"repaint whenever the animation ticks,
// avoiding both the build and layout phases of the pipeline"。将来若有重构把
// 每 tick 一次的 setState 加回来，build 阶段就会悄悄拿回它每帧每图标的开销，
// 而在 1000 动画图标基准里那正是最大的一项——所以用测试而不是注释来守。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/animated_svg_painter.dart';
import 'package:svgx/svgx.dart';

// A one-second indefinite spin, so the ticker keeps running for the whole test
// instead of settling and stopping.
// 一个一秒的无限旋转，使 ticker 在整个测试期间持续运行，而不会结束后停止。
const _spinner =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
    'viewBox="0 0 24 24">'
    '<circle cx="12" cy="12" r="9" fill="none" stroke="#000" '
    'stroke-width="2" stroke-dasharray="40 20">'
    '<animateTransform attributeName="transform" type="rotate" '
    'values="0 12 12;360 12 12" dur="1s" repeatCount="indefinite"/>'
    '</circle></svg>';

// The observable signature of "did build() re-run" is whether the widgets it
// returns are the same instances: a rebuild necessarily constructs a fresh
// CustomPaint and a fresh AnimatedSvgPainter. Counting rebuilds from an
// ancestor would not work — setState only ever dirties its own element, so an
// ancestor's build would not re-run either way.
//
// "build() 有没有重跑"的可观测特征，是它返回的控件是否还是同一批实例：重建必然
// 会新建一个 CustomPaint 和一个 AnimatedSvgPainter。从祖先节点数重建次数是没用
// 的——setState 只会把自己的 element 标脏，祖先的 build 两种情况下都不会重跑。
Finder _svgCustomPaint() => find
    .descendant(
      of: find.byType(SvgxAnimated),
      matching: find.byType(CustomPaint),
    )
    .first;

/// Reads the timeline position the painter of [paint] is currently sampling.
///
/// 读取 [paint] 的绘制器当前采样的时间线位置。
Duration laterPainterClock(CustomPaint paint) =>
    (paint.painter! as AnimatedSvgPainter).clock.value;

void main() {
  setUp(SvgxDocumentCache.instance.clear);
  tearDown(SvgxDocumentCache.instance.clear);

  testWidgets('an animating Svgx does not rebuild while ticking', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Svgx.string(_spinner, width: 24, height: 24)),
    );

    final firstPaint = tester.widget<CustomPaint>(_svgCustomPaint());
    final firstPainter = firstPaint.painter! as AnimatedSvgPainter;
    final timeAtMount = firstPainter.clock.value;

    // Advance well past a full animation cycle, one frame at a time.
    // 一帧一帧地推进，越过整个动画周期。
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final laterPaint = tester.widget<CustomPaint>(_svgCustomPaint());

    expect(
      laterPainterClock(laterPaint),
      greaterThan(timeAtMount),
      reason: 'sanity: the ticker must actually have advanced the timeline',
    );
    expect(
      laterPaint,
      same(firstPaint),
      reason:
          'ticking must invalidate paint only — a per-tick setState would '
          'have produced a fresh CustomPaint every frame',
    );
    expect(
      laterPaint.painter,
      same(firstPainter),
      reason: 'the painter instance must survive too, for the same reason',
    );
  });

  testWidgets('an animating Svgx disposes cleanly while still ticking', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Svgx.string(_spinner, width: 24, height: 24)),
    );
    await tester.pump(const Duration(milliseconds: 16));

    // Removing the widget mid-animation must not trip "used after dispose" on
    // the clock notifier the RenderCustomPaint is listening to.
    // 动画进行中移除控件，不得让 RenderCustomPaint 正在监听的时钟 notifier 触发
    // "used after dispose"。
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 16));

    expect(tester.takeException(), isNull);
  });
}
