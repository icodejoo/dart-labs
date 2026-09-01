// Tests for the opt-out-able, deliberately lossy high-concurrency
// degradation added in `SvgxAnimationQuality`: the pure divisor policy, the
// parser flag that marks a document as needing `saveLayer` (which is what
// makes it eligible for harder throttling), and the observable behaviour of
// the staggered per-icon frame skipping in `_SharedAnimationClock` — that
// under load only a fraction of icons advance their timeline on any one
// frame, that the fraction is spread rather than all-or-nothing, that every
// icon still progresses over time (nothing freezes), and that
// `SvgxAnimationQuality.exact` genuinely disables all of it.
//
// `SvgxAnimationQuality` 新增的"可关闭、故意有损"的高并发降级的测试：纯除数
// 策略、把文档标记为需要 `saveLayer` 的解析器标志（这决定它是否适用更狠的
// 节流）、以及 `_SharedAnimationClock` 里错相位逐图标跳帧的可观测行为——负载下
// 任一帧只有一部分图标推进时间线、这部分是铺开的而非全有全无、每个图标随时间
// 仍然都在前进（不会冻结），以及 `SvgxAnimationQuality.exact` 确实把这一切关掉。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/animated_svg_painter.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';
import 'package:svgx/svgx.dart';

// An indefinite spin — keeps ticking for the whole test instead of settling,
// so a stalled clock can only mean frame skipping and never "the animation
// finished".
//
// 无限旋转——整个测试期间持续 tick 而不会定格，因此时钟停住只可能是跳帧造成
// 的，绝不会是"动画播完了"。
const _spinner =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
    'viewBox="0 0 24 24">'
    '<circle cx="12" cy="12" r="9" fill="none" stroke="#000" '
    'stroke-width="2" stroke-dasharray="40 20">'
    '<animateTransform attributeName="transform" type="rotate" '
    'values="0 12 12;360 12 12" dur="1s" repeatCount="indefinite"/>'
    '</circle></svg>';

/// The timeline position [SvgxAnimated] instance [index] is currently
/// painting, read off the painter the same way
/// `shared_animation_clock_test.dart` does.
///
/// 第 [index] 个 [SvgxAnimated] 实例当前正在绘制的时间线位置，读取方式与
/// `shared_animation_clock_test.dart` 一致。
Duration _clockAt(int index, WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find
        .descendant(
          of: find.byType(SvgxAnimated).at(index),
          matching: find.byType(CustomPaint),
        )
        .first,
  );
  return (paint.painter! as AnimatedSvgPainter).clock.value;
}

Widget _grid(int count, {SvgxAnimationQuality? quality}) => MaterialApp(
  home: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < count; i++)
        SvgxAnimated.string(_spinner, width: 4, height: 4, quality: quality),
    ],
  ),
);

