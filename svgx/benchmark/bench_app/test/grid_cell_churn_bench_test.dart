// Host-side paired A/B for what ONE redundant per-icon sizing layer costs in
// the `LIB=anim_fps ITEMS=1000` scenario's dominant cost driver: `GridView`
// mounting and unmounting cells as they cross the viewport.
//
// Why this shape of measurement. The build phase of that benchmark had never
// been decomposed, and the leading structural suspicion was widget-tree depth
// per cell — every layer is an `Element` to inflate, a `RenderObject` to
// create and attach, a node to lay out, and a node to walk on paint, once per
// cell per appearance. `SvgxAnimated`/`SvgxStatic` used to wrap their childless
// `CustomPaint` in a `SizedBox` of identical dimensions, which
// `RenderCustomPaint.computeSizeForNoChild` already made redundant. This test
// measures the removal by reproducing the removed layer as an explicit
// `SizedBox` in the second arm, so both arms run in the SAME process against
// the same warm document cache and the difference is exactly one
// `RenderConstrainedBox` per cell.
//
// Arms alternate (A,B,A,B,...) so a monotonic drift over the test's lifetime
// pushes them in opposite directions instead of always favouring the first —
// the same reasoning `anim_fps_bench_screen.dart`'s `ARMFLIP` applies on
// device.
//
// This is a host measurement of Dart CPU in build+layout+paint-recording. It
// does not and cannot speak for GPU raster cost; the device run has the last
// word on end-to-end numbers.
//
// 主机侧配对 A/B，量化"每个图标多一层冗余定尺寸层"在 `LIB=anim_fps ITEMS=1000`
// 场景主要成本来源上的代价：`GridView` 在格子穿越视口时的挂载与卸载。
//
// 为什么用这种测量形状。该基准的 build 阶段此前从未被拆解，而首要的结构性怀疑就是
// 每格的控件树深度——每一层都意味着一个要 inflate 的 `Element`、一个要创建并
// attach 的 `RenderObject`、一个要布局的节点、一个绘制时要遍历的节点，且每格每次
// 出现都要付一次。`SvgxAnimated`/`SvgxStatic` 此前把无 child 的 `CustomPaint` 套在
// 同尺寸的 `SizedBox` 里，而 `RenderCustomPaint.computeSizeForNoChild` 早已让这层
// 成为冗余。本测试通过在第二臂里用显式 `SizedBox` 复现被移除的那一层来测量它，
// 于是两臂在**同一进程**、同一份预热文档缓存上运行，差异恰好是每格一个
// `RenderConstrainedBox`。
//
// 两臂交替（A,B,A,B,...），使测试生命周期内的单调漂移把两臂推向相反方向，而不是
// 恒定偏向先跑的那一臂——与 `anim_fps_bench_screen.dart` 的 `ARMFLIP` 在真机上
// 采用的是同一套理由。
//
// 这是对 build+layout+绘制录制阶段 Dart CPU 的主机侧测量。它不能、也不代表 GPU
// raster 开销；端到端数字仍以真机运行为准。

import 'package:bench_app/anim_icons_real.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/svgx.dart';

/// Cells in the simulated grid, matching the acceptance scenario's item count.
///
/// 模拟网格的格子数，与验收场景的条目数一致。
const int _itemCount = 1000;

/// Grid columns, matching `anim_fps_bench_screen.dart`.
///
/// 网格列数，与 `anim_fps_bench_screen.dart` 一致。
const int _columns = 8;

