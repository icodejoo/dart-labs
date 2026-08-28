// Single-icon steady-state benchmark (`LIB=one_anim`): what ONE animated SVG
// icon costs per frame, with nothing to amortize it against.
//
// Why this exists alongside `anim_fps_bench_screen.dart`. That screen scrolls a
// grid of 1000 animated icons, and every optimization judged by it was judged
// on how well cost spreads across concurrent icons — frame skipping, mask
// batching, per-cell layer sharing. But a real app shows a navigation-bar
// glyph, a button affordance, a loading spinner: one to a few dozen animated
// icons, standing still. That is a different question with a different answer,
// for two concrete reasons:
//
//   1. `SvgxAnimationQuality.adaptiveFrameSkipping` only engages above
//      `frameSkipThreshold` (24) concurrent icons, so every count this screen
//      measures runs the exact, every-single-frame path. Nothing is degraded,
//      and nothing can be.
//   2. Per-frame cost that is invisible when divided across 1000 icons is the
//      entire cost when there is one.
//
// Only `repeatCount="indefinite"` documents are used, and this is the crux of
// the whole measurement rather than a detail: a FINITE animated icon has no
// steady state to measure. Once its last timeline settles, `SvgxAnimated`
// unsubscribes from the shared clock (see `_SvgxAnimatedState._onGlobalTick`)
// and the icon stops repainting altogether — its steady-state cost is exactly
// zero, and a benchmark that included one would be averaging a real cost with
// a structural zero. A looping icon is the only kind that keeps paying, and it
// is sampled here after its `fill="freeze"` reveals have frozen, which is the
// state such an icon spends nearly all of its on-screen life in.
//
// Design: the discriminating metric cannot be FPS. One icon holds 60fps on any
// device, so `real_fps` is saturated and blind. What is measured instead is
// `build`/`raster` duration per frame, swept over icon COUNTS (0, 1, 4, 16 —
// all below the degradation threshold). The count-0 phase is the pipeline floor
// (a trivially repainting `CustomPaint`, so frames keep being produced with no
// svgx in them at all); the slope across counts is the marginal per-icon cost,
// resolved far better than a single 1-icon phase could resolve it against
// frame-to-frame noise. Plain and masked corpora run as separate sweeps,
// because a `<mask>` is the one feature that makes a single icon expensive on
// the raster thread (two `saveLayer` offscreen render passes per frame, which
// at one icon nothing gates and nothing shares).
//
// 单图标稳态基准（`LIB=one_anim`）：**一个**动画 SVG 图标每帧要花多少成本，且没有
// 任何东西可以用来摊薄它。
//
// 为什么它要与 `anim_fps_bench_screen.dart` 并存。那个屏幕滚动的是 1000 个动画图标
// 的网格，凡是用它判定的优化，判的都是"成本在并发图标之间摊得好不好"——跳帧、mask
// 批处理、逐格图层共享。但真实应用显示的是导航栏字形、按钮态、loading spinner：
// 一个到几十个动画图标，静止不动。这是另一个问题、另一个答案，有两条具体理由：
//
//   1. `SvgxAnimationQuality.adaptiveFrameSkipping` 只在并发图标数超过
//      `frameSkipThreshold`（24）时才生效，因此本屏幕测的每一个数量都走精确的
//      逐帧路径。什么都没降级，也降级不了。
//   2. 摊到 1000 个图标上看不见的每帧成本，在只有一个图标时就是全部成本。
//
// 只使用 `repeatCount="indefinite"` 文档，而这是整个测量的关键、不是细节：**有限**
// 动画图标根本没有稳态可测。当它最后一条时间线定格后，`SvgxAnimated` 会从共享时钟
// 退订（见 `_SvgxAnimatedState._onGlobalTick`），图标彻底停止重绘——其稳态成本恰好
// 为零，把它算进来等于拿真实成本去和一个结构性的零求平均。只有循环图标会一直付费，
// 而这里是在它的 `fill="freeze"` 揭示动画定格之后采样的，那正是这类图标在屏幕上几乎
// 全部时间所处的状态。
//
// 设计：判别指标不能是 FPS。一个图标在任何设备上都能跑满 60fps，因此 `real_fps`
// 饱和、完全不敏感。改为测量每帧的 `build`/`raster` 耗时，并在图标**数量**上做扫描
// （0、1、4、16——全都低于降级阈值）。数量为 0 的阶段是管线底噪（一个只是不断重绘的
// `CustomPaint`，因此帧照样在产出，但里面完全没有 svgx）；跨数量的斜率就是边际单
// 图标成本，其分辨率远好于单独一个 1 图标阶段去对抗帧间噪声。普通语料与带 mask 语料
// 分成两趟扫描，因为 `<mask>` 是唯一能让**单个**图标在 raster 线程上变贵的特性
// （每帧两个 `saveLayer` 离屏渲染通道，而在一个图标时既没有门控、也没有共享）。

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:svgx/svgx.dart';

