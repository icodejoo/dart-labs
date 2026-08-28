// Entry point for the svgx-vs-flutter_svg 1000-icon benchmark. The library
// under test and cycle count are chosen via --dart-define so the benchmark
// runs unattended under `flutter run --profile` and prints its report to
// stdout, which the harness scrapes.
//
// svgx 对比 flutter_svg 的千图标基准入口。被测库与滚动轮次数通过 --dart-define
// 选择，这样可以在 `flutter run --profile` 下无人值守运行，报告打印到 stdout，
// 由外部脚本抓取。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show debugProfileLayoutsEnabled, debugProfilePaintsEnabled;
import 'package:svgx/svgx.dart';

import 'anim_bench_screen.dart';
import 'anim_fps_bench_screen.dart';
import 'bare_anim_grid.dart';
import 'bench_screen.dart';
import 'compare_bench_screen.dart';
import 'micro_bench.dart';
import 'one_anim_bench_screen.dart';

const _libName = String.fromEnvironment('LIB', defaultValue: 'svgx');
const _cycles = int.fromEnvironment('CYCLES', defaultValue: 6);
const _items = int.fromEnvironment('ITEMS', defaultValue: 1000);
const _holdSeconds = int.fromEnvironment('HOLD', defaultValue: 6);

// `PROFILEWIDGETS=1` turns on the framework's own fine-grained timeline
// instrumentation for the whole run. Read as a string compared against
// '1'/'true' rather than through `bool.fromEnvironment`, for the reason
// `anim_fps_bench_screen.dart` documents at length (that constructor accepts
// ONLY the exact strings "true"/"false", so `=1` silently evaluates false and
// costs a whole wasted measurement round).
//
// What it buys, and why the build phase had never been decomposed before: with
// these three flags off — the default, including under `flutter run --profile`
// — the engine timeline carries only the coarse `BUILD` / `LAYOUT` / `PAINT`
// slices, so `tool/capture_timeline.dart` can say "BUILD cost 14ms" and
// nothing more. With them on, `Element.rebuild`,
// `RenderObject.layout` and `PaintingContext.paintChild` each open a slice
// NAMED AFTER the widget / render object being processed
// (`framework.dart`'s `FlutterTimeline.startSync('${widget.runtimeType}')`,
// `object.dart`'s equivalents for layout and paint), which is what makes a
// per-mechanism cost list possible at all: `SvgxAnimated`, `CustomPaint`,
// `RenderCustomPaint`, `RenderConstrainedBox`, `RenderSliverGrid` all become
// separately-summed line items.
//
// All three are `!kReleaseMode`-guarded in the framework, so they are live in
// profile mode and cost nothing in release. They are NOT free: every slice is
// a real timeline write, so a `PROFILEWIDGETS=1` run's absolute build numbers
// are inflated and must never be compared against a normal run's. Use it for
// *attribution* (which slice dominates), and re-measure the headline numbers
// with it off.
//
// `PROFILEWIDGETS=1` 为整次运行打开框架自带的细粒度时间线埋点。按字符串读取并与
// '1'/'true' 比较，而不用 `bool.fromEnvironment`，理由见
// `anim_fps_bench_screen.dart` 的详细记录（那个构造器**只**接受精确字符串
// "true"/"false"，因此 `=1` 会静默为 false，白费一整轮测量）。
//
// 它带来什么、以及为什么 build 阶段此前从未被拆解过：这三个开关关闭时——也就是
// 默认状态，`flutter run --profile` 下也一样——引擎时间线里只有粗粒度的
// `BUILD` / `LAYOUT` / `PAINT` 三个 slice，于是
// `tool/capture_timeline.dart` 只能说出"BUILD 花了 14ms"，再无下文。打开后，
// `Element.rebuild`、`RenderObject.layout`、`PaintingContext.paintChild` 各自会
// 开一个**以被处理的控件/渲染对象命名**的 slice（framework.dart 里的
// `FlutterTimeline.startSync('${widget.runtimeType}')`，以及 object.dart 里布局
// 与绘制的对应写法），这正是"按子机制归因"得以成立的前提：`SvgxAnimated`、
// `CustomPaint`、`RenderCustomPaint`、`RenderConstrainedBox`、`RenderSliverGrid`
// 会成为可以分别累加的独立条目。
//
// 三个开关在框架里都由 `!kReleaseMode` 守卫，因此 profile 模式下生效、release
// 下零成本。但它们**不是免费的**：每个 slice 都是一次真实的时间线写入，所以
// `PROFILEWIDGETS=1` 那次运行的 build 绝对值是被抬高过的，绝不能拿去和普通运行
// 比较。它用于**归因**（哪个 slice 占大头），头条数字要关掉它再测。
const String _profileWidgetsRaw = String.fromEnvironment('PROFILEWIDGETS');
const bool _profileWidgets =
    _profileWidgetsRaw == '1' || _profileWidgetsRaw == 'true';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_profileWidgets) {
    debugProfileBuildsEnabled = true;
    debugProfileLayoutsEnabled = true;
    debugProfilePaintsEnabled = true;
  }
  // Required once before any parseSvg() FFI call; forgetting this makes
  // SvgxStatic silently fall back to a blank SizedBox on every render (its
  // errorBuilder is null by default), which would otherwise make this
  // benchmark measure "building empty boxes" instead of real svgx work.
  //
  // 首次调用 parseSvg() 前必须初始化一次；漏掉这步会导致 SvgxStatic 每次渲染都
  // 静默回退成空白 SizedBox（默认 errorBuilder 为空），基准就会变成在测「渲染
  // 空盒子」而非 svgx 的真实开销。
  await RustLib.init();
  if (_libName == 'micro') {
    // Deterministic Dart-side microbenchmarks: no widget tree, no GPU, no
    // scrolling — see micro_bench.dart for why the scrolling suite alone
    // can't attribute Dart-level improvements on this machine.
    //
    // 确定性的 Dart 侧微基准：无控件树、无 GPU、无滚动——为什么单靠滚动基准
    // 无法在本机归因 Dart 层改进，见 micro_bench.dart。
    printMicroReport(runMicroBenchmarks());
    exit(0);
  }
  if (_libName == 'bare') {
    runApp(MaterialApp(home: BareAnimGrid(itemCount: _items)));
    return;
  }
  if (_libName == 'anim') {
    runApp(const MaterialApp(home: AnimBenchRunner()));
    return;
  }
  // Single-icon steady state: what ONE animated icon costs per frame, with no
  // concurrency to amortize it. See one_anim_bench_screen.dart's header for why
  // this is a different question from the 1000-icon grid above.
  //
  // 单图标稳态：**一个**动画图标每帧的成本，没有并发可以摊薄它。为什么这与上面的
  // 千图标网格是两个不同的问题，见 one_anim_bench_screen.dart 的文件头说明。
  if (_libName == 'one_anim') {
    runApp(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: OneAnimBenchScreen(),
      ),
    );
    return;
  }
  if (_libName == 'anim_fps') {
    runApp(
      MaterialApp(
        home: AnimFpsBenchRunner(
          itemCount: _items,
          cycles: _cycles,
          holdSeconds: _holdSeconds,
        ),
      ),
    );
    return;
  }
  if (_libName == 'compare') {
    // Single-build sequential mode: runs svgx static -> flutter_svg static ->
    // anim -> anim_fps, all inside this one process, then prints one
    // consolidated report. See compare_bench_screen.dart for why this exists
    // (same-session paired comparison, one compile instead of up to four).
    //
    // 单编译顺序模式：在这一个进程内依次跑完 svgx 静态 -> flutter_svg 静态 ->
    // anim -> anim_fps，再打印一份汇总报告。存在原因见
    // compare_bench_screen.dart（同一时段配对复测，一次编译代替最多四次）。
    runApp(
      MaterialApp(
        home: CompareBenchRunner(itemCount: _items, cycles: _cycles),
      ),
    );
    return;
  }
  final lib = _libName == 'flutter_svg' ? BenchLib.flutterSvg : BenchLib.svgx;
  runApp(
    MaterialApp(
      home: BenchRunner(lib: lib, cycles: _cycles, itemCount: _items),
    ),
  );
}
