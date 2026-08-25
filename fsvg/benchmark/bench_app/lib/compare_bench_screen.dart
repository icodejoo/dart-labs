// Single-build sequential comparison mode (`LIB=compare`): runs all four
// existing benchmark phases — fsvg static, flutter_svg static, the 12-icon
// animation smoothness check, and the 1000-icon animated real-FPS test — one
// after another inside ONE running process, then prints ONE consolidated
// report. This exists to fix a real methodology gap: comparing fsvg's static
// numbers only against a frozen historical baseline can't tell a real
// regression apart from machine-noise between two separate `flutter run`
// launches (a full recompile sits between them, during which machine load
// can shift). Running fsvg and flutter_svg back-to-back in the same process,
// same machine-state window, makes a same-session paired comparison the
// default instead of an occasional manual workaround (see CLAUDE.md
// "复测方法学调整" and its "⚠️ 补丁" note).
//
// This file only sequences the existing phase widgets (`BenchRunner`,
// `AnimBenchRunner`, `AnimFpsBenchRunner`) and aggregates their already
// -computed `*Result` snapshots — it does not reimplement any benchmark
// mechanics (scrolling, timing collection, RSS sampling all stay in the
// original files).
//
// 单编译顺序对比模式（`LIB=compare`）：在同一个运行中的进程内依次跑完全部
// 四个既有基准阶段——fsvg 静态、flutter_svg 静态、12 图标动画流畅度检查、
// 1000 图标动画真实 FPS 测试——然后打印一份汇总报告。这是为了修复一个真实的
// 方法学缺口：只拿 fsvg 的静态数据跟冻结的历史基线比，分不清是真回归还是两次
// 独立 `flutter run` 之间的机器噪声（两次之间隔着一次完整重新编译，期间机器
// 负载可能变化）。让 fsvg 与 flutter_svg 在同一进程、同一机器状态窗口内背靠背
// 跑完，能把"同一时段配对复测"变成默认做法，而不是偶尔才做的人工补救
// （见 CLAUDE.md"复测方法学调整"及其"⚠️ 补丁"说明）。
//
// 本文件只负责编排既有阶段 widget（`BenchRunner`/`AnimBenchRunner`/
// `AnimFpsBenchRunner`）并汇总它们已经算好的 `*Result` 快照——不重新实现任何
// 基准机制（滚动、计时采集、RSS 采样全部留在原文件里）。

import 'dart:async';

import 'package:flutter/material.dart';

import 'anim_bench_screen.dart';
import 'anim_fps_bench_screen.dart';
import 'bench_screen.dart';

/// Idle window inserted between phases so one phase's GC/memory pressure
/// doesn't bleed into the next phase's measurement. Chosen to be longer than
/// the 3s post-scroll "idle for leak check" pause each static phase already
/// does internally, since a phase *transition* additionally has to unmount
/// an entire 1000-widget grid before the next phase's grid mounts — a
/// judgment call, not a value derived from a measurement.
///
/// 阶段之间插入的静置窗口，避免上一阶段的 GC/内存压力影响下一阶段的测量。
/// 比每个静态阶段内部已有的"滚动后 3 秒静置检漏"更长，因为阶段*切换*还要多
/// 卸载一整个 1000 控件的网格，下一阶段的网格才会挂载——这是经验判断，不是
/// 由某次测量反推出的数值。
const _settleBetweenPhases = Duration(seconds: 5);

enum _Phase { fsvgStatic, settle1, flutterSvgStatic, settle2, anim, settle3, animFps, done }

/// Runs all four benchmark phases sequentially within one process lifetime
/// and prints one consolidated report to stdout.
///
/// 在同一个进程生命周期内顺序跑完全部四个基准阶段，把汇总报告打印到 stdout。
class CompareBenchRunner extends StatefulWidget {
  /// Creates the sequential comparison runner. / 创建顺序对比运行器。
  const CompareBenchRunner({super.key, required this.itemCount, required this.cycles});

  /// Number of distinct icons for the static/animated-FPS grids. / 静态/动画 FPS 网格的图标数。
  final int itemCount;
  /// Number of full up-down scroll cycles for the scrolling phases. / 滚动阶段的完整轮次数。
  final int cycles;

  @override
  State<CompareBenchRunner> createState() => _CompareBenchRunnerState();
}

class _CompareBenchRunnerState extends State<CompareBenchRunner> {
  final _stopwatch = Stopwatch()..start();
  _Phase _phase = _Phase.fsvgStatic;
  int _settleRemainingSec = 0;
  Timer? _settleTicker;

  BenchResult? _fsvgResult;
  BenchResult? _flutterSvgResult;
  AnimBenchResult? _animResult;
  AnimFpsBenchResult? _animFpsResult;