void main() {
  setUp(SvgxDocumentCache.instance.clear);
  tearDown(() {
    SvgxDocumentCache.instance.clear();
    SvgxAnimationQuality.defaultQuality = SvgxAnimationQuality.balanced;
  });

  group('frameDivisorFor policy', () {
    test('nothing is degraded at or below the threshold', () {
      const quality = SvgxAnimationQuality(frameSkipThreshold: 24);
      for (final concurrency in [1, 10, 24]) {
        expect(
          quality.frameDivisorFor(
            concurrency: concurrency,
            usesOffscreenLayers: false,
          ),
          1,
          reason: 'concurrency $concurrency is within the threshold',
        );
        expect(
          quality.frameDivisorFor(
            concurrency: concurrency,
            usesOffscreenLayers: true,
          ),
          1,
          reason: 'an offscreen-layer document is not degraded early either',
        );
      }
    });

    test('above the threshold, offscreen-layer documents throttle harder', () {
      const quality = SvgxAnimationQuality(
        frameSkipThreshold: 24,
        maxFrameDivisor: 2,
        offscreenLayerFrameDivisor: 3,
      );
      expect(
        quality.frameDivisorFor(concurrency: 25, usesOffscreenLayers: false),
        2,
      );
      expect(
        quality.frameDivisorFor(concurrency: 25, usesOffscreenLayers: true),
        3,
      );
    });

    test(
      'a smaller offscreen divisor never undercuts the ordinary one',
      () {
        // Guards the `max` in frameDivisorFor: a caller configuring an
        // offscreen divisor *below* maxFrameDivisor must not accidentally
        // make the expensive documents refresh MORE often than cheap ones.
        //
        // 守住 frameDivisorFor 里的取大：调用方把离屏除数配得*低于*
        // maxFrameDivisor 时，不能反而让昂贵的文档比廉价的刷得更勤。
        const quality = SvgxAnimationQuality(
          frameSkipThreshold: 0,
          maxFrameDivisor: 4,
          offscreenLayerFrameDivisor: 2,
        );
        expect(
          quality.frameDivisorFor(concurrency: 1, usesOffscreenLayers: true),
          4,
        );
      },
    );

    test('exact never degrades, at any concurrency', () {
      expect(
        SvgxAnimationQuality.exact.frameDivisorFor(
          concurrency: 100000,
          usesOffscreenLayers: true,
        ),
        1,
      );
    });
  });

  group('usesOffscreenLayers parsing', () {
    SvgDocument parse(String body) => parseAnimatedSvgDocument(
      '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" '
      'viewBox="0 0 100 100">$body</svg>',
    );

    test('a plain document needs no offscreen layer', () {
      expect(
        parse('<rect width="10" height="10" fill="#000"/>').usesOffscreenLayers,
        isFalse,
      );
    });

    test('a mask reference marks the document', () {
      expect(
        parse(
          '<mask id="m"><rect width="50" height="50" fill="#fff"/></mask>'
          '<rect width="100" height="100" fill="#000" mask="url(#m)"/>',
        ).usesOffscreenLayers,
        isTrue,
      );
    });

    test('a blur filter marks the document', () {
      expect(
        parse(
          '<rect width="10" height="10" fill="#000" filter="blur(2px)"/>',
        ).usesOffscreenLayers,
        isTrue,
      );
    });

    test('a clip-path alone does not — clipping needs no layer', () {
      expect(
        parse(
          '<clipPath id="c"><rect width="50" height="50"/></clipPath>'
          '<rect width="100" height="100" fill="#000" clip-path="url(#c)"/>',
        ).usesOffscreenLayers,
        isFalse,
      );
    });
  });

  group('staggered frame skipping', () {
    testWidgets(
      'under load only some icons advance on a given frame, and the skipped '
      'ones are a spread rather than all-or-nothing',
      (tester) async {
        SvgxAnimationQuality.defaultQuality = const SvgxAnimationQuality(
          frameSkipThreshold: 4,
          maxFrameDivisor: 2,
        );
        const count = 10;
        await tester.pumpWidget(_grid(count));
        await tester.pump(const Duration(milliseconds: 16));

        var advanced = 0;
        for (var i = 0; i < count; i++) {
          if (_clockAt(i, tester) > Duration.zero) advanced++;
        }
        expect(
          advanced,
          greaterThan(0),
          reason: 'frame skipping must not stall every icon',
        );
        expect(
          advanced,
          lessThan(count),
          reason: 'above the threshold, some icons must be skipped',
        );
        // Phases are handed out consecutively, so with divisor 2 the split is
        // even — half this frame, the other half next frame. Allowing +/-1
        // absorbs the parity of the shared phase counter, which is
        // process-wide and deliberately never reset.
        //
        // 相位是连号发放的，因此除数为 2 时切分是均匀的——这一帧一半、下一帧
        // 另一半。允许 +/-1 是为了吸收共享相位计数器的奇偶性，它是全进程的、
        // 且故意从不重置。
        expect((advanced - count ~/ 2).abs(), lessThanOrEqualTo(1));
      },
    );

    testWidgets('every icon still progresses over successive frames', (
      tester,
    ) async {
      SvgxAnimationQuality.defaultQuality = const SvgxAnimationQuality(
        frameSkipThreshold: 4,
        maxFrameDivisor: 2,
        offscreenLayerFrameDivisor: 3,
      );
      const count = 10;
      await tester.pumpWidget(_grid(count));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      for (var i = 0; i < count; i++) {
        expect(
          _clockAt(i, tester),
          greaterThan(Duration.zero),
          reason:
              'icon $i must have sampled its timeline at least once — frame '
              'skipping lowers the sample rate, it must never freeze an icon',
        );
      }
    });

    testWidgets('exact quality advances every icon on every frame', (
      tester,
    ) async {
      SvgxAnimationQuality.defaultQuality = const SvgxAnimationQuality(
        frameSkipThreshold: 4,
        maxFrameDivisor: 2,
      );
      const count = 10;
      // Per-widget override, with the global default set to degrade — proves
      // the opt-out works at the widget level and not only globally.
      //
      // 逐控件覆盖，同时全局默认是降级的——证明这个 opt-out 在控件级别也生效，
      // 不是只能全局关。
      await tester.pumpWidget(
        _grid(count, quality: SvgxAnimationQuality.exact),
      );
      await tester.pump(const Duration(milliseconds: 16));

      for (var i = 0; i < count; i++) {
        expect(
          _clockAt(i, tester),
          greaterThan(Duration.zero),
          reason: 'icon $i must not be skipped under exact quality',
        );
      }
    });

    testWidgets('below the threshold nothing is skipped', (tester) async {
      SvgxAnimationQuality.defaultQuality = const SvgxAnimationQuality(
        frameSkipThreshold: 4,
        maxFrameDivisor: 2,
      );
      const count = 3;
      await tester.pumpWidget(_grid(count));
      await tester.pump(const Duration(milliseconds: 16));

      for (var i = 0; i < count; i++) {
        expect(
          _clockAt(i, tester),
          greaterThan(Duration.zero),
          reason: 'icon $i is within the threshold and must not be degraded',
        );
      }
    });
  });
}
