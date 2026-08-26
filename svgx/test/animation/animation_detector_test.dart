// Regression test for the 2026-08-25 `<animateMotion>` detection gap: the
// detector had a per-tag pattern for `<animate>` and `<animateTransform>` but
// was missing one for `<animateMotion>`, so animateMotion-only SVGs were
// silently routed to the static usvg path (which drops SMIL) instead of the
// animated engine.
//
// 2026-08-25 `<animateMotion>` 检测缺口的回归测试：检测器本来给
// `<animate>`/`<animateTransform>` 各有一条独立正则，唯独漏了
// `<animateMotion>`，导致只用 animateMotion 的 SVG 被静默路由去静态 usvg
// 路径（会丢弃 SMIL），而非走动画引擎。

import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/animation_detector.dart';

void main() {
  group('AnimationDetector.hasAnimations', () {
    test('detects a bare <animate> tag', () {
      expect(AnimationDetector.hasAnimations('<svg><animate attributeName="x"/></svg>'), isTrue);
    });

    test('detects <animateTransform>, not confused by the shared "animate" prefix', () {
      expect(
        AnimationDetector.hasAnimations('<svg><animateTransform attributeName="transform"/></svg>'),
        isTrue,
      );
    });

    test('detects <animateMotion> even with no <animate>/<animateTransform>/<set> present', () {
      expect(
        AnimationDetector.hasAnimations('<svg><animateMotion path="M0,0 L10,10"/></svg>'),
        isTrue,
        reason: '<animateMotion>-only SVGs must not be misrouted to the static path',
      );
    });

    test('detects <set>', () {
      expect(AnimationDetector.hasAnimations('<svg><set attributeName="fill"/></svg>'), isTrue);
    });

    test('returns false for a plain static SVG', () {
      expect(AnimationDetector.hasAnimations('<svg><path d="M0,0 L1,1"/></svg>'), isFalse);
    });
  });
}
