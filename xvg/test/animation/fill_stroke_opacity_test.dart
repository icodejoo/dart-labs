// `fill-opacity` / `stroke-opacity`：继承、与 opacity 相乘、渐变、文字、
// 动画驱动、钳制。像素级断言（采样渲染出的 alpha）。

import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/svg_style.dart';
import 'package:xvg/src/animation/svg_theme.dart';

import 'pixel_test_utils.dart';

/// 半透明在 8 位 alpha 上允许的舍入误差。
const int _tol = 2;

Matcher _near(int expected) =>
    inInclusiveRange(expected - _tol, expected + _tol);

void main() {
  group('ResolvedStyle', () {
    const theme = XvgTheme();

    test('fill-opacity / stroke-opacity 默认 1，且被子节点继承', () {
      expect(ResolvedStyle.initial.fillOpacity, 1);
      expect(ResolvedStyle.initial.strokeOpacity, 1);
      final parent = ResolvedStyle.initial.inherit({
        'fill-opacity': '0.4',
        'stroke-opacity': '0.2',
      }, theme);
      final child = parent.inherit({}, theme);
      expect(child.fillOpacity, 0.4);
      expect(child.strokeOpacity, 0.2);
      expect(child.inherit({'fill-opacity': '1'}, theme).fillOpacity, 1);
    });

    test('取值钳制到 [0, 1]，无法解析时沿用继承值', () {
      expect(
        ResolvedStyle.initial.inherit({'fill-opacity': '2'}, theme).fillOpacity,
        1,
      );
      expect(
        ResolvedStyle.initial.inherit({
          'fill-opacity': '-1',
        }, theme).fillOpacity,
        0,
      );
      final parent = ResolvedStyle.initial.inherit({
        'fill-opacity': '0.3',
      }, theme);
      expect(parent.inherit({'fill-opacity': 'abc'}, theme).fillOpacity, 0.3);
    });

    test('opacity 在 [0, 1] 内原样保留（越界钳制见 opacity_clamp_test）', () {
      final parent = ResolvedStyle.initial.inherit({'opacity': '0.5'}, theme);
      expect(parent.opacity, 0.5);
    });
  });

  group('像素', () {
    test('纯色填充：alpha = 255 x fill-opacity', () async {
      final doc = parsePixelDoc(
        '<rect width="100" height="100" fill="#0000FF" fill-opacity="0.5"/>',
      );
      final px = await renderAt(doc, Duration.zero);
      expect(alphaAt(px, 50, 50), _near(128));
      expect(redAt(px, 50, 50), 0);
    });

    test('继承：分组上的 fill-opacity 作用于子元素，子元素可覆盖', () async {
      final doc = parsePixelDoc(
        '<g fill-opacity="0.5">'
        '<rect width="50" height="100" fill="#000"/>'
        '<rect x="50" width="50" height="100" fill="#000" fill-opacity="1"/>'
        '</g>',
      );
      final px = await renderAt(doc, Duration.zero);
      expect(alphaAt(px, 25, 50), _near(128));
      expect(alphaAt(px, 75, 50), 255);
    });

    test('颜色自身 alpha x fill-opacity x opacity 三者相乘', () async {
      final doc = parsePixelDoc(
        '<rect width="100" height="100" fill="#00000080" '
        'fill-opacity="0.5" opacity="0.5"/>',
      );
      final px = await renderAt(doc, Duration.zero);
      // 0.502 x 0.5 x 0.5 x 255 约 32
      expect(alphaAt(px, 50, 50), _near(32));
    });

    test('stroke-opacity 只影响描边，不影响填充', () async {
      final doc = parsePixelDoc(
        '<rect x="20" y="20" width="60" height="60" fill="#000" '
        'stroke="#000" stroke-width="10" stroke-opacity="0.25"/>',
      );
      final px = await renderAt(doc, Duration.zero);
      expect(alphaAt(px, 50, 50), 255, reason: '内部只有填充');
      // 描边宽 10，以 x=20 为中心：x=17 在填充之外，只有描边
      expect(alphaAt(px, 17, 50), _near(64));
    });

    test('渐变填充同样受 fill-opacity 影响', () async {
      final doc = parsePixelDoc(
        '<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="0">'
        '<stop offset="0" stop-color="#FF0000"/>'
        '<stop offset="1" stop-color="#0000FF"/></linearGradient></defs>'
        '<rect width="100" height="100" fill="url(#g)" fill-opacity="0.5"/>',
      );
      final px = await renderAt(doc, Duration.zero);
      expect(alphaAt(px, 50, 50), _near(128));
    });

    test('文字填充受 fill-opacity 影响', () async {
      Future<int> maxAlpha(String attrs) async {
        final doc = parsePixelDoc(
          '<text x="20" y="70" font-size="60" font-weight="bold" '
          'fill="#FF0000" $attrs>I</text>',
        );
        final px = await renderAt(doc, Duration.zero);
        var best = 0;
        for (var y = 0; y < kPixelSize; y++) {
          for (var x = 0; x < kPixelSize; x++) {
            final a = alphaAt(px, x, y);
            if (a > best) best = a;
          }
        }
        return best;
      }

      expect(await maxAlpha(''), 255);
      expect(await maxAlpha('fill-opacity="0.5"'), _near(128));
    });

    test('animate fill-opacity 随时间插值并定格', () async {
      final doc = parsePixelDoc(
        '<rect width="100" height="100" fill="#000">'
        '<animate attributeName="fill-opacity" values="0;1" dur="1s" '
        'fill="freeze"/></rect>',
      );
      expect(alphaAt(await renderAt(doc, Duration.zero), 50, 50), 0);
      expect(
        alphaAt(await renderAt(doc, const Duration(milliseconds: 500)), 50, 50),
        _near(128),
      );
      expect(
        alphaAt(await renderAt(doc, const Duration(seconds: 3)), 50, 50),
        255,
      );
    });

    test('fill-opacity=0 不画填充；越界值被钳制', () async {
      final hidden = await renderAt(
        parsePixelDoc(
          '<rect width="100" height="100" fill="#000" fill-opacity="0"/>',
        ),
        Duration.zero,
      );
      expect(alphaAt(hidden, 50, 50), 0);
      final clamped = await renderAt(
        parsePixelDoc(
          '<rect width="100" height="100" fill="#000" fill-opacity="3"/>',
        ),
        Duration.zero,
      );
      expect(alphaAt(clamped, 50, 50), 255);
    });
  });
}
