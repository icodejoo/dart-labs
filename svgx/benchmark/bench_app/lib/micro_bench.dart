// Deterministic, low-noise Dart-side microbenchmarks (`LIB=micro`).
//
// Why this exists: the scrolling `LIB=compare` suite measures the whole
// pipeline (scroll physics + GPU raster + OS scheduling) and, as
// `docs/performance-benchmarks.md` records, this machine's absolute build/
// raster numbers swing by 20%–110% between runs. That noise floor makes it
// impossible to attribute a 10–30% Dart-side improvement with the scrolling
// benchmark alone. These microbenchmarks instead run the exact Dart functions
// under optimization in a tight in-process loop with no GPU, no scrolling and
// no widget tree, repeat each measurement over several trials, and report the
// MIN trial (the standard low-noise statistic for CPU-bound loops: noise only
// ever adds time, so the minimum is the closest observation to the true cost)
// alongside the median. Same AOT binary, same machine — the scrolling suite
// still has the last word on end-to-end numbers.
//
// 为什么需要它：滚动版 `LIB=compare` 测的是整条管线（滚动物理 + GPU 光栅 +
// 操作系统调度），而 `docs/performance-benchmarks.md` 已记录本机 build/raster
// 绝对值在多次运行间会波动 20%~110%。这个噪声底噪使得仅靠滚动基准无法归因
// 10%~30% 量级的 Dart 侧改进。本文件改为在进程内用紧凑循环直接跑被优化的
// Dart 函数（无 GPU、无滚动、无控件树），每项测量重复多轮，报告**最小**耗时
// （CPU 密集循环的标准低噪统计量：噪声只会增加耗时，故最小值最接近真实开销）
// 并附中位数。同一 AOT 二进制、同一台机器——端到端结论仍以滚动基准为准。

// ignore_for_file: implementation_imports, avoid_print

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:svgx/src/animation/animated_svg_painter.dart';
import 'package:svgx/src/animation/animation_detector.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';
import 'package:svgx/src/animation/svg_theme.dart';
import 'package:svgx/src/rust_static_svg.dart';

import 'anim_icons_real.dart';
import 'mdi_icons_1000.dart';

/// One microbenchmark's timing result across all its trials.
///
/// 一项微基准在全部轮次上的计时结果。
class MicroResult {
  /// Creates a result. / 创建结果。
  const MicroResult(this.name, this.unitsPerTrial, this.trialMicros);

  /// Benchmark name printed in the report. / 报告中打印的基准名。
  final String name;

  /// Work units (icons, paints, ...) performed per trial, so the report can
  /// express cost per unit. / 每轮完成的工作单元数（图标数、绘制次数……），
  /// 便于报告换算成单位成本。
  final int unitsPerTrial;

  /// Wall-clock microseconds of each trial. / 每轮的挂钟耗时（微秒）。
  final List<int> trialMicros;

  /// Fastest trial, in microseconds per work unit. / 最快一轮的单位耗时（微秒）。
  double get minPerUnitUs =>
      (trialMicros.reduce((a, b) => a < b ? a : b)) / unitsPerTrial;

  /// Median trial, in microseconds per work unit. / 中位轮的单位耗时（微秒）。
  double get medianPerUnitUs {
    final sorted = [...trialMicros]..sort();
    return sorted[sorted.length ~/ 2] / unitsPerTrial;
  }

  @override
  String toString() =>
      '$name: min=${minPerUnitUs.toStringAsFixed(3)}us/unit '
      'median=${medianPerUnitUs.toStringAsFixed(3)}us/unit '
      'units=$unitsPerTrial trials=${trialMicros.length} '
      'raw_min_ms=${(trialMicros.reduce((a, b) => a < b ? a : b) / 1000).toStringAsFixed(2)}';
}

/// Runs [body] once per warmup pass, then [trials] timed passes.
///
/// [reset] runs before every pass (warmup included) and is not timed, so a
/// benchmark can clear caches without the clear showing up in the result.
///
/// 先跑 [warmups] 轮预热，再跑 [trials] 轮计时。[reset] 在每轮（含预热）之前
/// 执行且不计时，使基准可以在不污染结果的前提下清空缓存。
MicroResult _measure(
  String name,
  int unitsPerTrial,
  void Function() body, {
  int warmups = 3,
  int trials = 7,
  void Function()? reset,
}) {
  for (var i = 0; i < warmups; i++) {
    reset?.call();
    body();
  }
  final micros = <int>[];
  for (var i = 0; i < trials; i++) {
    reset?.call();
    final sw = Stopwatch()..start();
    body();
    micros.add(sw.elapsedMicroseconds);
  }
  return MicroResult(name, unitsPerTrial, micros);
}

