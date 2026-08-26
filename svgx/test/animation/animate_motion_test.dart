// `<animateMotion>`: inline `path`, `<mpath href="#id">`, arc-length paced
// sampling, `rotate="auto"`/`auto-reverse`/fixed angle, freeze/repeat, and
// graceful skipping of unusable paths.
//
// The arc-length table is built with dart:ui's Path.computeMetrics(), which
// works under plain `flutter test` — no FFI involved.
//
// `<animateMotion>`：内联 `path`、`<mpath href="#id">`、按弧长匀速采样、
// `rotate="auto"`/`auto-reverse`/固定角度、freeze/repeat，以及不可用路径的
// 静默跳过。
//
// 弧长表由 dart:ui 的 Path.computeMetrics() 构建，在纯 `flutter test` 下即可
// 运行——不涉及 FFI。

import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';

SvgDocument _parse(String body) => parseAnimatedSvgDocument(
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">$body</svg>',
    );

void main() {
  group('<animateMotion>', () {
    test('an inline path is sampled by arc length across the duration', () {
      final document = _parse(
        '<circle cx="0" cy="0" r="1">'
        '<animateMotion path="M0 0 L100 0" dur="1s" fill="freeze"/>'
        '</circle>',
      );
      final motion = document.root.children.single.motionAnimations.single;

      expect(motion.sample(Duration.zero)!.x, closeTo(0, 0.5));
      expect(motion.sample(const Duration(milliseconds: 500))!.x, closeTo(50, 0.5));
      expect(motion.sample(const Duration(seconds: 2))!.x, closeTo(100, 0.5));
      expect(motion.sample(const Duration(milliseconds: 500))!.y, closeTo(0, 0.5));
    });

    test('motion is paced by length, not by segment count', () {
      // Two segments of very different lengths: at half the duration the
      // element must be halfway along the *total arc length* (x = 50 on the
      // long first leg), not at the joint between the two segments.
      //
      // 两段长度悬殊：在时长一半处，元素应位于*总弧长*的一半（在很长的第一段上
      // x = 50），而不是两段的连接处。
      final document = _parse(
        '<circle cx="0" cy="0" r="1">'
        '<animateMotion path="M0 0 L90 0 L90 10" dur="1s" fill="freeze"/>'
        '</circle>',
      );
      final motion = document.root.children.single.motionAnimations.single;
      final mid = motion.sample(const Duration(milliseconds: 500))!;

      expect(mid.x, closeTo(50, 1));
      expect(mid.y, closeTo(0, 1));
    });

    test('<mpath href="#id"> uses the referenced path\'s d', () {
      final document = _parse(
        '<defs><path id="track" d="M0 0 L0 50"/></defs>'
        '<circle cx="0" cy="0" r="1">'
        '<animateMotion dur="1s" fill="freeze"><mpath href="#track"/></animateMotion>'
        '</circle>',
      );
      final motion = document.root.children.single.motionAnimations.single;

      expect(motion.sample(const Duration(seconds: 2))!.y, closeTo(50, 0.5));
    });

    test('an mpath pointing at nothing yields no motion animation', () {
      final document = _parse(
        '<circle cx="0" cy="0" r="1">'
        '<animateMotion dur="1s"><mpath href="#ghost"/></animateMotion>'
        '</circle>',
      );

      expect(document.root.children.single.motionAnimations, isEmpty);
    });

    test('a zero-length or missing path yields no motion animation', () {
      final document = _parse(
        '<circle cx="0" cy="0" r="1">'
        '<animateMotion dur="1s"/>'
        '<animateMotion path="M5 5" dur="1s"/>'
        '</circle>',
      );

      expect(document.root.children.single.motionAnimations, isEmpty);
    });

    test('rotate="auto" faces along the tangent', () {
      final document = _parse(
        '<circle cx="0" cy="0" r="1">'
        '<animateMotion path="M0 0 L0 100" rotate="auto" dur="1s" fill="freeze"/>'
        '</circle>',
      );
      final motion = document.root.children.single.motionAnimations.single;

      // Straight down: the tangent points at +90 degrees.
      expect(motion.sample(const Duration(milliseconds: 500))!.angleDegrees, closeTo(90, 1));
    });

    test('rotate="auto-reverse" faces the other way', () {
      final document = _parse(
        '<circle cx="0" cy="0" r="1">'
        '<animateMotion path="M0 0 L0 100" rotate="auto-reverse" dur="1s" fill="freeze"/>'
        '</circle>',
      );
      final motion = document.root.children.single.motionAnimations.single;

      expect(motion.sample(const Duration(milliseconds: 500))!.angleDegrees, closeTo(270, 1));
    });

    test('a numeric rotate is a constant angle; the default is none', () {
      final withAngle = _parse(
        '<circle cx="0" cy="0" r="1">'
        '<animateMotion path="M0 0 L100 0" rotate="45" dur="1s" fill="freeze"/>'
        '</circle>',
      ).root.children.single.motionAnimations.single;
      final withoutAngle = _parse(
        '<circle cx="0" cy="0" r="1">'
        '<animateMotion path="M0 0 L0 100" dur="1s" fill="freeze"/>'
        '</circle>',
      ).root.children.single.motionAnimations.single;

      expect(withAngle.sample(const Duration(milliseconds: 500))!.angleDegrees, 45);
      expect(withoutAngle.sample(const Duration(milliseconds: 500))!.angleDegrees, 0);
    });

    test('without fill="freeze" the motion stops applying once it ends', () {
      final document = _parse(
        '<circle cx="0" cy="0" r="1">'
        '<animateMotion path="M0 0 L100 0" dur="1s"/>'
        '</circle>',
      );
      final motion = document.root.children.single.motionAnimations.single;

      expect(motion.sample(const Duration(seconds: 2)), isNull);
    });

    test('keyPoints reroutes progress to a non-default arc-length fraction', () {
      // Without keyPoints, t=0.5 sits at the arc-length midpoint (x=50). With
      // keyPoints="0;0.9;1" and keyTimes="0;0.5;1", at t=0.5 the element must
      // sit at 90% of the arc length instead (x=90).
      //
      // 没有 keyPoints 时，t=0.5 处于弧长中点（x=50）。带
      // keyPoints="0;0.9;1"、keyTimes="0;0.5;1" 时，t=0.5 处元素应改为处于弧长
      // 的 90%（x=90）。
      final document = _parse(
        '<circle cx="0" cy="0" r="1">'
        '<animateMotion path="M0 0 L100 0" keyPoints="0;0.9;1" keyTimes="0;0.5;1" dur="1s" fill="freeze"/>'
        '</circle>',
      );
      final motion = document.root.children.single.motionAnimations.single;

      expect(motion.sample(const Duration(milliseconds: 500))!.x, closeTo(90, 1));
    });

    test('without keyPoints, behaviour is exactly unchanged (backward compatible)', () {
      final document = _parse(
        '<circle cx="0" cy="0" r="1">'
        '<animateMotion path="M0 0 L100 0" dur="1s" fill="freeze"/>'
        '</circle>',
      );
      final motion = document.root.children.single.motionAnimations.single;

      expect(motion.keyPoints, isNull);
      expect(motion.sample(const Duration(milliseconds: 500))!.x, closeTo(50, 0.5));
    });

    test('calcMode="discrete" on keyPoints holds each keyPoint, no interpolation', () {
      final document = _parse(
        '<circle cx="0" cy="0" r="1">'
        '<animateMotion path="M0 0 L100 0" keyPoints="0;1" keyTimes="0;1" calcMode="discrete" '
        'dur="1s" fill="freeze"/>'
        '</circle>',
      );
      final motion = document.root.children.single.motionAnimations.single;

      expect(motion.sample(const Duration(milliseconds: 400))!.x, closeTo(0, 0.5));
    });

    test('malformed keyPoints (fewer than two entries) is dropped like other malformed timing', () {
      final document = _parse(
        '<circle cx="0" cy="0" r="1">'
        '<animateMotion path="M0 0 L100 0" keyPoints="1" dur="1s" fill="freeze"/>'
        '</circle>',
      );
      final motion = document.root.children.single.motionAnimations.single;

      expect(motion.keyPoints, isNull);
    });

    test('motion timing joins the document duration and syncbase resolution', () {
      final document = _parse(
        '<circle cx="0" cy="0" r="1">'
        '<animate id="a" attributeName="r" from="0" to="1" dur="1s"/>'
        '<animateMotion path="M0 0 L10 0" dur="2s" begin="a.end"/>'
        '</circle>',
      );
      final motion = document.root.children.single.motionAnimations.single;

      expect(motion.begin, const Duration(seconds: 1));
      expect(document.totalDuration, const Duration(seconds: 3));
    });
  });
}
