// Tests for the lossless mask-layer-bounds optimization in
// `animated_svg_painter.dart` (see
// `SvgXAnimationQuality.tightMaskLayerBounds`): that sizing a `<mask>`'s two
// `saveLayer` offscreen targets to the mask content's own bounds produces
// pixel-identical output to leaving them unbounded, that it actually shrinks
// (and sometimes removes entirely) those layers, and that it falls back to
// unbounded layers for the cases where the bounds cannot be established
// safely.
//
// `animated_svg_painter.dart` 里无损的 mask 图层边界优化（见
// `SvgXAnimationQuality.tightMaskLayerBounds`）的测试：把 `<mask>` 的两个
// `saveLayer` 离屏目标按 mask 内容自身边界分配后，输出与保持无界时逐像素一致；
// 这些图层确实变小了（有时被整个去掉）；以及在边界无法安全确定的情形下会回退到
// 无界图层。

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/animated_svg_painter.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';
import 'package:svgx/src/animation/svg_theme.dart';
import 'package:svgx/src/animation/svgx_animation_quality.dart';

const _tight = SvgXAnimationQuality();
const _unbounded = SvgXAnimationQuality(tightMaskLayerBounds: false);

SvgDocument _parse(String body, {double viewBox = 100}) =>
    parseAnimatedSvgDocument(
      '<svg xmlns="http://www.w3.org/2000/svg" width="$viewBox" '
      'height="$viewBox" viewBox="0 0 $viewBox $viewBox">$body</svg>',
    );

/// Paints [document] through [canvas] at [time] with the given quality
/// profile.
///
/// 用给定画质配置，在 [time] 把 [document] 绘制到 [canvas]。
void _paint(
  Canvas canvas,
  SvgDocument document, {
  required Duration time,
  required SvgXAnimationQuality quality,
  required double size,
}) {
  AnimatedSvgPainter(
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
  ).paint(canvas, Size(size, size));
}

Future<ByteData> _pixels(
  SvgDocument document, {
  required Duration time,
  required SvgXAnimationQuality quality,
  double size = 100,
}) async {
  final recorder = ui.PictureRecorder();
  _paint(Canvas(recorder), document, time: time, quality: quality, size: size);
  final image = await recorder.endRecording().toImage(
    size.toInt(),
    size.toInt(),
  );
  return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
}

/// Number of pixels differing between the tight-bounds and unbounded renders
/// of [document] at [time], plus the largest single-channel difference.
///
/// 在 [time] 下，[document] 的紧边界渲染与无界渲染之间有多少像素不同，以及最大的
/// 单通道差值。
Future<
  ({int pixels, int maxChannelDelta, int materialPixels, double alphaRatio})
>
_divergence(
  SvgDocument document, {
  Duration time = Duration.zero,
  double size = 100,
}) async {
  final tight = await _pixels(
    document,
    time: time,
    quality: _tight,
    size: size,
  );
  final unbounded = await _pixels(
    document,
    time: time,
    quality: _unbounded,
    size: size,
  );
  var pixels = 0;
  var materialPixels = 0;
  var maxChannelDelta = 0;
  var tightAlpha = 0;
  var unboundedAlpha = 0;
  for (var i = 0; i < size.toInt() * size.toInt(); i++) {
    var largest = 0;
    for (var channel = 0; channel < 4; channel++) {
      final delta =
          (tight.getUint8(i * 4 + channel) -
                  unbounded.getUint8(i * 4 + channel))
              .abs();
      if (delta > largest) largest = delta;
    }
    if (largest != 0) pixels++;
    if (largest > _rasterNoiseTolerance) materialPixels++;
    if (largest > maxChannelDelta) maxChannelDelta = largest;
    tightAlpha += tight.getUint8(i * 4 + 3);
    unboundedAlpha += unbounded.getUint8(i * 4 + 3);
  }
  return (
    pixels: pixels,
    maxChannelDelta: maxChannelDelta,
    materialPixels: materialPixels,
    alphaRatio: unboundedAlpha == 0
        ? (tightAlpha == 0 ? 1.0 : double.infinity)
        : tightAlpha / unboundedAlpha,
  );
}

/// Largest single-channel difference attributable to the offscreen buffer's
/// own rasterization rather than to a change in what is masked — see the
/// equivalence group's comment for the two mechanisms measured (edge
/// antialiasing rounding, and gradient dither keyed on the buffer's origin).
///
/// 可归因于离屏缓冲自身光栅化、而非"被遮罩的内容变了"的最大单通道差值——两种实测
/// 机制（边缘抗锯齿舍入、以及以缓冲原点为种子的渐变抖动）见等价性测试组的注释。
const int _rasterNoiseTolerance = 8;