import 'anim_icons_real.dart';
import 'frame_timing.dart';
import 'report_sink.dart';

/// Icon counts swept per corpus, in phase order. Every value is below
/// [SvgxAnimationQuality.frameSkipThreshold] (24) so the exact per-frame path
/// runs throughout — see this file's header.
///
/// 每个语料所扫描的图标数量，按阶段顺序排列。每个值都低于
/// [SvgxAnimationQuality.frameSkipThreshold]（24），因此全程走精确逐帧路径——见本
/// 文件头部说明。
const List<int> _counts = <int>[0, 1, 4, 16];

/// Logical pixels per icon side. Kept at a realistic UI size (a toolbar glyph /
/// spinner), not blown up: the raster cost of a `saveLayer` is dominated by
/// per-pass fixed overhead rather than pixel count, and inflating the icon
/// would misattribute fill rate to layer overhead.
///
/// 每个图标边长的逻辑像素数。保持在真实 UI 尺寸（工具栏字形/spinner），不放大：
/// `saveLayer` 的 raster 成本主要由每通道的固定开销决定，而非像素数量，把图标放大
/// 会把填充率错记成图层开销。
const double _iconSize = 32;

/// Seconds each phase is measured for. / 每个阶段的测量时长（秒）。
const int _phaseSeconds = int.fromEnvironment('ONEHOLD', defaultValue: 5);

/// The looping (`repeatCount="indefinite"`) subset of the real corpus, split by
/// whether the document uses a `<mask>`.
///
/// Selected by substring rather than by re-parsing: this list is built once at
/// startup and only decides which sources go in which sweep, so a cheap sniff
/// is enough and keeps the benchmark independent of parser internals.
///
/// 真实语料中会循环（`repeatCount="indefinite"`）的子集，按文档是否使用 `<mask>`
/// 拆分。
///
/// 用子串而非重新解析来筛选：这个列表在启动时只构建一次，且只决定哪些源进入哪一趟
/// 扫描，因此廉价嗅探就够了，也让基准不依赖解析器内部实现。
final List<String> _loopingPlain = <String>[
  for (final src in animIconsReal)
    if (src.contains('indefinite') && !src.contains('<mask')) src,
];

/// Looping documents that DO use a `<mask>` — see [_loopingPlain].
///
/// 确实使用了 `<mask>` 的循环文档——见 [_loopingPlain]。
final List<String> _loopingMasked = <String>[
  for (final src in animIconsReal)
    if (src.contains('indefinite') && src.contains('<mask')) src,
];

/// One measured phase's outcome. / 一个测量阶段的结果。
class _PhaseResult {
  /// Creates a phase result. / 创建一个阶段结果。
  const _PhaseResult(this.label, this.count, this.collector);

  /// Phase name printed in the report. / 报告中打印的阶段名。
  final String label;

  /// Number of animated icons on screen during the phase.
  ///
  /// 该阶段屏幕上的动画图标数量。
  final int count;

  /// Timing samples gathered during the phase. / 该阶段采集到的计时样本。
  final FrameTimingCollector collector;
}

/// The single-icon steady-state benchmark screen. / 单图标稳态基准屏幕。
class OneAnimBenchScreen extends StatefulWidget {
  /// Creates the screen. / 创建屏幕。
  const OneAnimBenchScreen({super.key});

  @override
  State<OneAnimBenchScreen> createState() => _OneAnimBenchScreenState();
}

