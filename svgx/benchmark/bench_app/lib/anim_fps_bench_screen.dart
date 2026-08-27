// New performance-acceptance test case (added per explicit user request,
// 2026-08-25): 1000 concurrently-playing SMIL-animated icons, scrolled back
// and forth like the static 1000-icon benchmark, measuring REAL FPS — the
// actual rate of frames handed to the GPU (via
// FrameTiming.timestampInMicroseconds(FramePhase.rasterFinish)), not an
// estimate derived from build/raster duration averages and not a fixed
// assumed value.
//
// 新增性能验收用例（应用户明确要求新增，2026-08-25）：1000 个并发播放的 SMIL
// 动画图标，像静态千图标基准一样来回滚动，测量真实 FPS —— 引擎实际交给 GPU 的
// 帧率（取自 FrameTiming.timestampInMicroseconds(FramePhase.rasterFinish)），
// 不是从 build/raster 耗时均值推算的估计值，也不是固定假设值。

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:svgx/svgx.dart';

import 'anim_icon_gen.dart';
import 'frame_timing.dart';
import 'report_sink.dart';
import 'stats.dart';

/// Immutable snapshot of a completed [AnimFpsBenchRunner] phase, used by the
/// sequential `LIB=compare` mode to fold this svgx-only real-FPS test into
/// the consolidated report.
///
/// 一次已完成的 [AnimFpsBenchRunner] 阶段结果快照，供顺序 `LIB=compare` 模式
/// 把这个仅测 svgx 的真实 FPS 用例折进汇总报告。
///
/// Example:
/// ```dart
/// AnimFpsBenchRunner(itemCount: 1000, cycles: 6, onComplete: (r) => print(r.realFps));
/// ```
class AnimFpsBenchResult {
  /// Creates a result snapshot. / 创建结果快照。
  const AnimFpsBenchResult({
    required this.frameCount,
    required this.realFps,
    required this.build,
    required this.raster,
    required this.framesOver16_6,
    required this.framesOver8_3,
  });

  /// Total frames observed during the scroll window. / 滚动窗口内的总帧数。
  final int frameCount;

  /// Real measured average FPS (see [FrameTimingCollector.realAverageFps]).
  ///
  /// 实测平均 FPS（见 [FrameTimingCollector.realAverageFps]）。
  final double realFps;

  /// Build duration stats. / build 耗时统计。
  final DurationStats build;

  /// Raster duration stats. / raster 耗时统计。
  final DurationStats raster;

  /// Frames whose build exceeded 16.6ms. / build 超过 16.6ms 的帧数。
  final int framesOver16_6;

  /// Frames whose build exceeded 8.3ms. / build 超过 8.3ms 的帧数。
  final int framesOver8_3;
}

/// Runs the 1000-animated-icon benchmark and prints a report with real
/// measured FPS to stdout.
///
/// Two modes, because they measure different things:
///  - **scrolling** ([cycles] > 0): the acceptance scenario. Its `build` time
///    is dominated by `GridView` mounting and unmounting cells as they cross
///    the viewport, which swamps the per-frame animation cost.
///  - **holding still** ([cycles] == 0): no scrolling at all, so no cell
///    churn — `build` time is then purely what the visible icons' tickers cost
///    per frame. This is the only mode that can see a change to the per-frame
///    driving path (e.g. rebuild-per-tick vs repaint-per-tick).
///
/// 跑 1000 个动画图标的基准，把包含实测 FPS 的报告打印到 stdout。
///
/// 两种模式，因为它们测的是不同的东西：
///  - **滚动**（[cycles] > 0）：验收场景。它的 `build` 耗时由 `GridView` 在格子
///    进出视口时的挂载/卸载主导，会把逐帧动画开销完全盖住。
///  - **静止**（[cycles] == 0）：完全不滚动，因此没有格子进出——此时 `build`
///    耗时就纯粹是可见图标的 ticker 每帧的开销。这是唯一能看见"逐帧驱动路径"
///    改动（例如每 tick 重建 vs 每 tick 重绘）的模式。
class AnimFpsBenchRunner extends StatefulWidget {
  /// Creates the runner for the given icon count and cycle count.
  ///
  /// 创建指定图标数与滚动轮次数的基准运行器。
  const AnimFpsBenchRunner({
    super.key,
    required this.itemCount,
    required this.cycles,
    this.holdSeconds = 6,
    this.onComplete,
  });

