// The benchmark screen: renders 1000 distinct icon SVGs in a grid, drives a
// back-and-forth scroll (bounce between top/bottom), and collects frame
// timing, parse timing (svgx only) and RSS memory samples throughout.
//
// 基准测试页：网格渲染 1000 个不同的图标 SVG，驱动来回滚动（顶部/底部弹跳），
// 并全程采集帧耗时、解析耗时（仅 svgx）与 RSS 内存样本。

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:svgx/svgx.dart';

import 'frame_timing.dart';
import 'stats.dart';
import 'svg_gen.dart';

/// Which library under test renders the grid. / 被测的渲染库。
enum BenchLib { svgx, flutterSvg }

/// Immutable snapshot of one completed [BenchRunner] phase, used to build the
/// consolidated multi-phase report in the sequential `LIB=compare` mode
/// (`compare_bench_screen.dart`) without re-running or re-parsing anything.
///
/// 一次已完成的 [BenchRunner] 阶段结果快照，供 `LIB=compare` 顺序模式
/// （`compare_bench_screen.dart`）拼装汇总报告使用，无需重新运行或重新解析。
///
/// Example:
/// ```dart
/// BenchRunner(lib: BenchLib.svgx, cycles: 6, itemCount: 1000,
///     onComplete: (result) => print(result.build));
/// ```
class BenchResult {
  /// Creates a result snapshot. / 创建结果快照。
  const BenchResult({
    required this.lib,
    required this.frameCount,
    required this.build,
    required this.raster,
    required this.framesOver16_6,
    required this.framesOver8_3,
    required this.parse,
    required this.rssPeakMb,
    required this.rssSteadyMb,
    required this.rssIdleMb,
  });

  /// Library this result was measured for. / 本结果对应的被测库。
  final BenchLib lib;

  /// Total frames observed during the scroll window. / 滚动窗口内观测到的总帧数。
  final int frameCount;

  /// Build duration stats. / build 耗时统计。
  final DurationStats build;

  /// Raster duration stats. / raster 耗时统计。
  final DurationStats raster;

  /// Frames whose build exceeded 16.6ms. / build 超过 16.6ms 的帧数。
  final int framesOver16_6;

  /// Frames whose build exceeded 8.3ms. / build 超过 8.3ms 的帧数。
  final int framesOver8_3;

  /// Parse duration stats (empty/zero for flutter_svg, no public hook).
  ///
  /// 解析耗时统计（flutter_svg 无公开钩子，恒为空/零）。
  final DurationStats parse;

  /// Peak RSS in MB observed during the run. / 运行期间观测到的 RSS 峰值（MB）。
  final double rssPeakMb;

  /// RSS in MB right after the scroll cycles finish. / 滚动结束时的 RSS（MB）。
  final double rssSteadyMb;

  /// RSS in MB after the post-scroll idle window. / 滚动后静置窗口结束时的 RSS（MB）。
  final double rssIdleMb;
}

/// Runs the full scroll benchmark for [lib] and prints a report to stdout.
///
/// 对 [lib] 跑完整滚动基准，并把报告打印到 stdout。
class BenchRunner extends StatefulWidget {
  /// Creates the runner for the given library and cycle count.
  ///
  /// 创建指定库与轮次数的基准运行器。
  const BenchRunner({
    super.key,
    required this.lib,
    required this.cycles,
    required this.itemCount,
    this.onComplete,
  });

  /// Library under test. / 被测库。
  final BenchLib lib;

  /// Number of full up-down scroll cycles. / 上下滚动的完整轮次数。
  final int cycles;

  /// Number of distinct icons in the grid. / 网格中不同图标的数量。
  final int itemCount;

  /// Called with the final [BenchResult] once the phase finishes, in addition
  /// to (not instead of) the usual stdout report — used by the sequential
  /// `LIB=compare` mode to build a consolidated report without re-parsing
  /// stdout. Individual-mode runs (`LIB=svgx`/`LIB=flutter_svg`) leave this
  /// null and behave exactly as before.
  ///
  /// 阶段完成后携带最终 [BenchResult] 回调，是常规 stdout 报告之外的补充
  /// （不是替代）——供顺序 `LIB=compare` 模式拼装汇总报告，无需回头解析
  /// stdout。单独模式（`LIB=svgx`/`LIB=flutter_svg`）不传此参数，行为与之前
  /// 完全一致。
  final ValueChanged<BenchResult>? onComplete;

  @override
  State<BenchRunner> createState() => _BenchRunnerState();
}