void main() {
  testWidgets('one redundant sizing layer per cell, scrolling 1000 icons', (
    tester,
  ) async {
    final sources = <String>[
      for (var i = 0; i < _itemCount; i++)
        animIconsReal[i % animIconsReal.length],
    ];

    // Parse every distinct source up front so neither arm pays a cold parse:
    // the thing under measurement is the widget/render layer, not the XML
    // parser, and a cold miss costs ~44us against a ~0.1us hit (see
    // `SvgDocumentCache`), which would swamp everything else.
    //
    // 先把所有互异源解析好，使两臂都不付冷解析成本：被测的是控件/渲染层，不是 XML
    // 解析器，而一次冷未命中约 44us、命中约 0.1us（见 `SvgDocumentCache`），会把其它
    // 一切都盖掉。
    SvgDocumentCache.instance.maximumSize = animIconsReal.length + 50;
    for (final source in animIconsReal) {
      SvgDocumentCache.instance.getOrParse(source);
    }

    /// Builds the grid for one arm.
    ///
    /// 构建某一臂的网格。
    ///
    /// [controller] — scroll controller driven by the measurement loop.
    ///
    ///   由测量循环驱动的滚动控制器。
    ///
    /// [extraSizingLayer] — when true, reintroduces the removed `SizedBox`
    ///   wrapper so this arm carries one extra `RenderConstrainedBox` per cell.
    ///
    ///   为 true 时重新引入被移除的 `SizedBox` 包装，使该臂每格多带一个
    ///   `RenderConstrainedBox`。
    ///
    /// Returns the grid widget. / 返回网格控件。
    Widget buildGrid(
      ScrollController controller, {
      required bool extraSizingLayer,
    }) => Directionality(
      textDirection: TextDirection.ltr,
      child: GridView.builder(
        controller: controller,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _columns,
        ),
        itemCount: sources.length,
        itemBuilder: (context, index) {
          final Widget icon = Svgx.string(
            sources[index],
            width: 32,
            height: 32,
          );
          return Padding(
            padding: const EdgeInsets.all(4),
            child: extraSizingLayer
                ? SizedBox(width: 32, height: 32, child: icon)
                : icon,
          );
        },
      ),
    );

    /// Runs one measurement window: mounts the grid, scrolls it down and back
    /// up in [steps] jumps per leg, and returns the wall microseconds spent
    /// inside the pumps that follow each jump — i.e. the framework's
    /// build + layout + paint-recording work for the cells that churned.
    ///
    /// 跑一个测量窗口：挂载网格，每程分 [steps] 次跳跃地上下滚一遍，返回每次跳跃
    /// 之后 pump 内部消耗的挂钟微秒数——也就是框架为发生churn的格子所做的
    /// build + 布局 + 绘制录制的工作量。
    ///
    /// [extraSizingLayer] — see [buildGrid]. / 见 [buildGrid]。
    ///
    /// [steps] — scroll jumps per leg. / 每程的滚动跳跃次数。
    ///
    /// Returns elapsed microseconds. / 返回耗时（微秒）。
    Future<int> measure({
      required bool extraSizingLayer,
      int steps = 40,
    }) async {
      final controller = ScrollController();
      await tester.pumpWidget(
        buildGrid(controller, extraSizingLayer: extraSizingLayer),
      );
      await tester.pump(const Duration(milliseconds: 16));
      final maxExtent = controller.position.maxScrollExtent;
      final stopwatch = Stopwatch();
      for (final direction in [1, -1]) {
        for (var step = 1; step <= steps; step++) {
          final progress = direction == 1 ? step / steps : 1 - step / steps;
          controller.jumpTo(maxExtent * progress);
          stopwatch.start();
          await tester.pump(const Duration(milliseconds: 16));
          stopwatch.stop();
        }
      }
      // Unmount so this arm's 1000 subscriptions leave the shared clock before
      // the next arm mounts its own — otherwise the second arm would run at
      // double concurrency and its frame-divisor gating would differ.
      //
      // 卸载，使本臂的 1000 个订阅在下一臂挂载之前离开共享时钟——否则第二臂会在双倍
      // 并发下运行，其帧除数门控也就不同了。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 16));
      controller.dispose();
      return stopwatch.elapsedMicroseconds;
    }

    // Warm the whole pipeline once, untimed: first mount pays JIT/AOT warmup,
    // per-node style and geometry cache fills, and the icons' first path
    // parses.
    //
    // 先不计时地把整条管线预热一次：首次挂载要付 JIT/AOT 预热、逐节点样式与几何缓存
    // 填充，以及图标的首次路径解析。
    await measure(extraSizingLayer: false, steps: 8);
    await measure(extraSizingLayer: true, steps: 8);

    // The ORDER WITHIN each round flips. Running (flat, wrapped) repeatedly
    // looks alternating but leaves the wrapped arm always second, i.e. always
    // on a warmer VM — which reproducibly reported the extra layer as *cheaper*,
    // an impossible result that was purely the ordering artifact. Flipping every
    // round makes the warmup gradient favour opposite arms in opposite rounds.
    //
    // 交替的是**每一轮内部的顺序**。反复跑 (flat, wrapped) 看着像交替，实际上 wrapped
    // 臂永远排第二、永远在更热的 VM 上——那样会可复现地报出"多一层反而更便宜"，一个不
    // 可能成立的结果，纯粹是顺序造成的假象。每轮翻转顺序，能让预热梯度在不同轮里偏袒
    // 相反的臂。
    final flat = <int>[];
    final wrapped = <int>[];
    for (var round = 0; round < 6; round++) {
      if (round.isEven) {
        flat.add(await measure(extraSizingLayer: false));
        wrapped.add(await measure(extraSizingLayer: true));
      } else {
        wrapped.add(await measure(extraSizingLayer: true));
        flat.add(await measure(extraSizingLayer: false));
      }
    }

    int best(List<int> xs) => xs.reduce((a, b) => a < b ? a : b);
    final flatMin = best(flat);
    final wrappedMin = best(wrapped);
    // MIN across rounds, for the reason `micro_bench.dart` documents: noise
    // only ever adds time, so the minimum is the closest observation to the
    // true CPU cost.
    //
    // 取多轮最小值，理由与 `micro_bench.dart` 记录的一致：噪声只会增加耗时，因此
    // 最小值最接近真实 CPU 成本。
    // ignore: avoid_print
    print(
      '=== GRID CELL CHURN A/B (items=$_itemCount, 80 scroll steps/window) ===\n'
      'flat    (shipped)          min=${(flatMin / 1000).toStringAsFixed(1)}ms '
      'rounds=${flat.map((x) => (x / 1000).toStringAsFixed(1)).join('/')}\n'
      'wrapped (+1 SizedBox/cell) min=${(wrappedMin / 1000).toStringAsFixed(1)}ms '
      'rounds=${wrapped.map((x) => (x / 1000).toStringAsFixed(1)).join('/')}\n'
      'delta=${((wrappedMin - flatMin) / 1000).toStringAsFixed(1)}ms '
      '(${(100 * (wrappedMin - flatMin) / flatMin).toStringAsFixed(1)}% of flat)\n'
      '=== END GRID CELL CHURN A/B ===',
    );

    // No threshold assertion: the point is the printed number, and asserting a
    // timing ratio on a shared CI/dev machine would make this test flaky
    // without making the measurement any more true.
    //
    // 不做阈值断言：本测试的价值在于打印出来的数字，而在共用的 CI/开发机上断言时间
    // 比例只会让测试变得不稳定，并不会让测量更真实。
    expect(flatMin, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 10)));
}
