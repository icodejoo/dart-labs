// Animation smoothness check: renders several concurrently-playing SMIL
// animated icons (fsvg's original Dart animation engine, dispatched via
// FSvg.string) and collects frame build/raster timing while they animate,
// to confirm no main-thread blocking/jank per the performance acceptance
// criteria's animation requirement.
//
// 动画流畅度检查：渲染若干个同时播放的 SMIL 动画图标（fsvg 原创 Dart 动画引擎，
// 经 FSvg.string 分发），在播放期间采集帧 build/raster 耗时，用于验证性能验收
// 条件里"动画不得阻塞主线程"这一项。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fsvg/fsvg.dart';
import 'package:iconify_flutter/icons/line_md.dart';

import 'frame_timing.dart';
import 'stats.dart';

/// Immutable snapshot of a completed [AnimBenchRunner] phase, used by the
/// sequential `LIB=compare` mode to fold this fsvg-only smoothness check into
/// the consolidated report.
///
/// 一次已完成的 [AnimBenchRunner] 阶段结果快照，供顺序 `LIB=compare` 模式把这个
/// 仅测 fsvg 的流畅度检查折进汇总报告。
///
/// Example:
/// ```dart
/// AnimBenchRunner(onComplete: (r) => print(r.build));
/// ```
class AnimBenchResult {
  /// Creates a result snapshot. / 创建结果快照。
  const AnimBenchResult({
    required this.frameCount,
    required this.build,
    required this.raster,
    required this.framesOver16_6,
    required this.framesOver8_3,
  });

  /// Total frames observed during the observation window. / 观测窗口内的总帧数。
  final int frameCount;
  /// Build duration stats. / build 耗时统计。
  final DurationStats build;
  /// Raster duration stats. / raster 耗时统计。
  final DurationStats raster;
  /// Frames whose build exceeded 16.6ms. / build 超过 16.6ms 的帧数。
  final int framesOver16_6;
  /// Frames whose build exceeded 8.3ms. / build 超过 8.3ms 的帧数。
  final int framesOver8_3;
}

/// Concurrency count for animated icons under test. / 被测并发动画图标数量。
const _concurrentIcons = 12;

/// Observation window for frame-timing collection. / 帧耗时采集观测窗口。
const _observeDuration = Duration(seconds: 6);

// svg-spinners `180-ring`, verbatim (same source as `example/lib/main.dart`'s
// `kSpinnerSvg`). Added post-feature-batch to cover `<animateTransform
// type="rotate">` + `repeatCount="indefinite"`, driven by the raw `Ticker`
// that replaced the bounded `AnimationController` — a continuously-ticking
// animation is a different perf profile from the original `<animate>`-only,
// one-shot-then-freeze icons below (which stop ticking once done).
//
// svg-spinners 的 `180-ring`，与 `example/lib/main.dart` 里的 `kSpinnerSvg`
// 同源。功能批次落地后补充，用于覆盖 `<animateTransform type="rotate">` +
// `repeatCount="indefinite"`，由取代了有界 `AnimationController` 的原始
// `Ticker` 驱动——持续 ticking 与下面「一次性播放后停止」的 `<animate>` 图标
// 是完全不同的性能画像。
const String _kSpinnerSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">'
    '<path fill="currentColor" d="M12,1A11,11,0,1,0,23,12,11,11,0,0,0,12,1Zm0,19a8,8,0,1,1,8-8A8,8,0,0,1,12,20Z" opacity=".25"/>'
    '<path fill="currentColor" d="M12,4a8,8,0,0,1,7.89,6.7A1.53,1.53,0,0,0,21.38,12h0a1.5,1.5,0,0,0,1.48-1.75,11,11,0,0,0-21.72,0A1.5,1.5,0,0,0,2.62,12h0a1.53,1.53,0,0,0,1.49-1.3A8,8,0,0,1,12,4Z">'
    '<animateTransform attributeName="transform" dur="0.75s" repeatCount="indefinite" type="rotate" values="0 12 12;360 12 12"/>'
    '</path></svg>';

/// Runs the animation smoothness check and prints a report to stdout.
///
/// 跑动画流畅度检查，把报告打印到 stdout。
class AnimBenchRunner extends StatefulWidget {
  /// Creates the animation bench runner. / 创建动画基准运行器。
  const AnimBenchRunner({super.key, this.onComplete});

  /// Called with the final [AnimBenchResult] once the observation window
  /// ends, in addition to the usual stdout report. Null in standalone
  /// `LIB=anim` runs (behavior unchanged).
  ///
  /// 观测窗口结束后携带最终 [AnimBenchResult] 回调，是常规 stdout 报告之外的
  /// 补充。独立 `LIB=anim` 运行时为 null（行为不变）。
  final ValueChanged<AnimBenchResult>? onComplete;

  @override
  State<AnimBenchRunner> createState() => _AnimBenchRunnerState();
}

class _AnimBenchRunnerState extends State<AnimBenchRunner> {
  final _frameTiming = FrameTimingCollector();

  static const _icons = <String>[
    LineMd.confirm_circle,
    LineMd.account,
    LineMd.alert_circle,
    LineMd.align_center,
    _kSpinnerSvg,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _frameTiming.active = true;
    await Future<void>.delayed(_observeDuration);
    _frameTiming.active = false;
    _printReport();
  }

  void _printReport() {
    final b = _frameTiming.buildStats;
    final r = _frameTiming.rasterStats;
    final result = AnimBenchResult(
      frameCount: _frameTiming.frameCount,
      build: b,
      raster: r,
      framesOver16_6: _frameTiming.framesOverBudget(16.6),
      framesOver8_3: _frameTiming.framesOverBudget(8.3),
    );
    final buf = StringBuffer()
      ..writeln('=== ANIM BENCH REPORT icons=$_concurrentIcons window=${_observeDuration.inSeconds}s ===')
      ..writeln('frames=${result.frameCount}')
      ..writeln('build : $b')
      ..writeln('raster: $r')
      ..writeln('framesOver16.6ms=${result.framesOver16_6} '
          'framesOver8.3ms=${result.framesOver8_3}')
      ..writeln('=== END ANIM BENCH REPORT ===');
    // ignore: avoid_print
    print(buf.toString());
    widget.onComplete?.call(result);
  }

  @override
  void dispose() {
    _frameTiming.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('anim bench')),
      body: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4),
        itemCount: _concurrentIcons,
        itemBuilder: (context, index) {
          final source = _icons[index % _icons.length];
          return Padding(
            padding: const EdgeInsets.all(8),
            child: FSvg.string(source, width: 48, height: 48),
          );
        },
      ),
    );
  }
}
