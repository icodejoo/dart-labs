// Recorded evidence for two dart:ui/Skia facts that a rejected optimization
// direction turned on. Neither test exercises svgx code — they pin the
// renderer behaviour the decisions were made from, so revisiting the idea does
// not start by re-deriving it. The direction and why it was rejected on other
// grounds: `docs/performance-benchmarks.md`, section "2026-08-27 四轮".
//
//  1. Merging several non-overlapping masked icons into ONE shared
//     content-layer + coverage-layer pair is mathematically exact:
//     `BlendMode.dstIn` composites per pixel with no spatial coupling, so
//     icons that do not overlap cannot contaminate each other. Overlapping
//     ones can, and do.
//  2. A `<mask>`'s coverage layer cannot be collapsed into a direct
//     `dstIn` draw to save one offscreen pass: a draw only blends where its
//     own geometry covers, so content outside the mask shape is never erased.
//
// 为一个被否决的优化方向所依赖的两个 dart:ui/Skia 事实留下证据。两个测试都不涉及
// svgx 自身代码——它们钉住的是做决策时所依据的渲染器行为，使日后重新审视这个想法
// 时不必从头再推一遍。该方向是什么、以及它因其它原因被否决的过程：见
// `docs/performance-benchmarks.md` 的"2026-08-27 四轮"一节。
//
//  1. 把多个互不重叠的带 mask 图标合并进**一对**共享的内容图层 + 覆盖度图层，在
//     数学上是精确的：`BlendMode.dstIn` 逐像素合成、没有空间耦合，因此互不重叠的
//     图标不可能互相污染。重叠的则会，而且确实会。
//  2. `<mask>` 的覆盖度图层不能塌缩成一次直接的 `dstIn` 绘制来省掉一个离屏通道：
//     绘制只在自身几何覆盖处参与混合，因此 mask 形状之外的内容永远不会被擦掉。

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// The `luminanceToAlpha` coverage paint the animated painter's mask pipeline
/// uses — see `AnimatedSvgPainter._maskCoveragePaint`.
///
/// 动画绘制器 mask 管线所用的 `luminanceToAlpha` 覆盖度画笔——见
/// `AnimatedSvgPainter._maskCoveragePaint`。
Paint _coveragePaint() => Paint()
  ..blendMode = BlendMode.dstIn
  ..colorFilter = const ColorFilter.matrix(<double>[
    0, 0, 0, 0, 0, //
    0, 0, 0, 0, 0, //
    0, 0, 0, 0, 0, //
    0.2125, 0.7154, 0.0721, 0, 0,
  ]);

Future<ByteData> _render(void Function(Canvas) body) async {
  final recorder = ui.PictureRecorder();
  body(Canvas(recorder));
  final image = await recorder.endRecording().toImage(100, 100);
  return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
}

/// How many of the 100x100 pixels differ between [a] and [b], and by how much
/// at worst.
///
/// [a] 与 [b] 之间 100x100 个像素里有多少个不同，以及最大差值。
({int pixels, int maxChannelDelta}) _compare(ByteData a, ByteData b) {
  var pixels = 0;
  var maxChannelDelta = 0;
  for (var i = 0; i < 100 * 100; i++) {
    var largest = 0;
    for (var channel = 0; channel < 4; channel++) {
      final delta = (a.getUint8(i * 4 + channel) - b.getUint8(i * 4 + channel))
          .abs();
      if (delta > largest) largest = delta;
    }
    if (largest > 0) pixels++;
    if (largest > maxChannelDelta) maxChannelDelta = largest;
  }
  return (pixels: pixels, maxChannelDelta: maxChannelDelta);
}

/// One stand-in for a masked icon occupying [cell]: content is a filled body
/// plus a diagonal stroke, and the mask is a white disc with a black hole in
/// it and a mid-grey band across it — enough shapes and coverage levels that a
/// cross-icon leak would show.
///
/// 一个占据 [cell] 的带 mask 图标替身：内容是实心块加一条对角描边，mask 是带黑洞
/// 的白色圆盘再加一条中灰色横带——形状与覆盖度层级足够多，跨图标串扰会显现出来。
typedef _Cell = ({Rect cell, Color fill});

void _paintContent(Canvas canvas, _Cell icon) {
  canvas
    ..save()
    ..clipRect(icon.cell)
    ..drawRect(icon.cell.deflate(2), Paint()..color = icon.fill)
    ..drawLine(
      icon.cell.topLeft,
      icon.cell.bottomRight,
      Paint()
        ..color = const Color(0xFF00FF00)
        ..strokeWidth = 3,
    )
    ..restore();
}

void _paintMask(Canvas canvas, _Cell icon) {
  final center = icon.cell.center;
  canvas
    ..save()
    ..clipRect(icon.cell)
    ..drawCircle(
      center,
      icon.cell.width * 0.42,
      Paint()..color = const Color(0xFFFFFFFF),
    )
    ..drawCircle(
      center.translate(4, 4),
      icon.cell.width * 0.12,
      Paint()..color = const Color(0xFF000000),
    )
    ..drawRect(
      Rect.fromLTWH(icon.cell.left, center.dy, icon.cell.width, 3),
      Paint()..color = const Color(0xFF9A9A9A),
    )
    ..restore();
}