  /// Number of concurrently animating icons in the grid. / 网格中并发播放动画的图标数。
  final int itemCount;

  /// Number of full up-down scroll cycles, or 0 to hold the grid still for
  /// [holdSeconds] instead of scrolling.
  ///
  /// 上下滚动的完整轮次数；为 0 时不滚动，改为让网格静止 [holdSeconds] 秒。
  final int cycles;

  /// Observation window for the no-scroll mode (`cycles == 0`).
  ///
  /// 不滚动模式（`cycles == 0`）的观测时长。
  final int holdSeconds;

  /// Called with the final [AnimFpsBenchResult] once the run finishes, in
  /// addition to the usual stdout report. Null in standalone `LIB=anim_fps`
  /// runs (behavior unchanged).
  ///
  /// 运行结束后携带最终 [AnimFpsBenchResult] 回调，是常规 stdout 报告之外的
  /// 补充。独立 `LIB=anim_fps` 运行时为 null（行为不变）。
  final ValueChanged<AnimFpsBenchResult>? onComplete;

  @override
  State<AnimFpsBenchRunner> createState() => _AnimFpsBenchRunnerState();
}

// Both knobs are read as strings and compared against '1'/'true', not through
// `bool.fromEnvironment` — that accepts *only* the exact strings "true"/"false",
// so `--dart-define=QUALITYAB=1` silently evaluates to false. `report_sink.dart`
// already documents this trap costing a wasted benchmark round for AUTOEXIT;
// it cost another one here (the first three-arm run silently degraded to a
// single arm, and the report simply had no `arm=` lines) before the same fix
// was applied. Accept both spellings so the trap cannot fire a third time.
//
// 这两个旋钮都是按字符串读取并与 '1'/'true' 比较，而不是走 `bool.fromEnvironment`
// ——后者**只**接受 "true"/"false" 两个精确字符串，因此 `--dart-define=QUALITYAB=1`
// 会静默求值为 false。`report_sink.dart` 已经记录过这个坑让 AUTOEXIT 白跑了一轮；
// 这里又白跑了一轮（第一次三臂运行静默退化成了单臂，报告里根本没有 `arm=` 行），
// 之后才用同样的办法修掉。两种写法都接受，让这个坑不会有第三次。
const String _qualityAbRaw = String.fromEnvironment('QUALITYAB');
const bool _qualityAb = _qualityAbRaw == '1' || _qualityAbRaw == 'true';
const String _armFlipRaw = String.fromEnvironment('ARMFLIP');
const bool _armFlip = _armFlipRaw == '1' || _armFlipRaw == 'true';

class _AnimFpsBenchRunnerState extends State<AnimFpsBenchRunner> {
  late final List<String> _icons = generateAnimIcons(widget.itemCount);
  final _scrollController = ScrollController();
  final _frameTiming = FrameTimingCollector();
  bool _done = false;
  bool _gridMounted = true;
  String _status = 'warming up...';

