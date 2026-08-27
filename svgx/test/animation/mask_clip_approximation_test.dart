// Tests for the lossy mask-as-clip fast path in `animated_svg_painter.dart`
// (see `AnimatedSvgPainter.approximateMasks`): which mask definitions are
// eligible, that an eligible mask's approximated pixels match the exact
// pipeline's away from the antialiased boundary, that black mask content
// still punches holes, that animated mask content still animates through the
// approximation, and that the approximation is off unless a caller asks for
// it.
//
// `animated_svg_painter.dart` 里有损的 mask-转-clip 快路径（见
// `AnimatedSvgPainter.approximateMasks`）的测试：哪些 mask 定义合格、合格 mask
// 近似后的像素在抗锯齿边界之外与精确管线一致、黑色 mask 内容仍然会打洞、带动画的
// mask 内容经过近似后仍然会动，以及调用方不主动要求时近似处于关闭状态。

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/animated_svg_painter.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';
import 'package:svgx/src/animation/svg_theme.dart';

SvgDocument _parse(String body) => parseAnimatedSvgDocument(
  '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" '
  'viewBox="0 0 100 100">$body</svg>',
);

Future<ByteData> _renderPixels(
  SvgDocument document, {
  Duration time = Duration.zero,
  required bool approximate,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  AnimatedSvgPainter(
    root: document.root,
    intrinsicSize: Size(document.width, document.height),
    clock: ValueNotifier(time),
    theme: const SvgTheme(),
    fit: BoxFit.fill,
    alignment: Alignment.center,
    gradients: document.gradients,
    clipPaths: document.clipPaths,
    masks: document.masks,
    approximateMasks: () => approximate,
  ).paint(canvas, const Size(100, 100));
  final image = await recorder.endRecording().toImage(100, 100);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return bytes!;
}

int _alphaAt(ByteData pixels, int x, int y) =>
    pixels.getUint8((y * 100 + x) * 4 + 3);

/// True when [document]'s single mask definition was judged replaceable by a
/// clip path. Read off the flag the painter caches on the mask's root node,
/// after one paint has forced the judgement to be made.
///
/// [document] 唯一的 mask 定义是否被判定为可用裁剪路径替代。在一次绘制迫使判定
/// 发生之后，从绘制器缓存在 mask 根节点上的标志读取。
Future<bool> _eligibility(SvgDocument document) async {
  await _renderPixels(document, approximate: true);
  return document.masks.values.single.maskClipEligible ?? false;
}

void main() {
  group('eligibility', () {
    test('pure opaque white fills are eligible', () async {
      final document = _parse(
        '<mask id="m">'
        '<rect x="0" y="0" width="50" height="100" fill="#fff"/>'
        '</mask>'
        '<rect width="100" height="100" fill="#f00" mask="url(#m)"/>',
      );
      expect(await _eligibility(document), isTrue);
    });

    test('a fill inherited from a wrapping group is resolved', () async {
      // How real icon sets paint a whole mask subtree white — if inheritance
      // were not threaded through, this would be misread as "no fill" and the
      // mask would silently clip everything away.
      //
      // 真实图标集正是这样把整个 mask 子树刷白的——如果不把继承传下去，这里会被
      // 误读成"没有 fill"，于是 mask 会静默地把一切都裁掉。
      final document = _parse(
        '<mask id="m"><g fill="#fff">'
        '<rect x="0" y="0" width="50" height="100"/>'
        '</g></mask>'
        '<rect width="100" height="100" fill="#f00" mask="url(#m)"/>',
      );
      expect(await _eligibility(document), isTrue);
      final pixels = await _renderPixels(document, approximate: true);
      expect(
        _alphaAt(pixels, 25, 50),
        greaterThan(200),
        reason: 'the inherited-white half must still be visible',
      );
      expect(_alphaAt(pixels, 75, 50), 0);
    });

    test('stroke paint is rejected — no stroke-to-path in dart:ui', () async {
      final document = _parse(
        '<mask id="m">'
        '<path d="M0 50H100" stroke="#fff" stroke-width="20" fill="none"/>'
        '</mask>'
        '<rect width="100" height="100" fill="#f00" mask="url(#m)"/>',
      );
      expect(await _eligibility(document), isFalse);
    });

    test('a partial opacity is rejected', () async {
      final document = _parse(
        '<mask id="m">'
        '<rect width="50" height="100" fill="#fff" fill-opacity=".3"/>'
        '</mask>'
        '<rect width="100" height="100" fill="#f00" mask="url(#m)"/>',
      );
      expect(await _eligibility(document), isFalse);
    });

    test('an animated opacity is rejected', () async {
      final document = _parse(
        '<mask id="m">'
        '<rect width="50" height="100" fill="#fff">'
        '<animate attributeName="opacity" values="0;1" dur="1s"/>'
        '</rect></mask>'
        '<rect width="100" height="100" fill="#f00" mask="url(#m)"/>',
      );
      expect(await _eligibility(document), isFalse);
    });

    test('a mid-grey fill is rejected — genuinely partial coverage', () async {
      final document = _parse(
        '<mask id="m">'
        '<rect width="50" height="100" fill="#808080"/>'
        '</mask>'
        '<rect width="100" height="100" fill="#f00" mask="url(#m)"/>',
      );
      expect(await _eligibility(document), isFalse);
    });

    test('a gradient fill is rejected', () async {
      final document = _parse(
        '<linearGradient id="g">'
        '<stop offset="0" stop-color="#000"/>'
        '<stop offset="1" stop-color="#fff"/>'
        '</linearGradient>'
        '<mask id="m">'
        '<rect width="100" height="100" fill="url(#g)"/>'
        '</mask>'
        '<rect width="100" height="100" fill="#f00" mask="url(#m)"/>',
      );
      expect(await _eligibility(document), isFalse);
    });

    test(
      'a masked node that is also blurred keeps the exact pipeline',
      () async {
        // Correctness, not eligibility: the mask itself is eligible, but the
        // clip would reorder the pipeline into Blur(Mask()) — see the guard in
        // _paintNode. Proven by the pixels matching the exact render, which a
        // reordered pipeline would not.
        //
        // 这是正确性问题而非合格性问题：mask 本身是合格的，但裁剪会把管线重排成
        // Blur(Mask())——见 _paintNode 里的护栏。用像素与精确渲染一致来证明，
        // 管线被重排的话就不会一致。
        final document = _parse(
          '<mask id="m">'
          '<rect x="0" y="0" width="50" height="100" fill="#fff"/>'
          '</mask>'
          '<rect width="100" height="100" fill="#f00" mask="url(#m)" '
          'filter="blur(4px)"/>',
        );
        final exact = await _renderPixels(document, approximate: false);
        final approximated = await _renderPixels(document, approximate: true);
        for (final x in [40, 48, 52, 60, 70]) {
          expect(
            _alphaAt(approximated, x, 50),
            _alphaAt(exact, x, 50),
            reason:
                'alpha at ($x, 50) — across the mask boundary where a '
                'reordered Blur(Mask()) pipeline would differ',
          );
        }
      },
    );

    test('text content is rejected', () async {
      final document = _parse(
        '<mask id="m"><text x="0" y="50" fill="#fff">hi</text></mask>'
        '<rect width="100" height="100" fill="#f00" mask="url(#m)"/>',
      );
      expect(await _eligibility(document), isFalse);
    });
  });

  group('pixel behaviour', () {
    test(
      'an eligible mask approximated as a clip matches the exact pipeline '
      'away from the antialiased boundary',
      () async {
        final document = _parse(
          '<mask id="m">'
          '<circle cx="50" cy="50" r="30" fill="#fff"/>'
          '</mask>'
          '<rect width="100" height="100" fill="#f00" mask="url(#m)"/>',
        );
        final exact = await _renderPixels(document, approximate: false);
        final approximated = await _renderPixels(document, approximate: true);

        // Sampled well inside and well outside the circle: the documented
        // loss is edge antialiasing only, so everything except a thin band
        // along the boundary must agree.
        //
        // 取样点都远离圆的边界（内部与外部各若干）：已记录的损失仅限边缘抗锯齿，
        // 因此除了边界附近的一条窄带，其余都必须一致。
        const inside = [Offset(50, 50), Offset(35, 50), Offset(50, 65)];
        const outside = [Offset(5, 5), Offset(95, 95), Offset(50, 5)];
        for (final p in [...inside, ...outside]) {
          final x = p.dx.toInt(), y = p.dy.toInt();
          expect(
            _alphaAt(approximated, x, y),
            _alphaAt(exact, x, y),
            reason: 'alpha at ($x, $y) must match the exact mask pipeline',
          );
        }
        expect(
          _alphaAt(exact, 50, 50),
          greaterThan(200),
          reason: 'sanity: the masked-in centre must actually be painted',
        );
      },
    );

    test('black mask content still punches a hole', () async {
      final document = _parse(
        '<mask id="m">'
        '<rect width="100" height="100" fill="#fff"/>'
        '<circle cx="50" cy="50" r="20" fill="#000"/>'
        '</mask>'
        '<rect width="100" height="100" fill="#f00" mask="url(#m)"/>',
      );
      final approximated = await _renderPixels(document, approximate: true);
      final exact = await _renderPixels(document, approximate: false);

      expect(
        _alphaAt(approximated, 50, 50),
        0,
        reason: 'the black circle must remove coverage, not add it',
      );
      expect(_alphaAt(exact, 50, 50), 0, reason: 'sanity: exact agrees');
      expect(
        _alphaAt(approximated, 5, 5),
        _alphaAt(exact, 5, 5),
        reason: 'the white surround must be unaffected',
      );
    });

    test('a fill="none" shape in the mask punches no hole', () async {
      // Regression: `fill="none"` and `fill="#000"` were originally folded
      // together as "no coverage", which made an unpainted shape *subtract*
      // from the revealed region. `none` paints nothing and must therefore
      // change nothing; only actually-painted black removes coverage.
      //
      // 回归：`fill="none"` 与 `fill="#000"` 原先被合并成"无覆盖"，导致一个未被
      // 绘制的形状去*减掉*已显示区域。`none` 什么都不画，因此必须什么都不改变；
      // 只有真正画出来的黑色才去掉覆盖度。
      final document = _parse(
        '<mask id="m">'
        '<rect width="100" height="100" fill="#fff"/>'
        '<circle cx="50" cy="50" r="20" fill="none"/>'
        '</mask>'
        '<rect width="100" height="100" fill="#f00" mask="url(#m)"/>',
      );
      final approximated = await _renderPixels(document, approximate: true);
      final exact = await _renderPixels(document, approximate: false);

      expect(
        _alphaAt(approximated, 50, 50),
        greaterThan(200),
        reason: 'the fill="none" circle must not remove coverage',
      );
      expect(
        _alphaAt(approximated, 50, 50),
        _alphaAt(exact, 50, 50),
        reason: 'and it must agree with the exact pipeline',
      );
    });

    test('a mask shape with no fill at all hides, per SVG initial value',
        () async {
      // The other half of the same distinction: SVG's initial `fill` is black,
      // so a shape that inherits nothing genuinely does hide. Asserted through
      // the exact pipeline as the reference, then matched by the
      // approximation.
      //
      // 同一区分的另一半：SVG 的 `fill` 初始值是黑色，因此什么都没继承到的形状
      // 确实会隐藏。先以精确管线为参照断言，再要求近似与之一致。
      final document = _parse(
        '<mask id="m">'
        '<rect width="100" height="100" fill="#fff"/>'
        '<circle cx="50" cy="50" r="20"/>'
        '</mask>'
        '<rect width="100" height="100" fill="#f00" mask="url(#m)"/>',
      );
      expect(
        document.masks.values.single.children.last.attributes['fill'],
        isNull,
        reason: 'sanity: the circle really declares no fill',
      );
      final approximated = await _renderPixels(document, approximate: true);
      final exact = await _renderPixels(document, approximate: false);
      expect(
        _alphaAt(exact, 50, 50),
        0,
        reason: 'reference: the exact pipeline paints it black, so it hides',
      );
      expect(
        _alphaAt(approximated, 50, 50),
        0,
        reason: 'the approximation must subtract it, matching the reference',
      );
      expect(
        _alphaAt(approximated, 5, 5),
        _alphaAt(exact, 5, 5),
        reason: 'and leave the white surround alone',
      );
    });

    test('animated mask content still animates through the clip', () async {
      // The clip path is rebuilt from a fresh sample every frame, so a moving
      // mask must move. Freezing it at frame zero was the specific failure
      // mode worth guarding: the eligibility answer is cached on the node,
      // and caching the *path* alongside it would have caused exactly that.
      //
      // 裁剪路径每帧都用新采样重建，因此会动的 mask 必须真的动。冻结在第 0 帧是
      // 值得专门守住的失效模式：合格性判定结果是缓存在节点上的，如果把*路径*也
      // 一起缓存，就会正好造成这个后果。
      final document = _parse(
        '<mask id="m">'
        '<rect y="0" width="100" height="100" fill="#fff">'
        '<animateTransform attributeName="transform" type="translate" '
        'values="0,-100;0,0" dur="1s" fill="freeze"/>'
        '</rect></mask>'
        '<rect width="100" height="100" fill="#f00" mask="url(#m)"/>',
      );
      final atStart = await _renderPixels(
        document,
        approximate: true,
        time: Duration.zero,
      );
      final atEnd = await _renderPixels(
        document,
        approximate: true,
        time: const Duration(seconds: 1),
      );

      expect(
        _alphaAt(atStart, 50, 50),
        0,
        reason: 'at t=0 the mask rect is translated fully off the top',
      );
      expect(
        _alphaAt(atEnd, 50, 50),
        greaterThan(200),
        reason: 'at t=1s it has slid into place and reveals the content',
      );
    });

    test(
      'the clip path is reused once the mask animation has frozen, and '
      'rebuilt while it is still moving',
      () async {
        final document = _parse(
          '<mask id="m">'
          '<rect width="100" height="100" fill="#fff">'
          '<animateTransform attributeName="transform" type="translate" '
          'values="0,-100;0,0" dur="1s" fill="freeze"/>'
          '</rect></mask>'
          '<rect width="100" height="100" fill="#f00" mask="url(#m)"/>',
        );
        final def = document.masks.values.single;

        // Two instants inside the active interval sample to different offsets,
        // so the path must be a different object each time.
        //
        // 活跃区间内的两个时刻会采样出不同偏移，因此路径每次都必须是不同的对象。
        await _renderPixels(
          document,
          approximate: true,
          time: const Duration(milliseconds: 300),
        );
        final whileMoving = def.cachedMaskClip;
        await _renderPixels(
          document,
          approximate: true,
          time: const Duration(milliseconds: 600),
        );
        expect(
          def.cachedMaskClip,
          isNot(same(whileMoving)),
          reason:
              'a moving mask must rebuild — a stale clip here would freeze '
              'the animation, which is the failure mode this cache risks',
        );

        // Past the end with fill="freeze" both instants sample identically, so
        // the very same path object must come back — this is the cache
        // actually paying off.
        //
        // 越过结束点后（fill="freeze"）两个时刻采样完全相同，因此必须拿回同一个
        // 路径对象——这才是缓存真正生效。
        await _renderPixels(
          document,
          approximate: true,
          time: const Duration(seconds: 3),
        );
        final frozen = def.cachedMaskClip;
        await _renderPixels(
          document,
          approximate: true,
          time: const Duration(seconds: 9),
        );
        expect(
          def.cachedMaskClip,
          same(frozen),
          reason: 'a frozen mask must reuse its clip path across frames',
        );
      },
    );

    test('the approximation is off by default', () async {
      final document = _parse(
        '<mask id="m">'
        '<rect width="50" height="100" fill="#fff"/>'
        '</mask>'
        '<rect width="100" height="100" fill="#f00" mask="url(#m)"/>',
      );
      // Constructed without `approximateMasks`, i.e. how every pre-existing
      // caller constructs it — the eligibility flag must never even be
      // computed, proving the exact pipeline was taken.
      //
      // 不传 `approximateMasks` 构造，也就是所有既有调用方的构造方式——合格性标志
      // 必须连计算都不发生，以此证明走的是精确管线。
      final recorder = ui.PictureRecorder();
      AnimatedSvgPainter(
        root: document.root,
        intrinsicSize: Size(document.width, document.height),
        clock: ValueNotifier(Duration.zero),
        theme: const SvgTheme(),
        fit: BoxFit.fill,
        alignment: Alignment.center,
        masks: document.masks,
      ).paint(Canvas(recorder), const Size(100, 100));
      recorder.endRecording();

      expect(document.masks.values.single.maskClipEligible, isNull);
    });
  });
}
