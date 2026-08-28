// Minimal regression harness for the real-device black-screen bug fixed in
// `lib/src/animation/animated_svg_painter.dart`: a bare
// `Scaffold(GridView.builder(...))` of concurrently-animating `Svgx.string`
// icons, mounted all at once on the first frame with no RepaintBoundary,
// scrolling, or instrumentation of its own. Before the fix, ~100 items went
// permanently black on a Huawei STG-AL00 (Impeller GLES) because every
// `<mask>`-using icon allocated full-screen offscreen render targets.
//
// Run with `--dart-define=LIB=bare --dart-define=ITEMS=1000`.
//
// `lib/src/animation/animated_svg_painter.dart` 修复的真机黑屏 bug 的最小回归
// 用例：一个光秃秃的 `Scaffold(GridView.builder(...))`，格子是并发动画的
// `Svgx.string` 图标，首帧一次性全部挂载，自身不带 RepaintBoundary、滚动或任何
// 探针。修复前在华为 STG-AL00（Impeller GLES）上约 100 项就会永久黑屏，原因是
// 每个用了 `<mask>` 的图标都在分配全屏离屏渲染目标。
//
// 运行方式：`--dart-define=LIB=bare --dart-define=ITEMS=1000`。

import 'package:flutter/material.dart';
import 'package:svgx/svgx.dart';

import 'anim_icon_gen.dart';

/// A grid of [itemCount] concurrently-animating SVG icons, all mounted on the
/// first frame.
///
/// 一个含 [itemCount] 个并发动画 SVG 图标的网格，全部在首帧挂载。
class BareAnimGrid extends StatefulWidget {
  /// Creates the grid. / 创建网格。
  const BareAnimGrid({super.key, required this.itemCount});

  /// Number of concurrently-animating icons. / 并发动画图标数量。
  final int itemCount;

  @override
  State<BareAnimGrid> createState() => _BareAnimGridState();
}

class _BareAnimGridState extends State<BareAnimGrid> {
  /// The generated icon sources, built once. / 生成的图标源，只构建一次。
  late final List<String> _icons = generateAnimIcons(widget.itemCount);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
        ),
        itemCount: widget.itemCount,
        itemBuilder: (context, index) =>
            Svgx.string(_icons[index], width: 32, height: 32),
      ),
    );
  }
}