class _BenchRunnerState extends State<BenchRunner> {
  late final List<String> _icons = generateIcons(widget.itemCount);
  final _scrollController = ScrollController();
  final _frameTiming = FrameTimingCollector();
  final _parseDurations = <Duration>[];
  final _rssSamplesBytes = <int>[];
  Timer? _rssTimer;
  int? _peakRssBytes;
  int? _steadyRssBytes;
  int? _postIdleRssBytes;
  bool _done = false;
  String _status = 'warming up...';

  @override
  void initState() {
    super.initState();
    if (widget.lib == BenchLib.svgx) {
      // Size the cache to hold every distinct icon in the dataset so the
      // measurement reflects steady-state reuse (a real app would size its
      // cache to its icon set), not LRU thrashing from an undersized default.
      //
      // 把缓存上限设为能容纳数据集里所有不同图标，让测量反映稳态复用（真实应用
      // 会按图标集大小配置缓存），而不是默认上限过小导致的 LRU 抖动。
      RustSvgPictureCache.instance.maximumSize = widget.itemCount + 50;
      RustSvgPictureCache.instance.onParseMiss = _parseDurations.add;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  void _sampleRss() {
    final rss = ProcessInfo.currentRss;
    _rssSamplesBytes.add(rss);
    if (_peakRssBytes == null || rss > _peakRssBytes!) _peakRssBytes = rss;
  }

  Future<void> _run() async {
    // Warmup: let the grid lay out once before measuring.
    // 预热：先让网格完成一次布局再开始计时。
    await Future<void>.delayed(const Duration(milliseconds: 500));
    _rssTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _sampleRss(),
    );

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
    _steadyRssBytes = ProcessInfo.currentRss;

    setState(() => _status = 'idling for leak check...');
    await Future<void>.delayed(const Duration(seconds: 3));
    _postIdleRssBytes = ProcessInfo.currentRss;
    _rssTimer?.cancel();

    setState(() {
      _done = true;
      _status = 'done';
    });
    _printReport();
  }

  void _printReport() {
    final b = _frameTiming.buildStats;
    final r = _frameTiming.rasterStats;
    final parse = DurationStats.fromDurations(_parseDurations);
    final result = BenchResult(
      lib: widget.lib,
      frameCount: _frameTiming.frameCount,
      build: b,
      raster: r,
      framesOver16_6: _frameTiming.framesOverBudget(16.6),
      framesOver8_3: _frameTiming.framesOverBudget(8.3),
      parse: parse,
      rssPeakMb: (_peakRssBytes ?? 0) / 1e6,
      rssSteadyMb: (_steadyRssBytes ?? 0) / 1e6,
      rssIdleMb: (_postIdleRssBytes ?? 0) / 1e6,
    );
    final buf = StringBuffer()
      ..writeln(
        '=== BENCH REPORT lib=${widget.lib} items=${widget.itemCount} cycles=${widget.cycles} ===',
      )
      ..writeln('frames=${result.frameCount}')
      ..writeln('build : $b')
      ..writeln('raster: $r')
      ..writeln(
        'framesOver16.6ms=${result.framesOver16_6} '
        'framesOver8.3ms=${result.framesOver8_3}',
      )
      ..writeln(
        'parse : $parse (svgx only; flutter_svg has no equivalent public hook)',
      )
      ..writeln('rss_peak_mb=${result.rssPeakMb.toStringAsFixed(2)}')
      ..writeln(
        'rss_steady_after_scroll_mb=${result.rssSteadyMb.toStringAsFixed(2)}',
      )
      ..writeln('rss_after_idle_mb=${result.rssIdleMb.toStringAsFixed(2)}')
      ..writeln('=== END BENCH REPORT ===');
    // Use print (not debugPrint) so long report lines aren't truncated in
    // the `flutter run` console we scrape.
    // 用 print（而非 debugPrint）避免长报告行在 `flutter run` 控制台里被截断。
    // ignore: avoid_print
    print(buf.toString());
    widget.onComplete?.call(result);
  }

  @override
  void dispose() {
    _rssTimer?.cancel();
    _frameTiming.dispose();
    if (widget.lib == BenchLib.svgx) {
      RustSvgPictureCache.instance.onParseMiss = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('bench: ${widget.lib} ($_status)')),
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
            child: widget.lib == BenchLib.svgx
                ? SvgXStatic(source, width: 32, height: 32)
                : SvgPicture.string(source, width: 32, height: 32),
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
