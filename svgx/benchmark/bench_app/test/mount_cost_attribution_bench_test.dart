// Host-side decomposition of what ONE animated icon cell costs, split into the
// steps a `GridView` re-mount actually runs. This is the build-phase
// counterpart to the raster-thread attribution the timeline already produced
// (`RenderPassGLES::EncodeCommandsInReactor`, ~221us per mask render pass):
// build had only ever been reported as one aggregate number, so there was no
// way to tell a necessary cost (a first-ever parse) from a redundant one (work
// repeated on every re-mount that a cache should already have covered).
//
// The five steps, in the order a re-mounting cell runs them:
//
//  1. `route_decision`   — `SvgX.build`'s `AnimationDetector.hasAnimations`.
//  2. `document_cold`    — `SvgDocumentCache` miss: full XML parse + timeline
//                          build. Paid once per distinct source, ever.
//  3. `document_warm`    — the same call on a hit. Paid on every re-mount.
//  4. `mount_and_layout` — inflating the cell's widgets into elements, creating
//                          and attaching their render objects, laying out, and
//                          recording the first paint.
//  5. `paint_steady`     — re-recording an already-mounted icon at a new
//                          timeline position, i.e. the per-frame cost.
//
// What the split is for: (4) minus (5) is the part of a re-mount that exists
// only because the cell was destroyed and rebuilt, and (3) versus (2) is what
// the document cache is worth. Both are the numbers a "which build cost is
// redundant" list needs.
//
// Deliberate limits, stated rather than glossed over: this measures Dart CPU on
// a desktop host with no GPU in the loop and no scroll physics, so absolute
// microseconds do not transfer to a phone — the ratios between the five steps
// are what transfers. Real-device numbers still come from
// `LIB=anim_fps` plus `tool/capture_timeline.dart`.
//
// 主机侧分解：一个动画图标格子到底花多少，按 `GridView` 重挂载实际会跑的步骤拆开。
// 这是 build 阶段版的归因，对应 timeline 已经给出的 raster 线程归因（
// `RenderPassGLES::EncodeCommandsInReactor`，每个 mask 渲染通道约 221us）：build
// 此前只有一个聚合数字，因此无法把必要成本（某个源的首次解析）与冗余成本（每次
// 重挂载都重做、而缓存本应已经覆盖的工作）区分开。
//
// 五个步骤，按重挂载格子的执行顺序：
//
//  1. `route_decision`   —— `SvgX.build` 里的 `AnimationDetector.hasAnimations`。
//  2. `document_cold`    —— `SvgDocumentCache` 未命中：完整 XML 解析 + 时间线构建。
//                            每个互异源一生只付一次。
//  3. `document_warm`    —— 同一调用在命中时的开销。每次重挂载都要付。
//  4. `mount_and_layout` —— 把格子的控件 inflate 成 element、创建并 attach 其渲染
//                            对象、布局，以及录制首帧绘制。
//  5. `paint_steady`     —— 把已挂载的图标在新的时间线位置重新录制一遍，即逐帧成本。
//
// 这个拆分的用途：(4) 减 (5) 是重挂载里"仅因为格子被销毁重建才存在"的那部分，
// (3) 对比 (2) 则是文档缓存的价值。这两个都是"哪些 build 成本是冗余的"清单所需的
// 数字。
//
// 刻意说明而非掩盖的局限：本测试测的是桌面主机上的 Dart CPU，链路里没有 GPU、没有
// 滚动物理，因此绝对微秒数无法迁移到手机上——能迁移的是五个步骤之间的比例。真机
// 数字仍然来自 `LIB=anim_fps` 加 `tool/capture_timeline.dart`。

import 'dart:ui' as ui;

import 'package:bench_app/anim_icons_real.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/animated_svg_painter.dart';
import 'package:svgx/src/animation/animation_detector.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';
import 'package:svgx/src/animation/svg_dom.dart';
import 'package:svgx/svgx.dart';

/// Icons mounted per measured window — one screenful-plus of the acceptance
/// grid rather than all 399, because a re-mount only ever churns the cells
/// crossing the viewport.
///
/// 每个测量窗口挂载的图标数——取验收网格"一屏多一点"的量而不是全部 399 个，因为
/// 重挂载churn的永远只是穿越视口的那些格子。
const int _mountedIcons = 48;

/// Timed passes per step; the minimum is reported (noise only adds time).
///
/// 每个步骤的计时轮次；报告最小值（噪声只会增加耗时）。
const int _trials = 7;

