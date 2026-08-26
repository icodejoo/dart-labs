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
  String _status = 'warming up...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    // Warmup: let every animated icon's Ticker start and the grid lay out
    // once before measuring, so ticker start-up jank doesn't skew results.
    // 预热：先让每个动画图标的 Ticker 启动、网格完成一次布局再开始计时，
    // 避免 ticker 启动抖动影响结果。
    await Future<void>.delayed(const Duration(milliseconds: 500));

    // `cycles == 0` means "hold still and just watch the animations run" — see
    // the class doc for why that separate mode exists.
    // `cycles == 0` 表示"保持静止，只看动画跑"——这个独立模式存在的原因见类注释。
    if (widget.cycles == 0) {
      setState(() => _status = 'holding (${widget.holdSeconds}s, no scroll)...');
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
      )
      ..writeln('=== END ANIM FPS BENCH REPORT ===');
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
    _frameTiming.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('anim fps bench ($_status)')),
      body: GridView.builder(
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
