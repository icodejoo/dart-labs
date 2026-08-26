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

class _AnimFpsBenchRunnerState extends State<AnimFpsBenchRunner> {
  late final List<String> _icons = generateAnimIcons(widget.itemCount);
  final _scrollController = ScrollController();
  final _frameTiming = FrameTimingCollector();
  bool _done = false;
  bool _gridMounted = true;
  String _status = 'warming up...';

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  void _sampleRss() {
    final rss = ProcessInfo.currentRss;
    _rssSamplesBytes.add(rss);
    if (_peakRssBytes == null || rss > _peakRssBytes!) _peakRssBytes = rss;
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

    // `cycles == 0` means "hold still and just watch the animations run" — see
    // the class doc for why that separate mode exists.
    // `cycles == 0` 表示"保持静止，只看动画跑"——这个独立模式存在的原因见类注释。
    if (widget.cycles == 0) {
      setState(
        () => _status = 'holding (${widget.holdSeconds}s, no scroll)...',
      );
      _frameTiming.active = true;
      await Future<void>.delayed(Duration(seconds: widget.holdSeconds));
      _frameTiming.active = false;
    } else {
      setState(() => _status = 'scrolling (${widget.cycles} cycles)...');
      _frameTiming.active = true;
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
      _frameTiming.active = false;
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('anim fps bench ($_status)')),
      body: !_gridMounted
          ? const SizedBox.expand()
          : GridView.builder(
              controller: _scrollController,
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
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
