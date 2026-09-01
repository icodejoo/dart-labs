// Regression test for `AnimatedSvgPainter._effectiveAttributes`: guards
// against a reuse optimization that was tried and reverted (see that
// method's doc comment) — allocating one mutated-in-place map per node across
// frames, instead of a fresh `Map.of(node.attributes)` every frame, broke
// `_geometryPath`'s identity-based cache-invalidation for non-`<path>` shapes
// (a `<rect>`/`<circle>`/etc.'s geometry silently froze at whatever shape was
// cached on the first frame). This test verifies a non-freezing animation's
// override correctly disappears once the animation ends — painting the same
// long-lived node tree at a later time must show the element's static
// position, not a leftover sampled value.
//
// `AnimatedSvgPainter._effectiveAttributes` 的回归测试：防止一个已经试过又
// 回滚的复用优化（见该方法的文档注释）再次出现——每帧分配一份跨帧原地修改
// 的表，而非每帧一份全新的 `Map.of(node.attributes)`，会破坏
// `_geometryPath` 对除 `<path>` 外形状的、基于身份的缓存失效机制（`<rect>`/
// `<circle>` 等的几何会悄悄冻结在第一帧缓存的形状上）。本测试验证一个不
// 定格的动画结束后，覆盖值会正确消失——晚些时候再次绘制同一棵长生命周期
// 节点树，必须显示元素的静态位置，而非残留的采样值。

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/animated_svg_painter.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';
import 'package:svgx/src/animation/svg_theme.dart';

const _size = 100;
const _sizeD = 100.0;

SvgDocument _parse(String body) => parseAnimatedSvgDocument(
  '<svg xmlns="http://www.w3.org/2000/svg" width="$_size" height="$_size" '
  'viewBox="0 0 $_size $_size">$body</svg>',
);

Future<ByteData> _renderPixelsAt(SvgDocument document, Duration t) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  // A fresh AnimatedSvgPainter every call, same as production (a new
  // painter is built every frame) — but sharing `document.root`, the same
  // long-lived SvgNode tree the cache lives on, across calls.
  //
  // 每次调用都建一个全新的 AnimatedSvgPainter（与生产环境一致——每帧都新建
  // 一个绘制器），但跨调用共享 `document.root`，即缓存所依附的那棵长生命
  // 周期节点树。
  AnimatedSvgPainter(
    root: document.root,
    intrinsicSize: Size(document.width, document.height),
    clock: ValueNotifier(t),
    theme: const SvgxTheme(),
    fit: BoxFit.fill,
    alignment: Alignment.center,
    gradients: document.gradients,
    clipPaths: document.clipPaths,
    masks: document.masks,
  ).paint(canvas, const Size(_sizeD, _sizeD));
  final image = await recorder.endRecording().toImage(_size, _size);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return bytes!;
}

int _alphaAt(ByteData pixels, int x, int y) =>
    pixels.getUint8((y * _size + x) * 4 + 3);

void main() {
  test(
    'a non-freezing animate resets to the static value after it ends, not '
    "leaking the last sampled position into a later frame's paint of the "
    'same node tree',
    () async {
      // Base (static) x=5; animate slides x from 0 to 80 over 1s with no
      // fill="freeze" (default fill="remove"), so at t=2s (past the end) the
      // element must show its static x=5, not the animation's end value (80)
      // or the mid-animation value from an earlier frame (~45).
      //
      // 静态基准 x=5；动画在 1s 内把 x 从 0 滑到 80，未设置 fill="freeze"
      // （默认 fill="remove"），因此 t=2s（结束之后）时元素必须显示其静态
      // x=5，而不是动画的终值（80）或早前某帧动画进行中的值（约 45）。
      final document = _parse(
        '<rect x="5" y="5" width="10" height="10" fill="#ff0000">'
        '<animate attributeName="x" values="0;80" dur="1s"/>'
        '</rect>',
      );

      // Frame 1: mid-animation (t=0.5s, x≈40-45).
      //
      // 第一帧：动画进行中（t=0.5s，x≈40-45）。
      final mid = await _renderPixelsAt(
        document,
        const Duration(milliseconds: 500),
      );
      // The rect should NOT be at its static x=5..15 position during the
      // animation.
      //
      // 动画进行中，矩形不应处于其静态 x=5..15 的位置。
      expect(_alphaAt(mid, 10, 10), 0);

      // Frame 2 (same node tree, later real time): animation has ended
      // without freezing — must show the static x=5..15 position, not a
      // leftover sampled value from frame 1.
      //
      // 第二帧（同一棵节点树，更晚的真实时间）：动画已结束且未定格——必须
      // 显示静态 x=5..15 位置，而非第一帧残留的采样值。
      final after = await _renderPixelsAt(document, const Duration(seconds: 2));
      expect(_alphaAt(after, 10, 10), 255);
      // And must not still show the animation's end-of-range position
      // (x≈80..90) or the mid-animation position from frame 1 (x≈40..50).
      //
      // 且不应仍显示动画终值区域（x≈80..90）或第一帧动画进行中的位置
      // （x≈40..50）。
      expect(_alphaAt(after, 85, 10), 0);
      expect(_alphaAt(after, 45, 10), 0);
    },
  );
}
