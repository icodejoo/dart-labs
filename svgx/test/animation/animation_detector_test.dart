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
      expect(
        AnimationDetector.hasAnimations(
          '<svg><animate attributeName="x"/></svg>',
        ),
        isTrue,
      );
    });

    test(
      'detects <animateTransform>, not confused by the shared "animate" prefix',
      () {
        expect(
          AnimationDetector.hasAnimations(
            '<svg><animateTransform attributeName="transform"/></svg>',
          ),
          isTrue,
        );
      },
    );

    test('detects <animateMotion> even with no <animate>/<animateTransform>/<set> present', () {
      expect(
        AnimationDetector.hasAnimations(
          '<svg><animateMotion path="M0,0 L10,10"/></svg>',
        ),
        isTrue,
        reason: '<animateMotion>-only SVGs must not be misrouted to the static path',
      );
    });

    test('detects <set>', () {
      expect(
        AnimationDetector.hasAnimations(
          '<svg><set attributeName="fill"/></svg>',
        ),
        isTrue,
      );
    });

    test('returns false for a plain static SVG', () {
      expect(
        AnimationDetector.hasAnimations('<svg><path d="M0,0 L1,1"/></svg>'),
        isFalse,
      );
    });

    // The four per-tag patterns were merged into one alternation for speed
    // (see animation_detector.dart). These pin the property that made the
    // merge safe: every alternative still requires `[\s>]` right after the
    // tag name, so a longer tag name that merely starts with a supported one
    // is not a match.
    //
    // 出于性能考虑，四条分标签正则被合并成了一条多分支正则（见
    // animation_detector.dart）。以下两例钉住让合并成立的性质：每个分支都仍要求
    // 标签名后紧跟 `[\s>]`，因此仅仅以受支持标签名开头的更长标签不算命中。
    test('does not match a longer tag that merely starts with "animate"', () {
      expect(
        AnimationDetector.hasAnimations('<svg><animateWidget x="1"/></svg>'),
        isFalse,
      );
    });

    test('does not match a longer tag that merely starts with "set"', () {
      expect(
        AnimationDetector.hasAnimations('<svg><setter value="1"/></svg>'),
        isFalse,
      );
    });
  });
}