/// Renders [icons] the way the shipped painter does: one content layer and one
/// coverage layer per icon.
///
/// 按当前发布的绘制器方式渲染 [icons]：每个图标各一个内容图层与一个覆盖度图层。
Future<ByteData> _perIcon(List<_Cell> icons) => _render((canvas) {
  for (final icon in icons) {
    canvas.saveLayer(icon.cell, Paint());
    _paintContent(canvas, icon);
    canvas.saveLayer(icon.cell, _coveragePaint());
    _paintMask(canvas, icon);
    canvas
      ..restore()
      ..restore();
  }
});

/// Renders [icons] merged into a single shared layer pair over the union of
/// their cells — the rejected direction.
///
/// 把 [icons] 合并进覆盖其所有格子并集的**一对**共享图层来渲染——即被否决的方向。
Future<ByteData> _merged(List<_Cell> icons) => _render((canvas) {
  final union = icons.map((i) => i.cell).reduce((a, b) => a.expandToInclude(b));
  canvas.saveLayer(union, Paint());
  for (final icon in icons) {
    _paintContent(canvas, icon);
  }
  canvas.saveLayer(union, _coveragePaint());
  for (final icon in icons) {
    _paintMask(canvas, icon);
  }
  canvas
    ..restore()
    ..restore();
});

void main() {
  test('merging non-overlapping masked icons is pixel-exact', () async {
    const icons = <_Cell>[
      (cell: Rect.fromLTWH(0, 0, 50, 50), fill: Color(0xFFFF0000)),
      (cell: Rect.fromLTWH(50, 0, 50, 50), fill: Color(0xFF0000FF)),
      (cell: Rect.fromLTWH(0, 50, 50, 50), fill: Color(0xFFFFFF00)),
      (cell: Rect.fromLTWH(50, 50, 50, 50), fill: Color(0xFF00FFFF)),
    ];
    final difference = _compare(await _perIcon(icons), await _merged(icons));
    expect(
      difference.pixels,
      0,
      reason:
          'dstIn composites per pixel, so disjoint icons in one shared layer '
          'pair must render exactly as they do in their own layer pairs',
    );
  });

  test('merging OVERLAPPING masked icons is not', () async {
    // The negative control, and the reason a merge would need a runtime
    // disjointness proof rather than an assumption: where two icons' painted
    // regions overlap, the merged coverage layer holds the union of both
    // masks, so each icon's content is masked by the other's mask too.
    //
    // 反向对照，也是"合并必须在运行时证明互不重叠、而不能假设"的原因：两个图标绘制
    // 区域重叠处，合并后的覆盖度图层持有两者 mask 的并集，于是每个图标的内容也被
    // 对方的 mask 遮罩了。
    const icons = <_Cell>[
      (cell: Rect.fromLTWH(0, 0, 60, 60), fill: Color(0xFFFF0000)),
      (cell: Rect.fromLTWH(30, 30, 60, 60), fill: Color(0xFF0000FF)),
    ];
    final difference = _compare(await _perIcon(icons), await _merged(icons));
    expect(difference.pixels, greaterThan(0));
    expect(
      difference.maxChannelDelta,
      greaterThan(64),
      reason: 'and the contamination is gross, not a rounding artifact',
    );
  });

  test('a coverage layer cannot be collapsed into a direct dstIn draw', () async {
    // Why the mask pipeline needs its second offscreen layer at all, checked
    // rather than assumed: a `dstIn` *draw* blends only where its own geometry
    // covers, leaving everything outside the mask shape untouched — whereas
    // closing a `dstIn` *layer* applies the blend across the layer's whole
    // area, which is what erases the unmasked content.
    //
    // 为什么 mask 管线必须有第二个离屏图层——这是实测而非假设：`dstIn` *绘制*只在
    // 自身几何覆盖处混合，mask 形状之外的一切都不受影响；而关闭一个 `dstIn`
    // *图层*会把混合应用到整个图层区域，正是这一点擦掉了未被遮罩的内容。
    const bounds = Rect.fromLTWH(0, 0, 100, 100);
    final maskShape = ui.Path()
      ..addOval(Rect.fromCircle(center: const Offset(50, 50), radius: 30));

    final layered = await _render((canvas) {
      canvas
        ..saveLayer(bounds, Paint())
        ..drawRect(bounds, Paint()..color = const Color(0xFFFF0000))
        ..saveLayer(bounds, _coveragePaint())
        ..drawPath(maskShape, Paint()..color = const Color(0xFFFFFFFF))
        ..restore()
        ..restore();
    });
    final collapsed = await _render((canvas) {
      canvas
        ..saveLayer(bounds, Paint())
        ..drawRect(bounds, Paint()..color = const Color(0xFFFF0000))
        ..drawPath(
          maskShape,
          Paint()
            ..blendMode = BlendMode.dstIn
            ..color = const Color(0xFF000000),
        )
        ..restore();
    });

    final difference = _compare(layered, collapsed);
    // The collapsed form keeps the whole red rect and merely leaves the disc
    // alone, so the two differ across most of the frame.
    //
    // 塌缩形式保留了整个红色矩形、只是没有动圆盘，因此两者在画面大部分区域都不同。
    expect(difference.pixels, greaterThan(5000));
    expect(difference.maxChannelDelta, 255);
  });
}
