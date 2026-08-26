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

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:svgx/src/animation/animated_svg_painter.dart';
import 'package:svgx/src/animation/animation_detector.dart';
import 'package:svgx/src/animation/svg_document_cache.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';
import 'package:svgx/src/animation/svg_path_data.dart';
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

  // Calibration: a fixed pure-Dart scan over the same icon data, using only
  // `String.length`/`String.codeUnitAt`. NEVER change this benchmark — its
  // whole value is being a constant yardstick. Other work on the machine
  // (this repo's parallel Rust build, for one) shifts every absolute number
  // in a run by a common factor; dividing a measurement's change by this
  // one's change separates "the code got faster" from "the machine got
  // busier". Same paired-comparison logic `docs/performance-benchmarks.md`
  // already applies with the flutter_svg arm, just at microbenchmark scale.
  //
  // 校准项：对同一批图标数据做固定的纯 Dart 扫描，只用
  // `String.length`/`String.codeUnitAt`。**永远不要改动这个基准**——它的全部
  // 价值就在于当一根恒定的标尺。机器上的其它负载（比如本仓库并行进行的 Rust
  // 构建）会让一次运行里所有绝对值同乘一个系数；把某项的变化量除以本项的
  // 变化量，就能把"代码变快了"与"机器变忙了"区分开。这与
  // `docs/performance-benchmarks.md` 里用 flutter_svg 那一组做配对对照是同一个
  // 逻辑，只是尺度落到微基准。
  results.add(
    _measure('calibration_codeunit_scan', staticIcons.length, () {
      var angleBrackets = 0;
      for (final src in staticIcons) {
        for (var i = 0; i < src.length; i++) {
          if (src.codeUnitAt(i) == 0x3C) angleBrackets++;
        }
      }
      if (angleBrackets < 0) throw StateError('unreachable');
    }, trials: 9),
  );

  // Second calibration, for the allocation-heavy benchmarks. The scan above
  // allocates nothing, so it tracks raw CPU contention but is blind to the
  // GC/allocator/memory-bandwidth pressure that dominates noise in paint-shaped
  // work — observed directly: between two runs the scan held at 0.265us while
  // `anim_paint_frame` moved 16%. This one allocates a map, a path and a paint
  // and records them into a display list per iteration, using framework APIs
  // only. NEVER change it either.
  //
  // 第二个校准项，服务于分配密集的基准。上面那个扫描不做任何分配，能反映纯 CPU
  // 争用，但对绘制型工作里占主导的 GC/分配器/内存带宽压力完全不敏感——这是实际
  // 观测到的：两次运行之间扫描项稳定在 0.265us，而 `anim_paint_frame` 波动了
  // 16%。本项每轮迭代分配一个 map、一条 path 和一个 paint 并录制进显示列表，
  // 只用框架 API。**同样永远不要改动它**。
  const calibrationAttributes = <String, String>{
    'fill': '#ff0000',
    'stroke': 'none',
    'stroke-width': '2',
    'd': 'M0 0L10 10',
  };
  results.add(
    _measure('calibration_alloc_and_record', 1000, () {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      for (var i = 0; i < 1000; i++) {
        final copied = Map<String, String>.of(calibrationAttributes);
        final path = ui.Path()
          ..moveTo(0, 0)
          ..lineTo(10, i.toDouble())
          ..cubicTo(1, 2, 3, 4, 5, 6)
          ..close();
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.fill
            ..color = const Color(0xFFFF0000),
        );
        if (copied.length != 4) throw StateError('unreachable');
      }
      recorder.endRecording().dispose();
    }, trials: 9),
  );

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

  // The `<image>` sniff `SvgXStatic` used to run on *every* rebuild, versus
  // the cache lookup that now takes its place on the warm path. The pattern
  // below deliberately mirrors `SvgXStatic._imagePattern` (private) so the
  // removed work can be quantified.
  //
  // `SvgXStatic` 过去**每次**重建都要做的 `<image>` 嗅探，对比现在热路径上取代
  // 它的缓存查找。下面的正则刻意与私有的 `SvgXStatic._imagePattern` 一致，
  // 以便量化被去掉的这部分开销。
  final imagePattern = RegExp(r'<image[\s>]', caseSensitive: false);
  results.add(
    _measure('static_image_sniff_removed_work', staticIcons.length, () {
      var hits = 0;
      for (final src in staticIcons) {
        if (imagePattern.hasMatch(src)) hits++;
      }
      if (hits < 0) throw StateError('unreachable');
    }),
  );
  results.add(
    _measure('static_cache_peek_added_work', staticIcons.length, () {
      for (final src in staticIcons) {
        cache.peek(src);
      }
    }),
  );

  // --- Animation path ----------------------------------------------------
  // One-time document parse per animated icon: paid on every widget mount,
  // i.e. every time a cell scrolls into view in the anim_fps scenario.
  // 每个动画图标的一次性文档解析：每次控件挂载都要付，也就是 anim_fps 场景里
  // 每次格子滚进视口都要付。
  results.add(
    _measure(
      'anim_parse_document',
      animIcons.length,
      () {
        for (final src in animIcons) {
          parseAnimatedSvgDocument(src);
        }
      },
      warmups: 2,
      trials: 5,
    ),
  );

  // Same mount work once the document cache is warm — what a re-mount costs
  // after the first appearance of an icon.
  // 文档缓存预热后同样的挂载工作——图标首次出现之后，再次挂载要付多少。
  final documentCache = SvgDocumentCache.instance;
  documentCache.maximumSize = animIcons.length + 50;
  for (final src in animIcons) {
    documentCache.getOrParse(src);
  }
  results.add(
    _measure('anim_document_cache_hit', animIcons.length, () {
      for (final src in animIcons) {
        documentCache.getOrParse(src);
      }
    }),
  );

  // Paired primitive measurement for typing the display-list replay loop as
  // Uint8List/Float32List (what the FFI bridge actually returns) instead of
  // List<int>/List<double>. `static_parse_record` cannot resolve this on its
  // own: most of its 21.5us is the Rust parse, so the replay loop's share is
  // near the noise floor. Both variants run in the SAME process over the same
  // data, so the comparison is immune to background load.
  //
  // 把显示列表重放循环声明为 Uint8List/Float32List（FFI 桥实际返回的类型）而不是
  // List<int>/List<double> 这项改动的配对原语测量。`static_parse_record` 自身
  // 分辨不出来：它 21.5us 里大部分是 Rust 解析，重放循环那一份接近噪声底噪。
  // 两个变体在**同一个进程**里跑同一批数据，因此对后台负载免疫。
  final replayVerbs = Uint8List(4000);
  final replayPoints = Float32List(12000);
  for (var i = 0; i < replayVerbs.length; i++) {
    replayVerbs[i] = i % 5 == 0 ? 0 : (i % 4 == 0 ? 3 : 1);
  }
  for (var i = 0; i < replayPoints.length; i++) {
    replayPoints[i] = (i % 97).toDouble();
  }
  results.add(
    _measure('replay_typed_lists', 200, () {
      for (var pass = 0; pass < 200; pass++) {
        _replayTyped(replayVerbs, replayPoints);
      }
    }, trials: 9),
  );
  results.add(
    _measure('replay_interface_lists', 200, () {
      for (var pass = 0; pass < 200; pass++) {
        _replayInterface(replayVerbs, replayPoints);
      }
    }, trials: 9),
  );

  // Paired primitive measurement for the "reuse a scratch Paint instead of
  // allocating one per draw" change in `animated_svg_painter.dart`. Both
  // variants run in the SAME process seconds apart, so — unlike an
  // across-builds comparison — background load cannot favour either one. The
  // per-draw delta between them, times the number of draws an icon issues per
  // frame, is the change's real budget.
  //
  // `animated_svg_painter.dart` 里"复用临时 Paint 而非每次绘制新建一个"这项改动
  // 的配对原语测量。两个变体在**同一个进程**里相隔数秒运行，因此与跨构建对比
  // 不同，后台负载无法偏向任何一方。两者的单次绘制差值，乘以图标每帧发出的绘制
  // 次数，就是这项改动真正的预算。
  final scratchPath = ui.Path()
    ..moveTo(0, 0)
    ..lineTo(10, 10)
    ..cubicTo(1, 2, 3, 4, 5, 6);
  const drawColor = Color(0xFF3366CC);
  results.add(
    _measure('paint_fresh_alloc_per_draw', 20000, () {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      for (var i = 0; i < 20000; i++) {
        canvas.drawPath(
          scratchPath,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = drawColor
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
      recorder.endRecording().dispose();
    }, trials: 9),
  );
  final reusedPaint = Paint()..style = PaintingStyle.stroke;
  results.add(
    _measure('paint_reused_per_draw', 20000, () {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      for (var i = 0; i < 20000; i++) {
        canvas.drawPath(
          scratchPath,
          reusedPaint
            ..shader = null
            ..color = drawColor
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
      recorder.endRecording().dispose();
    }, trials: 9),
  );

  // SVG `d` parsing in isolation, over every `d` string in the 399 real
  // animated icons. Once geometry is cached per node this no longer runs every
  // frame, but it is still paid on a document's first paint, so it stays worth
  // measuring on its own rather than hiding inside `anim_paint_frame`.
  //
  // 单独测 SVG `d` 解析，样本是 399 个真实动画图标里的每一条 `d` 字符串。几何
  // 按节点缓存之后它不再每帧运行，但文档首帧绘制仍要付，所以值得单独测量，
  // 而不是藏在 `anim_paint_frame` 里。
  final pathDataStrings = <String>[];
  for (final src in animIcons) {
    for (final match in RegExp(r'\sd="([^"]+)"').allMatches(src)) {
      pathDataStrings.add(match.group(1)!);
    }
  }
  results.add(
    _measure('path_data_parse', pathDataStrings.length, () {
      for (final d in pathDataStrings) {
        parseSvgPathData(d);
      }
    }),
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
  final clock = ValueNotifier(Duration.zero);
  results.add(
    _measure(
      'anim_paint_frame',
      documents.length,
      () {
        frame++;
        clock.value = Duration(milliseconds: 16 * frame);
        for (final doc in documents) {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          AnimatedSvgPainter(
            root: doc.root,
            intrinsicSize: Size(doc.width, doc.height),
            clock: clock,
            theme: theme,
            fit: BoxFit.contain,
            alignment: Alignment.center,
            gradients: doc.gradients,
            clipPaths: doc.clipPaths,
            masks: doc.masks,
          ).paint(canvas, paintSize);
          recorder.endRecording().dispose();
        }
      },
      warmups: 3,
      trials: 9,
    ),
  );

  return results;
}

// Two copies of `rust_static_svg.dart`'s private `_replay` verb/point decoder,
// differing ONLY in the static type of the two buffers (and hence in whether
// element reads are typed-data loads or boxed interface calls). Kept in the
// benchmark rather than the library because the point is to compare a variant
// the library should NOT ship.
//
// `rust_static_svg.dart` 私有 `_replay` 动词/坐标解码器的两份拷贝，**唯一**区别
// 是两个缓冲区的静态类型（从而决定元素读取是类型化数据加载还是装箱的接口调用）。
// 放在基准里而不是库里，因为要比较的正是一个库**不应该**采用的变体。

ui.Path _replayTyped(Uint8List verbs, Float32List points) {
  final uiPath = ui.Path();
  var i = 0;
  for (var v = 0; v < verbs.length; v++) {
    switch (verbs[v]) {
      case 0:
        uiPath.moveTo(points[i], points[i + 1]);
        i += 2;
      case 1:
        uiPath.lineTo(points[i], points[i + 1]);
        i += 2;
      case 3:
        uiPath.cubicTo(
          points[i],
          points[i + 1],
          points[i + 2],
          points[i + 3],
          points[i + 4],
          points[i + 5],
        );
        i += 6;
      default:
        break;
    }
  }
  return uiPath;
}

ui.Path _replayInterface(List<int> verbs, List<double> points) {
  final uiPath = ui.Path();
  var i = 0;
  for (final verb in verbs) {
    switch (verb) {
      case 0:
        uiPath.moveTo(points[i], points[i + 1]);
        i += 2;
      case 1:
        uiPath.lineTo(points[i], points[i + 1]);
        i += 2;
      case 3:
        uiPath.cubicTo(
          points[i],
          points[i + 1],
          points[i + 2],
          points[i + 3],
          points[i + 4],
          points[i + 5],
        );
        i += 6;
      default:
        break;
    }
  }
  return uiPath;
}

/// Prints [results] as a stdout report block, and appends the same block to
/// the file named by the `SVGX_MICRO_OUT` environment variable when it is set.
///
/// The file is needed because Flutter's Windows runner reattaches stdout to
/// the parent console (`AttachConsole` + reopened stdio), so a caller that
/// pipes or redirects the process gets nothing — which makes the repeat-runner
/// in `tool/run_micro.ps1` impossible to build on stdout alone.
///
/// 把 [results] 作为报告块打印到 stdout；若设置了 `SVGX_MICRO_OUT` 环境变量，
/// 同时把同一份内容追加写入该文件。
///
/// 之所以需要写文件：Flutter 的 Windows runner 会把 stdout 重新挂到父控制台
/// （`AttachConsole` + 重开标准流），因此对该进程做管道/重定向的调用方什么都
/// 拿不到——只靠 stdout 就没法实现 `tool/run_micro.ps1` 里的重复运行器。
void printMicroReport(List<MicroResult> results) {
  final buf = StringBuffer()..writeln('=== MICRO BENCH REPORT ===');
  for (final r in results) {
    buf.writeln(r.toString());
  }
  buf.writeln('=== END MICRO BENCH REPORT ===');
  print(buf.toString());
  final outPath = Platform.environment['SVGX_MICRO_OUT'];
  if (outPath != null && outPath.isNotEmpty) {
    File(outPath).writeAsStringSync(buf.toString(), mode: FileMode.append);
  }
}
