// Corpus-wide evidence for the lossless mask-layer-bounds optimization (see
// `SvgXAnimationQuality.tightMaskLayerBounds`), on the real 399-icon SMIL set:
//
//  1. correctness — every mask-bearing icon renders the same with the tight
//     layers as with the unbounded ones, at several instants and two sizes;
//  2. payoff — how much offscreen area the tight layers actually allocate
//     compared with the unbounded ones, which is the figure that matters on a
//     device where an offscreen pass costs by area (an icon-sized pass ~221us
//     vs a window-sized one ~43ms, both measured on a Huawei STG-AL00);
//  3. price — the UI-thread cost of computing those bounds every frame.
//
// Host-side and deterministic, so none of it depends on getting a clean
// measurement window on a shared physical device.
//
// 在真实 399 图标 SMIL 语料上，为无损的 mask 图层边界优化（见
// `SvgXAnimationQuality.tightMaskLayerBounds`）提供全语料证据：
//
//  1. 正确性——每个带 mask 的图标，在多个时刻、两种尺寸下，紧边界与无界渲染结果
//     一致；
//  2. 收益——紧边界实际分配的离屏面积相比无界少多少；在"离屏通道按面积计费"的设备
//     上这才是关键数字（华为 STG-AL00 实测：图标尺寸的通道约 221us，窗口尺寸的
//     约 43ms）；
//  3. 代价——每帧计算这些边界的 UI 线程开销。
//
// 全部主机侧、确定性，因此不依赖在共用真机上抢到干净的测量窗口。

import 'dart:ui' as ui;

import 'package:bench_app/anim_icons_real.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/animated_svg_painter.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';
import 'package:svgx/src/animation/svg_dom.dart';
import 'package:svgx/src/animation/svg_theme.dart';
import 'package:svgx/src/animation/svgx_animation_quality.dart';

const _tight = SvgXAnimationQuality();
const _unbounded = SvgXAnimationQuality(tightMaskLayerBounds: false);

/// Builds a painter for [document] at [time] under [quality].
///
/// 按 [quality] 为 [document] 在 [time] 构建绘制器。
AnimatedSvgPainter _painter(
  SvgDocument document,
  Duration time,
  SvgXAnimationQuality quality,
) => AnimatedSvgPainter(
  root: document.root,
  intrinsicSize: Size(document.width, document.height),
  clock: ValueNotifier(time),
  theme: const SvgTheme(),
  fit: BoxFit.contain,
  alignment: Alignment.center,
  gradients: document.gradients,
  clipPaths: document.clipPaths,
  masks: document.masks,
  quality: quality,
);

Future<ByteData> _pixels(
  SvgDocument document,
  Duration time,
  SvgXAnimationQuality quality,
  int size,
) async {
  final recorder = ui.PictureRecorder();
  _painter(
    document,
    time,
    quality,
  ).paint(Canvas(recorder), Size(size.toDouble(), size.toDouble()));
  final image = await recorder.endRecording().toImage(size, size);
  return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
}

/// Every mask definition referenced by a node in [document]'s tree, with
/// duplicates for nodes sharing one definition — one entry per offscreen
/// layer pair the exact pipeline would open.
///
/// [document] 树中被节点引用的每个 mask 定义；多个节点共用一个定义时会重复出现
/// ——精确管线会开的每一对离屏图层对应一条。
List<SvgNode> _referencedMasks(SvgDocument document) {
  final refs = <SvgNode>[];
  void walk(SvgNode node) {
    final id = node.maskId;
    if (id != null) {
      final def = document.masks[id];
      if (def != null) refs.add(def);
    }
    for (final child in node.children) {
      walk(child);
    }
  }

  walk(document.root);
  return refs;
}