  // The `SvgXAnimationQuality` arms measured in this one process, in run
  // order. `QUALITYAB=1` measures the no-degradation control, then each
  // degradation layered on, back to back inside a single launch; otherwise
  // just one arm runs, exactly as before.
  //
  // Why every arm lives in one process: the animated degradation can only be
  // credited (or blamed) by comparing against a control measured under the
  // same thermal state, on the same binary. `--dart-define` is compile-time,
  // so a runtime switch is the only way to get two arms out of one build —
  // and it works precisely because `_SharedAnimationClock` re-reads the
  // quality profile every tick, so flipping the global default retunes the
  // 1000 already-mounted icons on the next frame with no remount.
  //
  // 本进程内要测的 `SvgXAnimationQuality` 实验臂，按运行顺序排列。`QUALITYAB=1`
  // 会在同一次启动内背靠背地测"不降级对照组"以及逐层叠加上去的各项降级；否则只跑
  // 一臂，行为与此前完全一致。
  //
  // 为什么所有臂放在同一进程：动画降级的功过，只有跟同一温度状态、同一二进制下测出
  // 的对照组比才能归因。`--dart-define` 是编译期的，所以运行时开关是从一次构建里
  // 拿到两臂的唯一办法——而它之所以可行，恰恰因为 `_SharedAnimationClock` 每 tick
  // 都重读画质配置，于是翻转全局默认值能在下一帧就把已经挂载好的 1000 个图标重新
  // 调好，无需任何重挂载。
  List<({String label, SvgXAnimationQuality quality})> _qualityArms = _qualityAb
      ? [
          // Control: no degradation of any kind.
          // 对照组：不做任何降级。
          (label: 'exact', quality: SvgXAnimationQuality.exact),
          // The shipped default: frame skipping only. Isolates the UI-thread
          // PAINT saving on its own.
          // 出厂默认：只跳帧。单独隔离出 UI 线程 PAINT 的节省。
          (label: 'skiponly', quality: SvgXAnimationQuality.balanced),
          // Frame skipping plus the opt-in mask-as-clip approximation, which
          // trades UI-thread clip-path construction for raster-thread render
          // passes. This arm exists specifically to settle whether that trade
          // is net positive on a real device — the measurement
          // `SvgXAnimationQuality.approximateSimpleMasksAsClip` is waiting on
          // before it can be defaulted on.
          //
          // 跳帧 + 需手动开启的 mask-转-clip 近似，它用 UI 线程的裁剪路径构建换
          // raster 线程的渲染通道。这一臂的存在目的就是判定这笔交易在真机上是否
          // 净赚——正是 `SvgXAnimationQuality.approximateSimpleMasksAsClip` 在等的
          // 那个测量，测出来才谈得上默认开启。
          (
            label: 'full',
            quality: SvgXAnimationQuality(approximateSimpleMasksAsClip: true),
          ),
          // IMPORTANT — read before assuming this is new ground: `full` above
          // is ALREADY frame skipping + clip approximation together, because
          // `adaptiveFrameSkipping` defaults to true and the constructor call
          // above only overrides `approximateSimpleMasksAsClip`. This arm is
          // the same configuration made explicit (both flags spelled out)
          // rather than relying on defaults, added on request to give the
          // combination its own unambiguous label after `full`'s dual nature
          // caused confusion. Expect its numbers to reproduce `full`'s within
          // noise — a large, reproducible gap between the two would itself be
          // a finding (e.g. arm-order thermal drift), not evidence the
          // configurations differ.
          //
          // 重要——在假设这是"从未测过"的新组合之前先读这段:上面的 `full` 臂
          // **已经**是跳帧 + clip 近似同时开启,因为 `adaptiveFrameSkipping`
          // 默认就是 true,上面那个构造调用只覆盖了 `approximateSimpleMasksAsClip`
          // 一个字段。这一臂是同一份配置,只是把两个字段都显式写出来,而不是依赖
          // 默认值——是应要求加的,为的是在 `full` 的"双重身份"造成过混淆之后,
          // 给这个组合一个不会被误解的独立标签。预期它的数字应与 `full` 在噪声范围
          // 内一致——如果两者出现大且可复现的差距,那本身就是一个新发现(比如臂序
          // 带来的温度漂移),而不是"配置不同"的证据。
          (
            label: 'combined',
            quality: const SvgXAnimationQuality(
              adaptiveFrameSkipping: true,
              approximateSimpleMasksAsClip: true,
            ),
          ),
        ]
      : [(label: 'default', quality: SvgXAnimationQuality.defaultQuality)];

  // Each measured arm's collector, in the order the arms actually ran (which
  // `ARMFLIP` may have reversed) — the report prints one block per entry.
  //
  // 每个已测实验臂的采集器，按实际运行顺序排列（`ARMFLIP` 可能已把顺序反转）
  // ——报告每个条目打印一段。
  final _armCollectors = <({String label, FrameTimingCollector collector})>[];