/// The bounds the painter gives [document]'s single `<mask>` definition's two
/// `saveLayer`s at [time], or null when it keeps them unbounded.
///
/// 绘制器在 [time] 给 [document] 唯一 `<mask>` 定义的两个 `saveLayer` 所用的
/// 边界；保持无界时为 null。
Rect? _maskLayerBounds(
  SvgDocument document, {
  Duration time = Duration.zero,
  double size = 100,
}) {
  final recorder = ui.PictureRecorder();
  final painter = AnimatedSvgPainter(
    root: document.root,
    intrinsicSize: Size(document.width, document.height),
    clock: ValueNotifier(time),
    theme: const SvgTheme(),
    fit: BoxFit.contain,
    alignment: Alignment.center,
    gradients: document.gradients,
    clipPaths: document.clipPaths,
    masks: document.masks,
    quality: _tight,
  )..paint(Canvas(recorder), Size(size, size));
  recorder.endRecording();
  return painter.debugMaskLayerBounds(document.masks.values.single);
}

void main() {
  group('pixel equivalence with the unbounded pipeline', () {
    // Every case below is rendered twice — tight bounds vs unbounded layers —
    // and compared channel by channel.
    //
    // Most cases are bit-identical. The two that are not were traced to the
    // offscreen buffer itself rather than to what gets masked — an
    // explicitly-bounded layer is allocated at a different size and origin
    // than a clip-sized one, and Skia's rasterization into it is keyed on
    // that:
    //
    //  - the black-hole mask at 100px: two pixels on the *interior* hole edge,
    //    (40,48) and (40,49), differ by 8/255 of alpha. Antialiasing rounding.
    //    It cannot be coverage clipping — those pixels sit 20 user units
    //    inside the layer bounds, not at their edge.
    //  - the gradient mask at 100px: 163 pixels scattered through the
    //    gradient's *interior* differ by exactly 1/255, tracking the ramp.
    //    Gradient dither, whose pattern is keyed on the buffer origin.
    //
    // So the assertions do not use a "differing pixel count" budget, which
    // would have to be loose enough to hide a real fault. They pin the two
    // things a coverage-clipping bug cannot satisfy: no single pixel moves by
    // more than raster noise, and the frame's total alpha is unchanged.
    //
    // 下面每个用例都渲染两次——紧边界 vs 无界图层——逐通道比较。
    //
    // 多数用例逐位一致。不一致的两个已追查到原因在离屏缓冲本身，而不在"被遮罩的内容"
    // ——显式指定 bounds 的图层与按裁剪区分配的图层，分配的尺寸与原点都不同，而
    // Skia 往里光栅化的结果与之相关：
    //
    //  - 黑洞 mask 在 100px 下：*内部*洞边缘的两个像素 (40,48)、(40,49) 的 alpha
    //    差 8/255，属抗锯齿舍入。不可能是覆盖度被裁：这两个像素位于图层边界内侧
    //    20 个用户单位处，不在边缘。
    //  - 渐变 mask 在 100px 下：渐变*内部*散布的 163 个像素恰好差 1/255，且随渐变
    //    斜坡变化，属渐变抖动，其图案以缓冲原点为种子。
    //
    // 因此断言不采用"差异像素数量"预算——那必须放宽到足以掩盖真实故障。断言钉的是
    // 覆盖度被裁时不可能满足的两件事：没有任何单个像素的变化超过光栅噪声，且整帧的
    // 总 alpha 不变。
    final cases = <String, String>{
      'a single white shape':
          '<mask id="m">'
          '<circle cx="40" cy="40" r="18" fill="#fff"/>'
          '</mask>'
          '<rect width="100" height="100" fill="#f00" mask="url(#m)"/>',
      'a white shape with a black hole punched in it':
          '<mask id="m">'
          '<circle cx="50" cy="50" r="30" fill="#fff"/>'
          '<circle cx="50" cy="50" r="10" fill="#000"/>'
          '</mask>'
          '<rect width="100" height="100" fill="#0f0" mask="url(#m)"/>',
      'a mid-grey (fractional coverage) shape':
          '<mask id="m">'
          '<rect x="10" y="10" width="40" height="40" fill="#7a7a7a"/>'
          '</mask>'
          '<rect width="100" height="100" fill="#00f" mask="url(#m)"/>',
      'a gradient-filled mask':
          '<linearGradient id="g">'
          '<stop offset="0" stop-color="#000"/>'
          '<stop offset="1" stop-color="#fff"/>'
          '</linearGradient>'
          '<mask id="m">'
          '<rect x="20" y="20" width="50" height="50" fill="url(#g)"/>'
          '</mask>'
          '<rect width="100" height="100" fill="#f0f" mask="url(#m)"/>',
      'a stroked mask (round caps and joins)':
          '<mask id="m">'
          '<path d="M20 20L80 20L80 80" fill="none" stroke="#fff" '
          'stroke-width="12" stroke-linecap="round" stroke-linejoin="round"/>'
          '</mask>'
          '<rect width="100" height="100" fill="#ff0" mask="url(#m)"/>',
      'a stroked mask with default (miter) joins':
          '<mask id="m">'
          '<path d="M20 30L50 20L80 30" fill="none" stroke="#fff" '
          'stroke-width="10"/>'
          '</mask>'
          '<rect width="100" height="100" fill="#ff0" mask="url(#m)"/>',
      'a stroke width inherited from a wrapping group':
          '<mask id="m">'
          '<g stroke="#fff" stroke-width="14">'
          '<path d="M25 25L75 75" fill="none"/>'
          '</g></mask>'
          '<rect width="100" height="100" fill="#0ff" mask="url(#m)"/>',
      'geometry animated by <animate>':
          '<mask id="m">'
          '<circle cx="50" cy="50" fill="#fff" r="5">'
          '<animate attributeName="r" dur="1s" values="5;45" '
          'repeatCount="indefinite"/></circle>'
          '</mask>'
          '<rect width="100" height="100" fill="#f00" mask="url(#m)"/>',
      'a dashed stroke animated by stroke-dashoffset':
          '<mask id="m">'
          '<path d="M10 50L90 50" fill="none" stroke="#fff" stroke-width="16" '
          'stroke-dasharray="80" stroke-dashoffset="80">'
          '<animate attributeName="stroke-dashoffset" dur="1s" values="80;0" '
          'fill="freeze"/></path>'
          '</mask>'
          '<rect width="100" height="100" fill="#f00" mask="url(#m)"/>',
      'mask content moved by <animateTransform>':
          '<mask id="m">'
          '<rect x="0" y="0" width="40" height="100" fill="#fff">'
          '<animateTransform attributeName="transform" type="translate" '
          'dur="1s" values="-40 0;60 0" repeatCount="indefinite"/>'
          '</rect></mask>'
          '<rect width="100" height="100" fill="#00f" mask="url(#m)"/>',
      'mask content rotated by <animateTransform>':
          '<mask id="m">'
          '<rect x="30" y="45" width="60" height="10" fill="#fff">'
          '<animateTransform attributeName="transform" type="rotate" '
          'dur="1s" values="0 50 50;180 50 50" repeatCount="indefinite"/>'
          '</rect></mask>'
          '<rect width="100" height="100" fill="#0f0" mask="url(#m)"/>',
      'mask content moved by <animateMotion>':
          '<mask id="m">'
          '<rect x="0" y="0" width="30" height="30" fill="#fff">'
          '<animateMotion dur="1s" path="M0 0L70 70" '
          'repeatCount="indefinite"/>'
          '</rect></mask>'
          '<rect width="100" height="100" fill="#f0f" mask="url(#m)"/>',
      'mask content under a static group transform':
          '<mask id="m">'
          '<g transform="translate(0 60) scale(2 1)">'
          '<rect x="0" y="0" width="30" height="20" fill="#fff"/>'
          '</g></mask>'
          '<rect width="100" height="100" fill="#ff0" mask="url(#m)"/>',
      'a masked node that also carries its own transform':
          '<mask id="m">'
          '<rect x="10" y="10" width="30" height="30" fill="#fff"/>'
          '</mask>'
          '<rect width="100" height="100" fill="#f00" mask="url(#m)" '
          'transform="translate(20 5) rotate(15)"/>',
      'a masked node that also carries a clip-path':
          '<clipPath id="c">'
          '<rect x="0" y="0" width="100" height="30"/></clipPath>'
          '<mask id="m">'
          '<rect x="10" y="10" width="60" height="60" fill="#fff"/>'
          '</mask>'
          '<rect width="100" height="100" fill="#0f0" mask="url(#m)" '
          'clip-path="url(#c)"/>',
      'a mask whose child carries its own mask':
          '<mask id="inner">'
          '<rect x="0" y="0" width="50" height="100" fill="#fff"/></mask>'
          '<mask id="m">'
          '<rect x="10" y="10" width="80" height="80" fill="#fff" '
          'mask="url(#inner)"/>'
          '</mask>'
          '<rect width="100" height="100" fill="#00f" mask="url(#m)"/>',
      'a mask defining no geometry at all':
          '<mask id="m"></mask>'
          '<rect width="100" height="100" fill="#f00" mask="url(#m)"/>',
      'a mask whose only shape is fill="none"':
          '<mask id="m">'
          '<circle cx="50" cy="50" r="20" fill="none"/></mask>'
          '<rect width="100" height="100" fill="#f00" mask="url(#m)"/>',
      // Fallback cases: the bounds cannot be established safely, so the
      // painter must keep the unbounded layers and therefore match trivially
      // — these guard the bail-outs actually firing rather than the bounds
      // being computed too tightly.
      //
      // 回退用例：边界无法安全确定，绘制器必须保持无界图层，因此天然一致——它们
      // 守的是"放弃分支确实触发了"，而不是"边界算得太紧"。
      'a blur on the masked node itself':
          '<mask id="m">'
          '<rect x="20" y="20" width="60" height="60" fill="#fff"/></mask>'
          '<filter id="b"><feGaussianBlur stdDeviation="4"/></filter>'
          '<rect width="100" height="100" fill="#f00" mask="url(#m)" '
          'filter="url(#b)"/>',
      'a blur inside the mask definition':
          '<filter id="b">'
          '<feGaussianBlur stdDeviation="5"/></filter>'
          '<mask id="m">'
          '<rect x="30" y="30" width="40" height="40" fill="#fff" '
          'filter="url(#b)"/></mask>'
          '<rect width="100" height="100" fill="#0f0" mask="url(#m)"/>',
      'a <text> mask':
          '<mask id="m">'
          '<text x="10" y="60" font-size="40" fill="#fff">Hi</text></mask>'
          '<rect width="100" height="100" fill="#00f" mask="url(#m)"/>',
      'a mask shape painted through a style attribute':
          '<mask id="m">'
          '<rect x="20" y="20" width="40" height="40" style="fill:#fff"/>'
          '</mask>'
          '<rect width="100" height="100" fill="#ff0" mask="url(#m)"/>',
    };

    for (final entry in cases.entries) {
      test('${entry.key} renders identically', () async {
        final document = _parse(entry.value);
        // Several instants, so an animated mask is checked mid-flight and not
        // just at rest, and two render scales, so the device-pixel padding is
        // exercised both above and below one user unit per pixel.
        //
        // 取多个时刻，使带动画的 mask 在运动中途也被检查，而不只是静止态；取两个
        // 渲染尺度，使"每像素一个用户单位"上下两侧的设备像素外扩都被覆盖。
        for (final ms in const [0, 137, 480, 999]) {
          for (final size in const [100.0, 32.0]) {
            final divergence = await _divergence(
              document,
              time: Duration(milliseconds: ms),
              size: size,
            );
            final where =
                '${entry.key} at ${ms}ms, ${size.toInt()}px '
                '(${divergence.pixels} px differ, max channel delta '
                '${divergence.maxChannelDelta}, alpha ratio '
                '${divergence.alphaRatio.toStringAsFixed(5)})';
            // No pixel may move by more than raster noise. Clipping real
            // coverage — the failure this optimization could plausibly cause —
            // shows up as whole regions at full alpha, which this catches
            // immediately.
            //
            // 任何像素的变化都不得超过光栅噪声。裁掉真实覆盖度——本优化真正可能造成
            // 的失效——表现为整片满 alpha 区域的差异，这一条会立刻抓到。
            expect(
              divergence.materialPixels,
              0,
              reason: 'material pixel change: $where',
            );
            // And in aggregate the frame must carry the same total coverage,
            // so many sub-tolerance losses cannot add up to a visible one.
            //
            // 且整帧的总覆盖度必须一致，使大量低于容差的损失无法累积成可见差异。
            expect(
              divergence.alphaRatio,
              closeTo(1, 0.0005),
              reason: 'total alpha shifted: $where',
            );
          }
        }
      });
    }
  });

  group('the layers actually shrink', () {
    test('a small mask sizes both layers to a fraction of the viewport', () {
      final document = _parse(
        '<mask id="m"><circle cx="40" cy="40" r="10" fill="#fff"/></mask>'
        '<rect width="100" height="100" fill="#f00" mask="url(#m)"/>',
      );
      final bounds = _maskLayerBounds(document);
      expect(bounds, isNotNull);
      // r=10 plus two logical pixels of padding, inside a 100x100 viewBox:
      // ~24x24 of user space, i.e. under 6% of the area the unbounded layer
      // would have taken.
      //
      // r=10 加两个逻辑像素外扩，位于 100x100 的 viewBox 内：约 24x24 用户空间，
      // 即不到无界图层所占面积的 6%。
      expect(bounds!.width, lessThan(30));
      expect(bounds.height, lessThan(30));
      expect(bounds.contains(const Offset(40, 40)), isTrue);
      expect(
        bounds.width * bounds.height / (100 * 100),
        lessThan(0.06),
        reason: 'offscreen area, relative to the unbounded layer',
      );
    });

    test('a stroked mask sizes to the stroke, not to the viewport', () {
      final document = _parse(
        '<mask id="m">'
        '<path d="M40 40L60 40" fill="none" stroke="#fff" stroke-width="6"/>'
        '</mask>'
        '<rect width="100" height="100" fill="#f00" mask="url(#m)"/>',
      );
      final bounds = _maskLayerBounds(document);
      expect(bounds, isNotNull);
      // The stroke itself is 6 wide; the inflation is deliberately generous
      // (2x the width, for miter joins) but must still be far short of the
      // viewport.
      //
      // 描边本身宽 6；外扩刻意取宽松值（宽度的 2 倍，为尖角连接留量），但仍必须远
      // 小于整个视口。
      expect(bounds!.height, lessThan(40));
      expect(bounds.width, lessThan(60));
      expect(bounds.contains(const Offset(50, 40)), isTrue);
    });

    test(
      'a mask whose coverage is entirely off-viewport skips the node outright',
      () async {
        // The reveal-mask shape starts fully to the left of the viewBox, so
        // nothing this node paints can be visible — `_paintNode` returns before
        // opening either offscreen layer rather than opening two and having
        // `dstIn` erase everything they contain.
        //
        // 揭示 mask 的形状起始时完全位于 viewBox 左侧，因此本节点画的一切都不可能
        // 可见——`_paintNode` 在开启任一离屏图层之前就返回，而不是开两个图层再让
        // `dstIn` 把里面的一切擦掉。
        final document = _parse(
          '<mask id="m">'
          '<rect x="-60" y="0" width="50" height="100" fill="#fff">'
          '<animateTransform attributeName="transform" type="translate" '
          'dur="1s" values="0 0;120 0" fill="freeze"/>'
          '</rect></mask>'
          '<rect width="100" height="100" fill="#f00" mask="url(#m)"/>',
        );
        final atRest = _maskLayerBounds(document);
        expect(atRest, isNotNull);
        expect(
          atRest!.overlaps(const Rect.fromLTWH(0, 0, 100, 100)),
          isFalse,
          reason: 'no overlap with the viewport is what triggers the skip',
        );
        // Both pipelines must agree that the frame is empty.
        // 两条管线都必须认为这一帧是空的。
        final pixels = await _pixels(
          document,
          time: Duration.zero,
          quality: _tight,
        );
        for (var i = 0; i < 100 * 100; i++) {
          expect(pixels.getUint8(i * 4 + 3), 0);
        }
        // ... and once it has slid in, the mask is bounded but visible again.
        // ……而一旦滑进来，mask 重新变成"有界但可见"。
        final midway = _maskLayerBounds(
          document,
          time: const Duration(milliseconds: 700),
        );
        expect(midway, isNotNull);
        expect(midway!.overlaps(const Rect.fromLTWH(0, 0, 100, 100)), isTrue);
      },
    );

    test('an indeterminate mask keeps unbounded layers', () {
      final document = _parse(
        '<mask id="m">'
        '<text x="10" y="60" font-size="30" fill="#fff">Hi</text></mask>'
        '<rect width="100" height="100" fill="#f00" mask="url(#m)"/>',
      );
      expect(_maskLayerBounds(document), isNull);
    });

    test('the switch off restores unbounded layers', () async {
      final document = _parse(
        '<mask id="m"><circle cx="40" cy="40" r="10" fill="#fff"/></mask>'
        '<rect width="100" height="100" fill="#f00" mask="url(#m)"/>',
      );
      // Nothing to read off the painter in this direction — `_paintNode` never
      // computes bounds when the switch is off — so this pins the switch's
      // observable contract instead: the unbounded render is the reference the
      // whole equivalence group above compares against, and it must still be
      // reachable.
      //
      // 这个方向上绘制器身上没有可读的东西——开关关闭时 `_paintNode` 根本不计算
      // 边界——因此这里钉的是开关的可观察契约：无界渲染是上面整组等价性测试所对照
      // 的基准，它必须仍然可达。
      expect(_unbounded.tightMaskLayerBounds, isFalse);
      final pixels = await _pixels(
        document,
        time: Duration.zero,
        quality: _unbounded,
      );
      expect(pixels.getUint8((40 * 100 + 40) * 4 + 3), 255);
      expect(pixels.getUint8((5 * 100 + 5) * 4 + 3), 0);
    });
  });
}
