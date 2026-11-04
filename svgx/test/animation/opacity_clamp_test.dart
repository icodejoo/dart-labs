// `opacity` 属性钳制到 [0, 1]：与 `fill-opacity` / `stroke-opacity` 一致。
// 回弹类缓动（y 越出 0~1）会让 opacity 动画越界，而 fillAlpha = opacity *
// fillOpacity 在越界值下会算错，所以解析处就要钳制。

import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/svg_style.dart';
import 'package:svgx/src/animation/svg_theme.dart';

import 'pixel_test_utils.dart';

/// 半透明在 8 位 alpha 上允许的舍入误差。
const int _alphaSlack = 2;

/// 255 x 0.5 四舍五入后的 alpha。
const int _halfAlpha = 128;

/// 全幅矩形，[attrs] 为附加在 `<rect>` 上的属性。
String _fullRect(String attrs) =>
    '<rect width="$kPixelSize" height="$kPixelSize" fill="#000" $attrs/>';

/// 渲染 [attrs] 对应的全幅矩形，返回画面中心的 alpha。
Future<int> _centerAlpha(String attrs) async {
  final px = await renderAt(parsePixelDoc(_fullRect(attrs)), Duration.zero);
  return alphaAt(px, kPixelSize ~/ 2, kPixelSize ~/ 2);
}

void main() {
  group('ResolvedStyle.opacity', () {
    const theme = SvgxTheme();

    /// 以 [attributes] 解析出的 opacity，父级为默认样式。
    double resolved(Map<String, String> attributes) =>
        ResolvedStyle.initial.inherit(attributes, theme).opacity;

    test('超过 1 钳到 1', () {
      expect(resolved({'opacity': '1.5'}), 1);
    });

    test('小于 0 钳到 0', () {
      expect(resolved({'opacity': '-0.2'}), 0);
    });

    test('范围内的值原样保留', () {
      expect(resolved({'opacity': '0.3'}), 0.3);
      expect(resolved({'opacity': '0'}), 0);
      expect(resolved({'opacity': '1'}), 1);
    });

    test('缺失时使用本节点默认值 1', () {
      final parent = ResolvedStyle.initial.inherit({'opacity': '0.4'}, theme);
      expect(parent.inherit({}, theme).opacity, 1);
      expect(resolved({}), 1, reason: '默认样式的 opacity 为 1');
    });

    test('非数字时使用本节点默认值 1', () {
      final parent = ResolvedStyle.initial.inherit({'opacity': '0.4'}, theme);
      expect(parent.inherit({'opacity': 'abc'}, theme).opacity, 1);
      expect(parent.inherit({'opacity': ''}, theme).opacity, 1);
    });

    test('子节点越界值也钳制，不受父级影响', () {
      final parent = ResolvedStyle.initial.inherit({'opacity': '0.4'}, theme);
      expect(parent.inherit({'opacity': '3'}, theme).opacity, 1);
      expect(parent.inherit({'opacity': '-3'}, theme).opacity, 0);
    });
  });

  group('像素', () {
    test('opacity="1.5" 按 1 渲染：中心完全不透明', () async {
      expect(await _centerAlpha('opacity="1.5"'), 255);
    });

    test('opacity="-1" 按 0 渲染：中心完全透明', () async {
      expect(await _centerAlpha('opacity="-1"'), 0);
    });

    test('opacity="1.5" 与 fill-opacity=".5" 相乘：alpha 约 128 而非 191', () async {
      // 不钳制时 1.5 x 0.5 = 0.75，alpha 会约为 191。
      expect(
        await _centerAlpha('opacity="1.5" fill-opacity=".5"'),
        inInclusiveRange(_halfAlpha - _alphaSlack, _halfAlpha + _alphaSlack),
      );
    });
  });
}