class _OneAnimBenchScreenState extends State<OneAnimBenchScreen>
    with SingleTickerProviderStateMixin {
  /// Sources currently mounted; empty for the count-0 floor phase.
  ///
  /// 当前挂载的源；数量为 0 的底噪阶段时为空。
  List<String> _mounted = const [];

  /// Label of the phase being measured, shown on screen for eyeball checks.
  ///
  /// 正在测量的阶段名，显示在屏幕上便于目视核对。
  String _phase = 'warmup';

  bool _done = false;

  /// Drives the count-0 floor phase: a ticker whose only job is to keep the
  /// pipeline producing frames when there is no animated icon to do it, so the
  /// floor is measured over real frames rather than over an idle app that
  /// produces none.
  ///
  /// 驱动数量为 0 的底噪阶段：一个 ticker，唯一职责是在没有任何动画图标时让管线继续
  /// 产出帧，使底噪是在真实帧上测出来的，而不是在一个根本不产帧的空闲应用上。
  late final Ticker _floorTicker;

  /// Repaint signal for the floor phase's placeholder painter.
  ///
  /// 底噪阶段占位绘制器的重绘信号。
  final ValueNotifier<int> _floorTick = ValueNotifier<int>(0);

  final List<_PhaseResult> _results = <_PhaseResult>[];

  @override
  void initState() {
    super.initState();
    _floorTicker = createTicker((_) => _floorTick.value++)..start();
    unawaited(_run());
  }

  @override
  void dispose() {
    _floorTicker.dispose();
    _floorTick.dispose();
    for (final result in _results) {
      result.collector.dispose();
    }
    super.dispose();
  }

  /// Mounts [count] distinct looping icons from [corpus] and lets the tree
  /// settle.
  ///
  /// Distinct sources, not one source repeated: repeating a source would share
  /// a single parsed document (see `SvgDocumentCache`) and therefore a single
  /// set of per-node paint caches across all instances, so instances 2..N would
  /// ride on the first one's cache fills and the measured slope would flatter
  /// the library. Distinct documents make each icon pay its own way, which is
  /// what a per-icon cost is supposed to mean.
  ///
  /// 从 [corpus] 挂载 [count] 个**互不相同**的循环图标，并等待控件树稳定。
  ///
  /// 用互异的源、而不是同一个源重复：重复同一个源会让所有实例共享同一份已解析文档
  /// （见 `SvgDocumentCache`），从而共享同一套逐节点绘制缓存，于是第 2..N 个实例会
  /// 蹭第一个实例填好的缓存，测出来的斜率会偏向对本库有利。互异文档让每个图标自己
  /// 付自己的账，而这才是"单图标成本"应有的含义。
  ///
  /// [corpus] — source list to draw from. / 取样的源列表。
  ///
  /// [count] — how many icons to mount. / 挂载多少个图标。
  Future<void> _mount(List<String> corpus, int count) async {
    setState(() {
      _mounted = <String>[
        for (var i = 0; i < count; i++) corpus[i % corpus.length],
      ];
    });
    // Let the icons mount, parse, and — critically — run past their
    // `fill="freeze"` reveals, so the phase measures the settled steady state
    // rather than the one-off reveal at the start of every timeline.
    //
    // 让图标完成挂载、解析，并且——这一点最关键——跑过它们的 `fill="freeze"` 揭示
    // 动画，使该阶段测的是已定格的稳态，而不是每条时间线开头那一次性的揭示。
    await Future<void>.delayed(const Duration(seconds: 3));
  }

  /// Measures one phase for [_phaseSeconds] and records the result.
  ///
  /// 测量一个阶段 [_phaseSeconds] 秒并记录结果。
  ///
  /// [label] — phase name. / 阶段名。
  ///
  /// [corpus] — source list. / 源列表。
  ///
  /// [count] — icon count. / 图标数量。
  Future<void> _measurePhase(
    String label,
    List<String> corpus,
    int count,
  ) async {
    setState(() => _phase = label);
    await _mount(corpus, count);
    final collector = FrameTimingCollector();
    // The engine's timing-report channel can take seconds to start firing after
    // a cold launch — see `FrameTimingCollector.hasReceivedAnyTiming`. Waiting
    // for it here keeps the first phase from reporting a spuriously tiny frame
    // count.
    //
    // 冷启动后引擎的帧上报通道可能要过几秒才开始触发——见
    // `FrameTimingCollector.hasReceivedAnyTiming`。在此等待可避免第一个阶段报出
    // 虚假的极小帧数。
    await warmUpFrameTimingChannel(collector, pumpFrames: false);
    collector.reset();
    collector.active = true;
    await Future<void>.delayed(Duration(seconds: _phaseSeconds));
    collector.active = false;
    _results.add(_PhaseResult(label, count, collector));
  }

  Future<void> _run() async {
    for (final count in _counts) {
      await _measurePhase('plain_n$count', _loopingPlain, count);
    }
    // The count-0 floor is corpus-independent, so it is measured once (above)
    // and not repeated for the masked sweep.
    //
    // 数量为 0 的底噪与语料无关，因此只在上面测一次，masked 那一趟不再重复。
    for (final count in _counts.where((c) => c != 0)) {
      await _measurePhase('mask_n$count', _loopingMasked, count);
    }
    _report();
  }

  void _report() {
    // One short message per phase: a single long report gets truncated by
    // logcat on Android, which silently eats the END marker every harness
    // script polls for. `anim_fps_bench_screen.dart` documents this trap at
    // length after it cost several wasted measurement sessions.
    //
    // 每个阶段一条短消息：单条过长的报告会被 Android 的 logcat 截断，从而静默吃掉
    // 所有 harness 脚本都在轮询的 END 标记。`anim_fps_bench_screen.dart` 在为此白费
    // 了数次测量之后详细记录了这个坑。
    for (final result in _results) {
      final c = result.collector;
      emitReport(
        '=== ONE ANIM PHASE ${result.label} ===\n'
        'phase=${result.label} count=${result.count} '
        'frames=${c.frameCount}\n'
        'phase=${result.label} real_fps='
        '${c.realAverageFps.toStringAsFixed(2)}\n'
        'phase=${result.label} build : ${c.buildStats}\n'
        'phase=${result.label} raster: ${c.rasterStats}\n'
        '=== END ONE ANIM PHASE ${result.label} ===\n',
      );
    }
    final buf = StringBuffer()
      ..writeln('=== ONE ANIM BENCH REPORT ===')
      ..writeln('icon_size=$_iconSize phase_seconds=$_phaseSeconds')
      ..writeln(
        'looping_plain=${_loopingPlain.length} '
        'looping_masked=${_loopingMasked.length}',
      );
    for (final result in _results) {
      final c = result.collector;
      buf.writeln(
        '${result.label} count=${result.count} '
        'frames=${c.frameCount} '
        'fps=${c.realAverageFps.toStringAsFixed(2)} '
        'build_avg_us=${c.buildStats.avgUs.toStringAsFixed(1)} '
        'raster_avg_us=${c.rasterStats.avgUs.toStringAsFixed(1)}',
      );
    }
    buf.writeln('=== END ONE ANIM BENCH REPORT ===');
    emitReport(buf.toString());
    setState(() => _done = true);
    if (autoExitAfterReport) exit(0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                _done ? 'done' : 'phase: $_phase (${_mounted.length} icons)',
                style: const TextStyle(fontSize: 14, color: Colors.black),
              ),
            ),
            Expanded(
              child: _mounted.isEmpty
                  // Floor phase: no svgx at all, just a painter that repaints
                  // every tick so the pipeline keeps producing frames to
                  // measure. Wrapped the same way an icon is, so the floor
                  // includes the same one `RepaintBoundary`.
                  //
                  // 底噪阶段：完全没有 svgx，只有一个每 tick 重绘的绘制器，让管线持续
                  // 产出可测量的帧。包装方式与图标一致，因此底噪里含有同样的一个
                  // `RepaintBoundary`。
                  ? RepaintBoundary(
                      child: CustomPaint(
                        size: const Size(_iconSize, _iconSize),
                        painter: _FloorPainter(_floorTick),
                      ),
                    )
                  : Wrap(
                      children: [
                        for (final src in _mounted)
                          SvgxAnimated.string(
                            src,
                            width: _iconSize,
                            height: _iconSize,
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Painter for the count-0 floor phase: repaints on every tick but draws a
/// single tiny rect, so the phase measures the framework/engine cost of
/// producing a frame with no svgx content in it.
///
/// 数量为 0 底噪阶段的绘制器：每 tick 重绘，但只画一个极小矩形，因此该阶段测的是
/// "产出一帧、其中没有任何 svgx 内容"的框架/引擎成本。
class _FloorPainter extends CustomPainter {
  /// Creates the painter, repainting whenever [tick] changes.
  ///
  /// 创建绘制器，[tick] 变化时重绘。
  _FloorPainter(this.tick) : super(repaint: tick);

  /// Repaint signal. / 重绘信号。
  final ValueListenable<int> tick;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 2, 2),
      Paint()..color = const Color(0xFF000000),
    );
  }

  @override
  bool shouldRepaint(_FloorPainter oldDelegate) => false;
}