void main() {
  final documents = <SvgDocument>[];
  for (final source in animIconsReal) {
    final document = parseAnimatedSvgDocument(source);
    if (document.masks.isNotEmpty) documents.add(document);
  }

  test('tight mask layers render the corpus identically', () async {
    var worstMaterialPixels = 0;
    var worstChannelDelta = 0;
    var worstAlphaDrift = 0.0;
    var worstIcon = '';
    var comparisons = 0;

    for (final document in documents) {
      for (final ms in const [0, 133, 617, 1500]) {
        for (final size in const [32, 96]) {
          final time = Duration(milliseconds: ms);
          final tight = await _pixels(document, time, _tight, size);
          final unbounded = await _pixels(document, time, _unbounded, size);
          comparisons++;
          var material = 0;
          var maxDelta = 0;
          var tightAlpha = 0;
          var unboundedAlpha = 0;
          for (var i = 0; i < size * size; i++) {
            var largest = 0;
            for (var channel = 0; channel < 4; channel++) {
              final delta =
                  (tight.getUint8(i * 4 + channel) -
                          unbounded.getUint8(i * 4 + channel))
                      .abs();
              if (delta > largest) largest = delta;
            }
            // 8/255 is the raster-noise ceiling established by
            // `svgx/test/animation/mask_layer_bounds_test.dart`, which traced
            // the two mechanisms (edge antialiasing rounding and gradient
            // dither, both keyed on the offscreen buffer's size and origin).
            //
            // 8/255 是 `svgx/test/animation/mask_layer_bounds_test.dart` 定下的
            // 光栅噪声上限，那里追查出了两种机制（边缘抗锯齿舍入与渐变抖动，都以
            // 离屏缓冲的尺寸与原点为种子）。
            if (largest > 8) material++;
            if (largest > maxDelta) maxDelta = largest;
            tightAlpha += tight.getUint8(i * 4 + 3);
            unboundedAlpha += unbounded.getUint8(i * 4 + 3);
          }
          final drift = unboundedAlpha == 0
              ? 0.0
              : (tightAlpha - unboundedAlpha).abs() / unboundedAlpha;
          if (material > worstMaterialPixels || drift > worstAlphaDrift) {
            worstIcon =
                '${document.root.attributes['id'] ?? ''} '
                '${ms}ms ${size}px';
          }
          if (material > worstMaterialPixels) worstMaterialPixels = material;
          if (maxDelta > worstChannelDelta) worstChannelDelta = maxDelta;
          if (drift > worstAlphaDrift) worstAlphaDrift = drift;
        }
      }
    }

    // ignore: avoid_print
    print(
      'maskBearingIcons=${documents.length} comparisons=$comparisons '
      'worstMaterialPixels=$worstMaterialPixels '
      'worstChannelDelta=$worstChannelDelta '
      'worstAlphaDrift=${(worstAlphaDrift * 100).toStringAsFixed(4)}% '
      'worstCase="$worstIcon"',
    );

    expect(documents, isNotEmpty, reason: 'sanity: corpus has masked icons');
    expect(
      worstMaterialPixels,
      0,
      reason: 'no pixel may move by more than raster noise',
    );
    expect(
      worstAlphaDrift,
      lessThan(0.001),
      reason: 'total coverage per frame must be unchanged',
    );
  });

  test('how much offscreen area the tight mask layers save', () {
    // Rendered at 32 logical px, the size the 1000-icon grid benchmark uses.
    // 按 32 逻辑像素渲染，与千图标网格基准所用尺寸一致。
    const size = 32.0;
    var refs = 0;
    var boundedRefs = 0;
    var skippedRefs = 0;
    var indeterminateRefs = 0;
    var areaShareSum = 0.0;
    final shares = <double>[];

    for (final document in documents) {
      final painter =
          _painter(document, const Duration(milliseconds: 400), _tight)
            // Paint once so the painter records the box-fit scale its padding is
            // derived from.
            // 先绘制一次，让绘制器记录下外扩量所依据的 box-fit 缩放。
            ..paint(Canvas(ui.PictureRecorder()), const Size(size, size));
      final viewBox = Rect.fromLTWH(0, 0, document.width, document.height);
      for (final def in _referencedMasks(document)) {
        refs++;
        // ignore: invalid_use_of_visible_for_testing_member
        final bounds = painter.debugMaskLayerBounds(def);
        if (bounds == null) {
          indeterminateRefs++;
          areaShareSum += 1; // unbounded: the whole viewport, as before
          shares.add(1);
          continue;
        }
        final visible = bounds.intersect(viewBox);
        if (visible.isEmpty) {
          skippedRefs++;
          shares.add(0);
          continue;
        }
        boundedRefs++;
        final share =
            (visible.width * visible.height) / (viewBox.width * viewBox.height);
        areaShareSum += share;
        shares.add(share);
      }
    }

    shares.sort();
    final median = shares.isEmpty ? 0.0 : shares[shares.length ~/ 2];
    // ignore: avoid_print
    print(
      'maskedNodeRefs=$refs bounded=$boundedRefs skippedEntirely=$skippedRefs '
      'indeterminate=$indeterminateRefs '
      'meanOffscreenAreaShare='
      '${(areaShareSum / refs * 100).toStringAsFixed(1)}% '
      'medianOffscreenAreaShare=${(median * 100).toStringAsFixed(1)}% '
      'offscreenAreaRemoved='
      '${((1 - areaShareSum / refs) * 100).toStringAsFixed(1)}%',
    );

    expect(refs, greaterThan(0));
    expect(
      boundedRefs,
      greaterThan(0),
      reason: 'the optimization must apply to real icon data',
    );
    expect(
      areaShareSum / refs,
      lessThan(1),
      reason: 'and it must allocate strictly less offscreen area than before',
    );
  });

  test('UI-thread cost of computing the mask layer bounds', () {
    /// Records every mask-bearing document once per simulated 60Hz frame.
    ///
    /// 每个模拟 60Hz 帧把每个带 mask 的文档各录制一次。
    ///
    /// [tight] — whether the bounds are computed. / 是否计算边界。
    ///
    /// [frames] — how many frames to simulate. / 模拟多少帧。
    ///
    /// Returns the elapsed wall time. / 返回墙钟耗时。
    Duration run({required bool tight, int frames = 60}) {
      final quality = tight ? _tight : _unbounded;
      final stopwatch = Stopwatch()..start();
      for (var frame = 0; frame < frames; frame++) {
        final time = Duration(microseconds: frame * 16667);
        for (final document in documents) {
          final recorder = ui.PictureRecorder();
          _painter(
            document,
            time,
            quality,
          ).paint(Canvas(recorder), const Size(32, 32));
          recorder.endRecording();
        }
      }
      stopwatch.stop();
      return stopwatch.elapsed;
    }

    run(tight: false, frames: 10);
    run(tight: true, frames: 10);

    // Min-of-N, the convention the other host-side micro benchmarks here use.
    // 取 N 次最小值，与这里其它主机侧微基准的口径一致。
    var unboundedBest = const Duration(days: 1);
    var tightBest = const Duration(days: 1);
    for (var i = 0; i < 5; i++) {
      final off = run(tight: false);
      if (off < unboundedBest) unboundedBest = off;
      final on = run(tight: true);
      if (on < tightBest) tightBest = on;
    }

    final offUs = unboundedBest.inMicroseconds / 60;
    final onUs = tightBest.inMicroseconds / 60;
    // ignore: avoid_print
    print(
      'maskBearingDocuments=${documents.length} '
      'unbounded_us_per_frame_all_docs=${offUs.toStringAsFixed(1)} '
      'tight_us_per_frame_all_docs=${onUs.toStringAsFixed(1)} '
      'delta_us=${(onUs - offUs).toStringAsFixed(1)} '
      'delta_us_per_document='
      '${((onUs - offUs) / documents.length).toStringAsFixed(2)}',
    );

    expect(documents, isNotEmpty);
  });
}