  void _settleThen(_Phase settlePhase, VoidCallback onDone) {
    setState(() {
      _phase = settlePhase;
      _settleRemainingSec = _settleBetweenPhases.inSeconds;
    });
    _settleTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _settleRemainingSec--);
    });
    Future<void>.delayed(_settleBetweenPhases, () {
      _settleTicker?.cancel();
      if (!mounted) return;
      onDone();
    });
  }

  void _onFsvgStaticDone(BenchResult result) {
    _fsvgResult = result;
    _settleThen(_Phase.settle1, () => setState(() => _phase = _Phase.flutterSvgStatic));
  }

  void _onFlutterSvgStaticDone(BenchResult result) {
    _flutterSvgResult = result;
    _settleThen(_Phase.settle2, () => setState(() => _phase = _Phase.anim));
  }

  void _onAnimDone(AnimBenchResult result) {
    _animResult = result;
    _settleThen(_Phase.settle3, () => setState(() => _phase = _Phase.animFps));
  }

  void _onAnimFpsDone(AnimFpsBenchResult result) {
    _animFpsResult = result;
    setState(() => _phase = _Phase.done);
    _printConsolidatedReport();
  }

  String _fmtMs(double us) => '${(us / 1000).toStringAsFixed(3)}ms';

  /// Formats one metric row as `metric | fsvg | flutter_svg | delta/ratio |
  /// verdict`, matching the tables already used in CLAUDE.md's benchmark
  /// sections so results can be pasted straight in.
  ///
  /// 按 `metric | fsvg | flutter_svg | delta/ratio | verdict` 格式化一行指标，
  /// 与 CLAUDE.md 基准章节里已经在用的表格一致，方便直接粘贴。
  String _row(String metric, double fsvgVal, double flutterVal, {bool lowerIsBetter = true, String unit = 'ms'}) {
    final ratio = flutterVal == 0 ? double.infinity : fsvgVal / flutterVal;
    final fsvgWins = lowerIsBetter ? fsvgVal <= flutterVal : fsvgVal >= flutterVal;
    final verdict = fsvgWins ? 'fsvg wins' : 'flutter_svg wins';
    return '| $metric | ${fsvgVal.toStringAsFixed(3)}$unit | ${flutterVal.toStringAsFixed(3)}$unit | '
        'ratio=${ratio.toStringAsFixed(3)} | $verdict |';
  }

  void _printConsolidatedReport() {
    final fsvg = _fsvgResult!;
    final flutterSvg = _flutterSvgResult!;
    final anim = _animResult!;
    final animFps = _animFpsResult!;
    final buf = StringBuffer()
      ..writeln('=== COMPARE BENCH REPORT (single-build sequential, items=${widget.itemCount} cycles=${widget.cycles}) ===')
      ..writeln('wall_clock_total_s=${(_stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1)} '
          '(compile time not included; measured from first frame of this widget)')
      ..writeln()
      ..writeln('--- Phase 1+3: static 1000-icon matched pair (fsvg vs flutter_svg, same session) ---')
      ..writeln('| metric | fsvg | flutter_svg | delta/ratio | verdict |')
      ..writeln('|---|---|---|---|---|')
      ..writeln(_row('build avg', fsvg.build.avgUs / 1000, flutterSvg.build.avgUs / 1000))
      ..writeln(_row('build p50', fsvg.build.p50Us / 1000, flutterSvg.build.p50Us / 1000))
      ..writeln(_row('build p90', fsvg.build.p90Us / 1000, flutterSvg.build.p90Us / 1000))
      ..writeln(_row('build p99', fsvg.build.p99Us / 1000, flutterSvg.build.p99Us / 1000))
      ..writeln(_row('build max', fsvg.build.maxUs / 1000, flutterSvg.build.maxUs / 1000))
      ..writeln(_row('raster avg', fsvg.raster.avgUs / 1000, flutterSvg.raster.avgUs / 1000))
      ..writeln(_row('raster p50', fsvg.raster.p50Us / 1000, flutterSvg.raster.p50Us / 1000))
      ..writeln(_row('raster p90', fsvg.raster.p90Us / 1000, flutterSvg.raster.p90Us / 1000))
      ..writeln(_row('raster p99', fsvg.raster.p99Us / 1000, flutterSvg.raster.p99Us / 1000))
      ..writeln(_row('raster max', fsvg.raster.maxUs / 1000, flutterSvg.raster.maxUs / 1000))
      ..writeln(_row('framesOver8.3ms (count)', fsvg.framesOver8_3.toDouble(), flutterSvg.framesOver8_3.toDouble(), unit: ''))
      ..writeln(_row('framesOver16.6ms (count)', fsvg.framesOver16_6.toDouble(), flutterSvg.framesOver16_6.toDouble(), unit: ''))
      ..writeln(_row('rss peak', fsvg.rssPeakMb, flutterSvg.rssPeakMb, unit: 'MB'))
      ..writeln(_row('rss steady (post-scroll)', fsvg.rssSteadyMb, flutterSvg.rssSteadyMb, unit: 'MB'))
      ..writeln(_row('rss after idle', fsvg.rssIdleMb, flutterSvg.rssIdleMb, unit: 'MB'))
      ..writeln('| parse avg (fsvg only, flutter_svg has no public hook) | ${_fmtMs(fsvg.parse.avgUs)} | n/a | n/a | n/a |')
      ..writeln('| parse p99 (fsvg only) | ${_fmtMs(fsvg.parse.p99Us)} | n/a | n/a | n/a |')
      ..writeln('frames: fsvg=${fsvg.frameCount} flutter_svg=${flutterSvg.frameCount}')
      ..writeln()
      ..writeln('--- Phase 5: anim smoothness (12 concurrent SMIL icons, fsvg-only — no equivalent flutter_svg SMIL rendering path exists, per CLAUDE.md honesty principle) ---')
      ..writeln('frames=${anim.frameCount} build_avg=${_fmtMs(anim.build.avgUs)} build_max=${_fmtMs(anim.build.maxUs)} '
          'raster_avg=${_fmtMs(anim.raster.avgUs)} raster_max=${_fmtMs(anim.raster.maxUs)} '
          'framesOver16.6ms=${anim.framesOver16_6} framesOver8.3ms=${anim.framesOver8_3}')
      ..writeln()
      ..writeln('--- Phase 7: anim_fps (1000 animated icons scrolled, real FPS, fsvg-only — no equivalent flutter_svg comparison, per CLAUDE.md honesty principle) ---')
      ..writeln('frames=${animFps.frameCount} real_fps=${animFps.realFps.toStringAsFixed(2)} '
          'build_avg=${_fmtMs(animFps.build.avgUs)} build_max=${_fmtMs(animFps.build.maxUs)} '
          'raster_avg=${_fmtMs(animFps.raster.avgUs)} raster_max=${_fmtMs(animFps.raster.maxUs)} '
          'framesOver16.6ms=${animFps.framesOver16_6} framesOver8.3ms=${animFps.framesOver8_3}')
      ..writeln('=== END COMPARE BENCH REPORT ===');
    // Use print (not debugPrint) so long report lines aren't truncated in the
    // `flutter run` console we scrape.
    // 用 print（而非 debugPrint）避免长报告行在 `flutter run` 控制台里被截断。
    // ignore: avoid_print
    print(buf.toString());
  }

  @override
  void dispose() {
    _settleTicker?.cancel();
    super.dispose();
  }

  Widget _settleScaffold(String afterPhase) => Scaffold(
        appBar: AppBar(title: const Text('compare bench: settling...')),
        body: Center(
          child: Text(
            'settling ${_settleRemainingSec}s after $afterPhase before next phase\n'
            '(letting GC/memory pressure clear before measuring the next phase)',
            textAlign: TextAlign.center,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _Phase.fsvgStatic:
        return BenchRunner(
          key: const ValueKey('fsvg-static'),
          lib: BenchLib.fsvg,
          cycles: widget.cycles,
          itemCount: widget.itemCount,
          onComplete: _onFsvgStaticDone,
        );
      case _Phase.settle1:
        return _settleScaffold('fsvg static phase');
      case _Phase.flutterSvgStatic:
        return BenchRunner(
          key: const ValueKey('flutter_svg-static'),
          lib: BenchLib.flutterSvg,
          cycles: widget.cycles,
          itemCount: widget.itemCount,
          onComplete: _onFlutterSvgStaticDone,
        );
      case _Phase.settle2:
        return _settleScaffold('flutter_svg static phase');
      case _Phase.anim:
        return AnimBenchRunner(
          key: const ValueKey('anim'),
          onComplete: _onAnimDone,
        );
      case _Phase.settle3:
        return _settleScaffold('anim smoothness phase');
      case _Phase.animFps:
        return AnimFpsBenchRunner(
          key: const ValueKey('anim-fps'),
          itemCount: widget.itemCount,
          cycles: widget.cycles,
          onComplete: _onAnimFpsDone,
        );
      case _Phase.done:
        return Scaffold(
          appBar: AppBar(title: const Text('compare bench: done')),
          body: const Center(child: Text('All four phases complete. See stdout for the consolidated report.')),
        );
    }
  }
}