  // Memory probes. The static bench has reported RSS since day one, but this
  // phase never has — so the animated path's footprint (399 parsed documents
  // held in `SvgDocumentCache`, 1000 live tickers, 1000 painters) has been
  // unmeasured the whole time. Same probe shape as `bench_screen.dart`:
  // a warmup floor, a peak, a post-run steady/idle pair, then what unmounting
  // the grid and dropping the document cache actually gives back.
  //
  // 内存探针。静态基准从第一天起就报 RSS，本阶段从来没有——也就是说动画路径的
  // 占用（`SvgDocumentCache` 里 399 份已解析文档、1000 个 ticker、1000 个
  // painter）一直没被测过。探针形状与 `bench_screen.dart` 一致：预热地板、峰值、
  // 结束后的稳态/静置，再看卸掉网格、丢掉文档缓存到底能还回来多少。
  final _rssSamplesBytes = <int>[];
  Timer? _rssTimer;
  int? _peakRssBytes;
  int? _warmupRssBytes;
  int? _steadyRssBytes;
  int? _postIdleRssBytes;
  int? _afterUnmountRssBytes;
  int? _afterClearRssBytes;
  int? _cachedDocuments;

  @override
  void initState() {
    super.initState();
    // `DOCCACHE=n` overrides SvgDocumentCache's default cap. This corpus has
    // 399 distinct documents against a default cap of 200, so the default
    // guarantees eviction thrash: half the set is re-parsed on every pass.
    // The knob exists to measure what that thrash costs in RSS, which is a
    // cache-capacity question the suite had no way to ask before.
    //
    // `DOCCACHE=n` 覆盖 SvgDocumentCache 的默认上限。本语料有 399 份互异文档，
    // 而默认上限是 200，也就是说默认配置必然抖动：每一趟都要重新解析半个语料。
    // 这个旋钮的用途是量出这份抖动在 RSS 上的代价——这是本套件此前无法提出的
    // 缓存容量问题。
    const docCache = int.fromEnvironment('DOCCACHE');
    if (docCache > 0) SvgDocumentCache.instance.maximumSize = docCache;
    if (_qualityArms.length > 1) {
      // Arm order alternates run-to-run (`ARMFLIP=1`) so a monotonic drift
      // over the process's lifetime — device warming up across the two
      // windows — pushes the two arms in opposite directions between runs
      // instead of always favouring whichever goes first.
      //
      // 实验臂顺序在不同运行间交替（`ARMFLIP=1`），使进程生命周期内的单调漂移
      // （设备在两个窗口之间持续升温）在不同运行中把两臂推向相反方向，而不是
      // 恒定地偏向先跑的那一臂。
      if (_armFlip) {
        _qualityArms = _qualityArms.reversed.toList();
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  void _sampleRss() {
    final rss = ProcessInfo.currentRss;
    _rssSamplesBytes.add(rss);
    if (_peakRssBytes == null || rss > _peakRssBytes!) _peakRssBytes = rss;
  }

  /// Opens one measurement window on [collector] — either the scrolling
  /// acceptance scenario or the hold-still mode, exactly as before, just
  /// factored out so it can be run once per quality arm.
  ///
  /// 在 [collector] 上打开一个测量窗口——滚动验收场景或静止模式，与此前完全一致，
  /// 只是抽了出来以便每个画质实验臂各跑一次。
  ///
  /// [collector] — receives this window's frame timings.
  ///
  ///   接收本窗口的帧计时。
  ///
  /// [label] — arm name, shown in the on-screen status only.
  ///
  ///   实验臂名称，仅用于屏幕状态显示。
  Future<void> _measureWindow(
    FrameTimingCollector collector,
    String label,
  ) async {
    // `cycles == 0` means "hold still and just watch the animations run" — see
    // the class doc for why that separate mode exists.
    // `cycles == 0` 表示"保持静止，只看动画跑"——这个独立模式存在的原因见类注释。
    if (widget.cycles == 0) {
      setState(
        () =>
            _status = '[$label] holding (${widget.holdSeconds}s, no scroll)...',
      );
      collector.active = true;
      await Future<void>.delayed(Duration(seconds: widget.holdSeconds));
      collector.active = false;
      return;
    }
    setState(() => _status = '[$label] scrolling (${widget.cycles} cycles)...');
    collector.active = true;
    final maxExtent = _scrollController.position.maxScrollExtent;
    for (var i = 0; i < widget.cycles; i++) {
      await _scrollController.animateTo(
        maxExtent,
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeInOut,
      );
      await _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeInOut,
      );
    }
    collector.active = false;
  }

  Future<void> _run() async {
    // Warmup: let every animated icon's Ticker start and the grid lay out
    // once before measuring, so ticker start-up jank doesn't skew results.
    // 预热：先让每个动画图标的 Ticker 启动、网格完成一次布局再开始计时，
    // 避免 ticker 启动抖动影响结果。
    await Future<void>.delayed(const Duration(milliseconds: 500));
    _warmupRssBytes = ProcessInfo.currentRss;
    _rssTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _sampleRss(),
    );
    // See [warmUpFrameTimingChannel]: confirms the engine's timing-report
    // channel is actually live before opening the real measurement window,
    // instead of risking a `frames=0` false result when this phase happens
    // to run first right after a cold install/launch.
    //
    // 见 [warmUpFrameTimingChannel]：打开真正的计时窗口前先确认引擎的
    // 上报通道确实存活，避免本阶段恰好在冷安装/冷启动后第一个跑时测出假的
    // `frames=0`。
    await warmUpFrameTimingChannel(_frameTiming);

    for (var arm = 0; arm < _qualityArms.length; arm++) {
      final (label: label, quality: quality) = _qualityArms[arm];
      // Retunes every already-mounted icon on the next tick — see
      // [_qualityArms] for why that works without a remount.
      //
      // 下一个 tick 就会把所有已挂载的图标重新调好——为什么无需重挂载见
      // [_qualityArms]。
      SvgXAnimationQuality.defaultQuality = quality;
      // A fresh collector per arm; the first arm's frames must not leak into
      // the second arm's statistics.
      //
      // 每臂一个全新的采集器；第一臂的帧绝不能混进第二臂的统计里。
      final collector = arm == 0 ? _frameTiming : FrameTimingCollector();
      _armCollectors.add((label: label, collector: collector));
      // Let the new quality profile settle for a few frames before opening
      // the window, so the transition frames (where half the icons are
      // catching up a skipped tick) are not counted as steady state.
      //
      // 开窗前先让新的画质配置稳定几帧，使过渡帧（此时有一半图标正在补上被跳过
      // 的那一 tick）不被算进稳态里。
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await _measureWindow(collector, label);
      if (arm != _qualityArms.length - 1) {
        // Scroll position is left wherever the previous arm ended; reset so
        // both arms traverse the identical extent.
        //
        // 上一臂结束时滚动位置停在哪就是哪；重置一下，使两臂走过完全相同的行程。
        _scrollController.jumpTo(0);
      }
    }
    _steadyRssBytes = ProcessInfo.currentRss;

    setState(() => _status = 'idling for leak check...');
    await Future<void>.delayed(const Duration(seconds: 3));
    _postIdleRssBytes = ProcessInfo.currentRss;
    _rssTimer?.cancel();

    // Attribution probe, standalone runs only — all headline numbers are
    // already recorded, so nothing below can perturb them. See
    // `bench_screen.dart` for why the grid has to come down before the cache
    // is cleared.
    //
    // 归因探针，仅独立运行——头条数字都已记录，下面的动作扰动不了它们。
    // 为什么必须先卸网格再清缓存，见 `bench_screen.dart`。
    if (widget.onComplete == null) {
      _cachedDocuments = SvgDocumentCache.instance.length;
      setState(() {
        _gridMounted = false;
        _status = 'cache-clear attribution probe...';
      });
      await Future<void>.delayed(const Duration(seconds: 3));
      _afterUnmountRssBytes = ProcessInfo.currentRss;
      // `NOCLEAR=1` is the control arm: identical timing, but the cache is
      // left alone. Without it, a drop between the unmount and clear samples
      // cannot be told apart from "a major GC happened to land in that
      // window" — this path's RSS has already been observed falling ~280MB
      // just by idling, so that confusion is not hypothetical.
      //
      // `NOCLEAR=1` 是对照组：时序完全相同，只是不清缓存。没有它的话，卸载与
      // 清空两个采样点之间的下降，就无法与"恰好有一次 major GC 落在这个窗口"
      // 区分开——本路径实测仅静置就掉了约 280MB，这种混淆并非假想。
      if (!const bool.fromEnvironment('NOCLEAR')) {
        SvgDocumentCache.instance.clear();
      }
      await Future<void>.delayed(const Duration(seconds: 3));
      _afterClearRssBytes = ProcessInfo.currentRss;
    }

    setState(() {
      _done = true;
      _status = 'done';
    });
    _printReport();
  }

  void _printReport() {
    final b = _frameTiming.buildStats;
    final r = _frameTiming.rasterStats;
    final result = AnimFpsBenchResult(
      frameCount: _frameTiming.frameCount,
      realFps: _frameTiming.realAverageFps,
      build: b,
      raster: r,
      framesOver16_6: _frameTiming.framesOverBudget(16.6),
      framesOver8_3: _frameTiming.framesOverBudget(8.3),
    );
    // Per-arm block goes out as its OWN report message, emitted before the
    // headline report — not appended to it.
    //
    // This is not cosmetic. On Android `emitReport` is a `print`, which lands
    // in logcat, and logcat truncates an over-long single message. Appending
    // the three arms' 15 extra lines to the headline report pushed it past that
    // limit and silently cut off the trailing `=== END ANIM FPS BENCH REPORT
    // ===` line — which is exactly the marker every harness script polls for to
    // decide a run finished. The result was runs that had completed and printed
    // their numbers being reported as timeouts, which cost a lot of wasted
    // measurement attempts before the cause was found. Keeping each emitted
    // message short keeps every existing scraper working.
    //
    // 逐臂数据块作为**独立的一条**报告消息发出，排在头条报告之前——不是追加到它
    // 后面。
    //
    // 这不是排版问题。Android 上 `emitReport` 就是 `print`，会落到 logcat，而
    // logcat 会截断过长的单条消息。把三个臂的 15 行追加到头条报告里，会把它顶过
    // 这个上限，从而静默切掉末尾的 `=== END ANIM FPS BENCH REPORT ===`——而这一行
    // 恰恰是所有 harness 脚本用来判断"这次运行结束了"的标记。后果是：明明已经跑完
    // 并打印出数字的运行被判成超时，在查明原因之前白白浪费了大量测量尝试。让每条
    // 发出的消息都保持简短，就能让所有现有抓取脚本继续工作。
    // One message PER ARM, not one message for all arms. The first version of
    // this emitted every arm in a single block, which was already the fix for
    // having appended them to the headline report — and it survived exactly as
    // long as there were three arms. Adding a fourth pushed that block over
    // logcat's per-message limit too, and the truncation landed mid-way through
    // the fourth arm's numbers: the `raster:` line simply did not exist in the
    // captured log, so a whole 4-run measurement session produced no raster
    // figure for the one arm it had been run to measure. Emitting per arm makes
    // the message size independent of how many arms there are, so the next arm
    // added cannot resurrect this.
    //
    // 每个臂**一条**消息，而不是所有臂共一条。这段代码的第一版把所有臂放在同一个块里
    // 发出——那本身已经是"曾经把它们追加到头条报告后面"的修复了——而它撑到三个臂为止。
    // 加上第四个臂后，这个块同样顶过了 logcat 的单条消息上限，而截断正好落在第四个臂的
    // 数字中间：抓到的日志里根本没有 `raster:` 这一行，于是整整 4 次运行的测量，恰恰在
    // 它专门要测的那一臂上拿不到 raster 数字。改成逐臂发出后，消息大小与臂的数量无关，
    // 下一个新增的臂不可能再让这个问题复活。
    if (_armCollectors.length > 1) {
      for (final (label: label, collector: collector) in _armCollectors) {
        emitReport(
          '=== ANIM FPS BENCH ARM $label items=${widget.itemCount} ===\n'
          'arm=$label frames=${collector.frameCount}\n'
          'arm=$label real_fps='
          '${collector.realAverageFps.toStringAsFixed(2)}\n'
          'arm=$label build : ${collector.buildStats}\n'
          'arm=$label raster: ${collector.rasterStats}\n'
          'arm=$label framesOver16.6ms=${collector.framesOverBudget(16.6)} '
          'framesOver8.3ms=${collector.framesOverBudget(8.3)}\n'
          '=== END ANIM FPS BENCH ARM $label ===\n',
        );
      }
    }
    final buf = StringBuffer()
      ..writeln(
        '=== ANIM FPS BENCH REPORT items=${widget.itemCount} cycles=${widget.cycles} ===',
      )
      ..writeln('frames=${result.frameCount}')
      ..writeln('real_fps=${result.realFps.toStringAsFixed(2)}')
      ..writeln('build : $b')
      ..writeln('raster: $r')
      ..writeln(
        'framesOver16.6ms=${result.framesOver16_6} '
        'framesOver8.3ms=${result.framesOver8_3}',
      );
    // The unprefixed headline keys stay exactly where every existing script
    // expects them (they report the arm that ran first); the per-arm numbers
    // were already emitted as their own message above.
    //
    // 不带前缀的头条键原地不动，所有现有脚本期望的位置都没变（它们报告的是先跑的
    // 那一臂）；逐臂数字已在上方作为独立消息发出。
    void mb(String name, int? bytes) {
      if (bytes != null) {
        buf.writeln('$name=${(bytes / 1e6).toStringAsFixed(2)}');
      }
    }

    mb('rss_after_warmup_mb', _warmupRssBytes);
    mb('rss_peak_mb', _peakRssBytes);
    mb('rss_steady_after_scroll_mb', _steadyRssBytes);
    mb('rss_after_idle_mb', _postIdleRssBytes);
    mb('rss_after_grid_unmount_mb', _afterUnmountRssBytes);
    mb('rss_after_cache_clear_mb', _afterClearRssBytes);
    if (_cachedDocuments != null) {
      buf.writeln('cached_documents=$_cachedDocuments');
    }
    buf.writeln('=== END ANIM FPS BENCH REPORT ===');
    emitReport(buf.toString());
    widget.onComplete?.call(result);
    // Unattended repeat runs (tool/run_anim_fps.ps1) need the process to end on
    // its own rather than sit on the exit button — this phase's numbers vary
    // enough between runs that a single sample cannot be trusted, so measuring
    // it means running it many times.
    //
    // 无人值守的重复运行（tool/run_anim_fps.ps1）需要进程自行结束，而不是停在
    // 退出按钮上——本阶段的数字在多次运行间波动足够大，单次采样不可信，因此
    // 测量它就意味着要跑很多次。
    if (autoExitAfterReport && widget.onComplete == null) exit(0);
  }

  @override
  void dispose() {
    _rssTimer?.cancel();
    _frameTiming.dispose();
    // Arms after the first own their own collectors (the first arm reuses
    // `_frameTiming`), and each one registered a timings callback with the
    // engine — leaving them registered would keep them collecting after the
    // run ended.
    //
    // 第一臂之外的实验臂各自持有自己的采集器（第一臂复用 `_frameTiming`），
    // 而每个采集器都向引擎注册了帧计时回调——不注销就会在运行结束后继续采集。
    for (final (label: _, collector: collector) in _armCollectors) {
      if (collector != _frameTiming) collector.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('anim fps bench ($_status)'),
        clipBehavior: Clip.none,
      ),
      body: !_gridMounted
          ? const SizedBox.expand()
          : GridView.builder(
              controller: _scrollController,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
              ),
              itemCount: _icons.length,
              itemBuilder: (context, index) {
                final source = _icons[index];
                return Padding(
                  padding: const EdgeInsets.all(4),
                  child: SvgX.string(source, width: 32, height: 32),
                );
              },
            ),
      floatingActionButton: _done
          ? FloatingActionButton.extended(
              onPressed: () => exit(0),
              label: const Text('exit'),
            )
          : null,
    );
  }
}