/// Runs [body] [warmups] times untimed then [_trials] times timed, and returns
/// the fastest pass in microseconds per unit of work.
///
/// 先不计时地跑 [body] [warmups] 次，再计时跑 [_trials] 次，返回最快一轮的单位
/// 工作耗时（微秒）。
///
/// [units] — work units per pass, so the result is per-icon.
///
///   每轮的工作单元数，使结果是"每图标"口径。
double _minPerUnitUs(int units, void Function() body, {int warmups = 2}) {
  for (var i = 0; i < warmups; i++) {
    body();
  }
  var best = double.infinity;
  for (var i = 0; i < _trials; i++) {
    final stopwatch = Stopwatch()..start();
    body();
    stopwatch.stop();
    final perUnit = stopwatch.elapsedMicroseconds / units;
    if (perUnit < best) best = perUnit;
  }
  return best;
}

void main() {
  testWidgets('per-icon build-phase cost, step by step', (tester) async {
    final sources = animIconsReal;
    final cache = SvgDocumentCache.instance..maximumSize = sources.length + 50;
    final report = <String, double>{};

    // 1. Route decision. Memoized, so this is the steady-state cost after the
    //    first appearance of each source — which is what a scrolling grid pays.
    // 1. 路由判定。带 memo，因此这里测的是每个源首次出现之后的稳态成本——也正是
    //    滚动网格实际付的。
    for (final source in sources) {
      AnimationDetector.hasAnimations(source);
    }
    report['route_decision'] = _minPerUnitUs(sources.length, () {
      var hits = 0;
      for (final source in sources) {
        if (AnimationDetector.hasAnimations(source)) hits++;
      }
      if (hits < 0) throw StateError('unreachable');
    });

    // 2. Cold document: parse + timeline build, bypassing the cache so the
    //    measurement is the miss cost itself.
    // 2. 冷文档：解析 + 时间线构建，绕开缓存，使测量结果就是未命中成本本身。
    report['document_cold'] = _minPerUnitUs(sources.length, () {
      for (final source in sources) {
        parseAnimatedSvgDocument(source);
      }
    }, warmups: 1);

    // 3. Warm document: the same call a re-mount makes.
    // 3. 热文档：重挂载实际发起的同一个调用。
    for (final source in sources) {
      cache.getOrParse(source);
    }
    report['document_warm'] = _minPerUnitUs(sources.length, () {
      for (final source in sources) {
        cache.getOrParse(source);
      }
    });

    // 4. Mount + layout + first paint of a screenful, from nothing. Measured
    //    by pumping an empty tree and then the populated one, so each timed
    //    pass includes exactly one full mount (and the preceding unmount).
    //    The document cache is warm, so no parse is included.
    // 4. 从零挂载一屏 + 布局 + 首帧绘制。做法是先 pump 空树再 pump 满树，使每个计时
    //    轮恰好包含一次完整挂载（以及它前面的卸载）。文档缓存已预热，因此不含解析。
    final mountedSources = sources.take(_mountedIcons).toList();

    /// Builds a screenful of icons, optionally with the redundant sizing layer
    /// that `SvgXAnimated` used to wrap its `CustomPaint` in reintroduced.
    ///
    /// 构建一屏图标，可选地重新引入 `SvgXAnimated` 此前套在 `CustomPaint` 外面的那层
    /// 冗余定尺寸层。
    ///
    /// [extraSizingLayer] — true adds one `SizedBox` (hence one
    ///   `RenderConstrainedBox`) per icon.
    ///
    ///   为 true 时每个图标多一个 `SizedBox`（即多一个 `RenderConstrainedBox`）。
    ///
    /// Returns the widget to pump. / 返回待 pump 的控件。
    Widget screenful({required bool extraSizingLayer}) => Directionality(
      textDirection: TextDirection.ltr,
      child: Wrap(
        children: [
          for (final source in mountedSources)
            if (extraSizingLayer)
              SizedBox(
                width: 32,
                height: 32,
                child: SvgX.string(source, width: 32, height: 32),
              )
            else
              SvgX.string(source, width: 32, height: 32),
        ],
      ),
    );

    /// Times one full mount of [widget] from an empty tree, repeatedly, and
    /// returns the fastest pass in microseconds per icon.
    ///
    /// `runAsync` is not used: everything measured here is synchronous
    /// framework work, and a `pumpWidget` inside the stopwatch window is what
    /// actually runs the build + layout + first paint recording.
    ///
    /// 反复从空树完整挂载 [widget] 并计时，返回最快一轮的单图标耗时（微秒）。
    ///
    /// 不用 `runAsync`：这里测的全是同步框架工作，而把 `pumpWidget` 放进秒表窗口里，
    /// 跑的正是 build + 布局 + 首帧绘制录制。
    Future<double> timeMount(Widget widget) async {
      var best = double.infinity;
      for (var i = 0; i < _trials + 2; i++) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 16));
        final stopwatch = Stopwatch()..start();
        await tester.pumpWidget(widget);
        stopwatch.stop();
        if (i < 2) continue; // warmup passes / 预热轮
        final perUnit = stopwatch.elapsedMicroseconds / _mountedIcons;
        if (perUnit < best) best = perUnit;
      }
      return best;
    }

    // The ORDER WITHIN each round flips, not just the pairing. An earlier
    // version ran (flat, wrapped) twice, which looks alternating but leaves the
    // wrapped arm always running second — i.e. always on a warmer VM. It
    // reproducibly reported the extra layer as ~10us/icon *cheaper*, which is
    // not a possible result and was purely that ordering artifact. Flipping the
    // order every round makes the warmup gradient push the two arms in opposite
    // directions between rounds instead of consistently favouring one.
    //
    // 交替的是**每一轮内部的顺序**，而不只是配对方式。早先的版本跑了两次
    // (flat, wrapped)，看起来是交替，实际上 wrapped 臂永远排第二——也就是永远在更热的
    // VM 上跑。它可复现地报出"多一层反而每图标便宜约 10us"，这不是一个可能成立的
    // 结果，纯粹是那个顺序造成的假象。每轮翻转顺序后，预热梯度会在不同轮之间把两臂
    // 推向相反方向，而不是恒定偏袒其中一个。
    final flat = <double>[];
    final wrapped = <double>[];
    for (var round = 0; round < 4; round++) {
      if (round.isEven) {
        flat.add(await timeMount(screenful(extraSizingLayer: false)));
        wrapped.add(await timeMount(screenful(extraSizingLayer: true)));
      } else {
        wrapped.add(await timeMount(screenful(extraSizingLayer: true)));
        flat.add(await timeMount(screenful(extraSizingLayer: false)));
      }
    }
    report['mount_and_layout'] = flat.reduce((a, b) => a < b ? a : b);
    report['mount_plus_1_layer'] = wrapped.reduce((a, b) => a < b ? a : b);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 16));

    // 5. Steady-state paint: re-recording an already-mounted icon at a fresh
    //    timeline position. Driven through the painter directly rather than
    //    through a pump, so the number is the icon's own recording cost with no
    //    framework traversal folded in — which is exactly what makes it
    //    subtractable from step 4.
    // 5. 稳态绘制：把已挂载的图标在新的时间线位置重新录制。直接驱动 painter 而不是走
    //    pump，使这个数字是图标自身的录制成本、不掺入框架遍历——正因如此它才可以从
    //    步骤 4 里减出去。
    final documents = [
      for (final source in mountedSources) cache.getOrParse(source).document,
    ];
    const theme = SvgTheme();
    final clock = ValueNotifier<Duration>(Duration.zero);
    var frame = 0;
    report['paint_steady'] = _minPerUnitUs(documents.length, () {
      frame++;
      clock.value = Duration(milliseconds: 16 * frame);
      for (final document in documents) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        AnimatedSvgPainter(
          root: document.root,
          intrinsicSize: Size(document.width, document.height),
          clock: clock,
          theme: theme,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          gradients: document.gradients,
          clipPaths: document.clipPaths,
          masks: document.masks,
        ).paint(canvas, const Size(32, 32));
        recorder.endRecording().dispose();
      }
    }, warmups: 3);
    clock.dispose();

    final buffer = StringBuffer()
      ..writeln('=== PER-ICON BUILD-PHASE COST (host, min of $_trials) ===');
    for (final entry in report.entries) {
      buffer.writeln(
        '${entry.key.padRight(20)} ${entry.value.toStringAsFixed(2).padLeft(9)} us/icon',
      );
    }
    buffer
      ..writeln(
        'mount_minus_paint    '
        '${(report['mount_and_layout']! - report['paint_steady']!).toStringAsFixed(2).padLeft(9)} us/icon'
        '  <- framework-only remount overhead / 纯框架重挂载开销',
      )
      ..writeln(
        'one_layer_cost       '
        '${(report['mount_plus_1_layer']! - report['mount_and_layout']!).toStringAsFixed(2).padLeft(9)} us/icon'
        '  <- cost of ONE extra widget layer at mount / 挂载时多一层控件的代价',
      )
      ..writeln('=== END PER-ICON BUILD-PHASE COST ===');
    // ignore: avoid_print
    print(buffer);

    // The assertions are the invariants the cost list depends on, not timing
    // thresholds: a warm document lookup must be far cheaper than a cold parse
    // (otherwise the cache is not doing its job), and every step must have
    // produced a real measurement.
    //
    // 断言的是成本清单所依赖的不变量，而非时间阈值：热文档查找必须远比冷解析便宜
    // （否则缓存就没起作用），且每个步骤都必须产出了真实测量值。
    expect(report['document_warm'], lessThan(report['document_cold']! / 10));
    for (final entry in report.entries) {
      expect(entry.value.isFinite, isTrue, reason: entry.key);
    }
  }, timeout: const Timeout(Duration(minutes: 10)));

  // Answers the "flatten the per-frame tree walk into a pre-baked draw list"
  // suspicion structurally, with counts rather than timings: how many nodes
  // `_paintNode` actually recurses over per icon, how deep the tree is, and how
  // many of those nodes carry an `<animate>` (a node whose values move cannot
  // be pre-baked at all).
  //
  // Counts, not durations, on purpose. A timed frozen-clock-versus-advancing-
  // clock split was tried first and thrown away as unsound: the two arms cannot
  // be made comparable, because a fixed clock position lands on one particular
  // dash phase (which decides how many segments `dashPath` emits) rather than
  // the average of the sweep, and whichever arm runs second gets a warmer VM.
  // It duly reported the frozen arm as *slower* than the advancing one — a
  // physically impossible result, and a good reminder that a number is only
  // evidence once its confounds are ruled out. The counts below have no such
  // problem: they are exact.
  //
  // 用结构性的计数而不是计时，来回答"把逐帧树遍历扁平化成预先烘好的绘制指令列表"这个
  // 怀疑：`_paintNode` 每个图标实际递归多少个节点、树有多深、其中多少节点带
  // `<animate>`（值在动的节点根本无法预先烘）。
  //
  // 刻意用计数而非耗时。一开始尝试过"冻结时钟 vs 推进时钟"的计时拆分，后来作为不可靠
  // 方法丢弃了：两臂无法做到可比，因为固定的时钟位置落在某一个特定的虚线相位上（它决定
  // `dashPath` 产出多少段），而不是整段扫描的平均值；而且后跑的那一臂 VM 更热。它果然
  // 报出冻结臂比推进臂**更慢**——一个物理上不可能的结果，也很好地提醒了：一个数字只有
  // 在排除掉混淆因素之后才算证据。下面的计数没有这个问题：它们是精确的。
  test('paint-walk size over the real corpus', () {
    final documents = [
      for (final source in animIconsReal) parseAnimatedSvgDocument(source),
    ];

    var totalNodes = 0;
    var animatedNodes = 0;
    var maxDepth = 0;
    var maxNodesInOneIcon = 0;
    void walk(SvgNode node, int depth, void Function() countIcon) {
      totalNodes++;
      countIcon();
      if (node.animations.isNotEmpty) animatedNodes++;
      if (depth > maxDepth) maxDepth = depth;
      for (final child in node.children) {
        walk(child, depth + 1, countIcon);
      }
    }

    for (final document in documents) {
      var perIcon = 0;
      walk(document.root, 1, () => perIcon++);
      if (perIcon > maxNodesInOneIcon) maxNodesInOneIcon = perIcon;
    }

    // ignore: avoid_print
    print(
      '=== PAINT WALK SURVEY (${documents.length} real SMIL icons) ===\n'
      'nodes_total=$totalNodes '
      'nodes_per_icon_avg=${(totalNodes / documents.length).toStringAsFixed(1)} '
      'nodes_per_icon_max=$maxNodesInOneIcon\n'
      'animated_nodes=$animatedNodes '
      '(${(100 * animatedNodes / totalNodes).toStringAsFixed(1)}% of all nodes)\n'
      'max_tree_depth=$maxDepth\n'
      '=== END PAINT WALK SURVEY ===',
    );

    expect(totalNodes, greaterThan(0));
  });
}
