// Entry point for the svgx-vs-flutter_svg 1000-icon benchmark. The library
// under test and cycle count are chosen via --dart-define so the benchmark
// runs unattended under `flutter run --profile` and prints its report to
// stdout, which the harness scrapes.
//
// svgx 对比 flutter_svg 的千图标基准入口。被测库与滚动轮次数通过 --dart-define
// 选择，这样可以在 `flutter run --profile` 下无人值守运行，报告打印到 stdout，
// 由外部脚本抓取。

import 'package:flutter/material.dart';
import 'package:svgx/svgx.dart';

import 'anim_bench_screen.dart';
import 'anim_fps_bench_screen.dart';
import 'bench_screen.dart';
import 'compare_bench_screen.dart';

const _libName = String.fromEnvironment('LIB', defaultValue: 'svgx');
const _cycles = int.fromEnvironment('CYCLES', defaultValue: 6);
const _items = int.fromEnvironment('ITEMS', defaultValue: 1000);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Required once before any parseSvg() FFI call; forgetting this makes
  // SvgXStatic silently fall back to a blank SizedBox on every render (its
  // errorBuilder is null by default), which would otherwise make this
  // benchmark measure "building empty boxes" instead of real svgx work.
  //
  // 首次调用 parseSvg() 前必须初始化一次；漏掉这步会导致 SvgXStatic 每次渲染都
  // 静默回退成空白 SizedBox（默认 errorBuilder 为空），基准就会变成在测「渲染
  // 空盒子」而非 svgx 的真实开销。
  await RustLib.init();
  if (_libName == 'anim') {
    runApp(const MaterialApp(home: AnimBenchRunner()));
    return;
  }
  if (_libName == 'anim_fps') {
    runApp(
      MaterialApp(
        home: AnimFpsBenchRunner(itemCount: _items, cycles: _cycles),
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