/// Runs every Dart-side microbenchmark and prints one report block.
///
/// 跑完全部 Dart 侧微基准并打印一份报告。
///
/// Example:
/// ```dart
/// runMicroBenchmarks();
/// ```
List<MicroResult> runMicroBenchmarks() {
  final results = <MicroResult>[];
  final staticIcons = mdiIcons1000;
  final animIcons = animIconsReal;
  final cache = RustSvgPictureCache.instance;

  // --- Static path -------------------------------------------------------
  // Cold parse + ui.Picture record for 1000 distinct real icons: the
  // cache-miss cost every icon pays exactly once.
  // 1000 个互异真实图标的冷解析 + ui.Picture 录制：每个图标只付一次的缓存
  // 未命中成本。
  cache.maximumSize = staticIcons.length + 50;
  results.add(
    _measure(
      'static_parse_record',
      staticIcons.length,
      () {
        for (final src in staticIcons) {
          cache.getOrRender(src);
        }
      },
      reset: cache.clear,
      warmups: 2,
      trials: 5,
    ),
  );

  // Warm path: what `SvgXStatic.build` does on every rebuild once the picture
  // is cached — animation sniffing, `<image>` sniffing, cache lookup. This is
  // the per-frame-per-visible-icon cost during a scroll.
  // 热路径：picture 已缓存后 `SvgXStatic.build` 每次重建做的事——动画嗅探、
  // `<image>` 嗅探、缓存查找。这是滚动中每帧每个可见图标的成本。
  for (final src in staticIcons) {
    cache.getOrRender(src);
  }
  results.add(
    _measure('static_route_and_lookup', staticIcons.length, () {
      for (final src in staticIcons) {
        if (!AnimationDetector.hasAnimations(src)) {
          cache.getOrRender(src);
        }
      }
    }),
  );

  // Animation sniffing in isolation, over the same static sources (the
  // all-patterns-miss worst case, which is what a static icon grid hits).
  // 单独测动画嗅探，样本仍是静态源（全部模式都不命中的最坏情况，也正是静态
  // 图标网格的实际情况）。
  results.add(
    _measure('detect_animations_static_sources', staticIcons.length, () {
      var hits = 0;
      for (final src in staticIcons) {
        if (AnimationDetector.hasAnimations(src)) hits++;
      }
      if (hits < 0) throw StateError('unreachable');
    }),
  );

  // --- Animation path ----------------------------------------------------
  // One-time document parse per animated icon: paid on every widget mount,
  // i.e. every time a cell scrolls into view in the anim_fps scenario.
  // 每个动画图标的一次性文档解析：每次控件挂载都要付，也就是 anim_fps 场景里
  // 每次格子滚进视口都要付。
  results.add(
    _measure('anim_parse_document', animIcons.length, () {
      for (final src in animIcons) {
        parseAnimatedSvgDocument(src);
      }
    }, warmups: 2, trials: 5),
  );

  // Per-frame paint cost: the dominant repeated work of the animation engine.
  // Documents are parsed once up front (not timed); each timed pass paints
  // every document at a fresh timeline position into a throwaway recorder.
  // 逐帧绘制成本：动画引擎重复做的主要工作。文档预先解析好（不计时）；每一轮
  // 计时都在新的时间线位置把每个文档绘制进一个一次性 recorder。
  final documents = [
    for (final src in animIcons) parseAnimatedSvgDocument(src),
  ];
  const theme = SvgTheme();
  const paintSize = Size(32, 32);
  var frame = 0;
  results.add(
    _measure('anim_paint_frame', documents.length, () {
      frame++;
      final time = Duration(milliseconds: 16 * frame);
      for (final doc in documents) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        AnimatedSvgPainter(
          root: doc.root,
          intrinsicSize: Size(doc.width, doc.height),
          time: time,
          theme: theme,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          gradients: doc.gradients,
          clipPaths: doc.clipPaths,
          masks: doc.masks,
        ).paint(canvas, paintSize);
        recorder.endRecording().dispose();
      }
    }, warmups: 3, trials: 9),
  );

  return results;
}

/// Prints [results] as a stdout report block the harness can scrape.
///
/// 把 [results] 打印成外部脚本可抓取的 stdout 报告块。
void printMicroReport(List<MicroResult> results) {
  final buf = StringBuffer()..writeln('=== MICRO BENCH REPORT ===');
  for (final r in results) {
    buf.writeln(r.toString());
  }
  buf.writeln('=== END MICRO BENCH REPORT ===');
  print(buf.toString());
}
