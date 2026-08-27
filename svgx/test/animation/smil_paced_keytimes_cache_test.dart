// Regression test for the `calcMode="paced"` key-times cache added to
// SmilAnimation/SmilTransformAnimation/SmilColorAnimation/SmilMotionAnimation:
// `sample()` used to recompute `_pacedKeyTimes` (an O(n) pass over `values`)
// on every call; it's now cached on first call. These tests call `sample()`
// many times across the timeline (simulating repeated frames) to verify the
// cached path still produces correct, paced-by-distance interpolation — not
// just that it doesn't crash.
//
// `calcMode="paced"` 关键帧时间缓存的回归测试，覆盖
// SmilAnimation/SmilTransformAnimation/SmilColorAnimation/SmilMotionAnimation：
// `sample()` 此前每次调用都会重算一遍 `_pacedKeyTimes`（对 `values` 的 O(n)
// 遍历）；现在改为首次调用后缓存。这些测试在时间线上多次调用 `sample()`
// （模拟重复的帧），验证走缓存路径依然产出正确的、按距离匀速的插值结果——
// 不只是不崩溃。

import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';
import 'package:svgx/src/animation/svg_gradient.dart';

SvgDocument _parse(String body) => parseAnimatedSvgDocument(
  '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">$body</svg>',
);

void main() {
  group('calcMode="paced" key-times cache', () {
    test('SmilAnimation: repeated sample() calls stay paced by distance', () {
      // Keyframes 0, 1, 100: paced mode spaces time by |value delta|, so the
      // second segment (1->100, length 99) should take ~99% of the duration,
      // not 50% (which plain evenly-spaced keyframes would give).
      //
      // 关键帧 0、1、100：paced 模式按 |数值差| 分配时间，第二段（1->100，
      // 长度 99）应占时长的约 99%，而非均匀关键帧会给出的 50%。
      final document = _parse(
        '<rect>'
        '<animate attributeName="stroke-dashoffset" values="0;1;100" '
        'calcMode="paced" dur="1s" fill="freeze"/>'
        '</rect>',
      );
      final animation = document.root.children.single.animations.single;

      // Call sample() repeatedly across many "frames" — first call populates
      // the cache, subsequent calls must read it back correctly.
      //
      // 反复调用 sample() 模拟多帧——首次调用填充缓存，后续调用必须能正确
      // 读回。
      for (var i = 0; i < 5; i++) {
        expect(animation.sample(Duration.zero), closeTo(0, 0.01));
        // At the segment boundary time (~1% in), value should be just past 1,
        // not near the segment's midpoint value.
        //
        // 在分段边界时间点（约 1% 处），数值应刚过 1，而非接近该段中点值。
        expect(
          animation.sample(const Duration(milliseconds: 10)),
          closeTo(1, 0.5),
        );
        expect(
          animation.sample(const Duration(milliseconds: 500)),
          closeTo(50, 2),
        );
        expect(animation.sample(const Duration(seconds: 1)), closeTo(100, 0.01));
      }
    });

    test(
      'SmilTransformAnimation: repeated sample() calls stay paced by distance',
      () {
        final document = _parse(
          '<rect>'
          '<animateTransform attributeName="transform" type="translate" '
          'values="0,0;1,0;100,0" calcMode="paced" dur="1s" fill="freeze"/>'
          '</rect>',
        );
        final animation =
            document.root.children.single.transformAnimations.single;

        for (var i = 0; i < 5; i++) {
          expect(animation.sample(Duration.zero)![0], closeTo(0, 0.01));
          expect(
            animation.sample(const Duration(milliseconds: 500))![0],
            closeTo(50, 2),
          );
          expect(
            animation.sample(const Duration(seconds: 1))![0],
            closeTo(100, 0.01),
          );
        }
      },
    );

    test(
      'SmilColorAnimation (stop-color): repeated resample stays paced by '
      'distance',
      () {
        // Black -> near-black -> white on a gradient stop: paced by
        // per-channel ARGB distance, so the huge second leg should dominate
        // the timing just like the numeric case above.
        //
        // 渐变色标上的 黑 -> 近黑 -> 白：按逐通道 ARGB 距离分配时间，巨大的
        // 第二段理应像上面数值用例一样主导时长分配。
        final document = _parse(
          '<defs><linearGradient id="g">'
          '<stop offset="0" stop-color="#000000">'
          '<animate attributeName="stop-color" '
          'values="#000000;#010101;#ffffff" '
          'calcMode="paced" dur="1s" fill="freeze"/>'
          '</stop>'
          '<stop offset="1" stop-color="#0000ff"/>'
          '</linearGradient></defs>',
        );
        final def = document.gradients['g']!;

        for (var i = 0; i < 5; i++) {
          final atStart = resampleGradientAtTime(def, Duration.zero);
          expect(atStart.stops.first.color.r, closeTo(0, 0.01));

          final atEnd = resampleGradientAtTime(
            def,
            const Duration(seconds: 1),
          );
          expect(atEnd.stops.first.color.r, closeTo(1, 0.01));

          // Midpoint should be far past the tiny first segment's end
          // (#010101) — roughly mid-grey — since the second (huge) leg
          // dominates pacing.
          //
          // 中点应远远越过第一小段的终点（#010101）——大致处于中灰——因为
          // 占主导的是第二个巨大分段。
          final mid = resampleGradientAtTime(
            def,
            const Duration(milliseconds: 500),
          );
          expect(mid.stops.first.color.r, greaterThan(0.3));
        }
      },
    );

    test(
      'SmilMotionAnimation keyPoints: repeated sample() calls stay paced',
      () {
        // keyPoints are arc-length fractions along `path` (total length 100):
        // segment 0->0.01 is tiny, segment 0.01->1 is huge, so paced mode
        // spends almost the whole duration on the second segment.
        //
        // keyPoints 是沿 `path`（总长 100）的弧长比例：0->0.01 段极短，
        // 0.01->1 段极长，paced 模式几乎把全部时长都花在第二段上。
        final document = _parse(
          '<circle cx="0" cy="0" r="1">'
          '<animateMotion path="M0 0 L100 0" '
          'keyPoints="0;0.01;1" keyTimes="0;0.5;1" '
          'calcMode="paced" dur="1s" fill="freeze"/>'
          '</circle>',
        );
        final motion = document.root.children.single.motionAnimations.single;

        for (var i = 0; i < 5; i++) {
          expect(motion.sample(Duration.zero)!.x, closeTo(0, 0.5));
          expect(
            motion.sample(const Duration(seconds: 1))!.x,
            closeTo(100, 0.5),
          );
          expect(
            motion.sample(const Duration(milliseconds: 500))!.x,
            closeTo(50, 2),
          );
        }
      },
    );
  });
}
