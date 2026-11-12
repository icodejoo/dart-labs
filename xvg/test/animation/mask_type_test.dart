// `mask-type` 的像素测试：alpha 遮罩按内容 alpha 取覆盖度（而非亮度），精确管线
// 与近似管线结果一致，luminance 默认行为逐像素不变。

import 'package:flutter_test/flutter_test.dart';

import 'pixel_test_utils.dart';
import 'rule_pixel_utils.dart';

/// 深蓝（亮度极低、完全不透明）。
const String _dark = '#070772';

/// 遮罩内容区域内一点（矩形 10..90）。
const int _inside = 50;

/// 构造 `<mask id="m">`，再用它遮罩红色满画布。
String _doc(String maskAttrs, String maskContent) =>
    '<mask id="m" $maskAttrs>$maskContent</mask>'
    '<g mask="url(#m)">$kRedFill</g>';

/// 深色不透明矩形（10..90）作为遮罩内容。
const String _darkRect =
    '<rect x="10" y="10" width="80" height="80" fill="$_dark"/>';

/// 渲染后返回中心点的 alpha。
Future<int> _centerAlpha(
  String maskAttrs,
  String content, {
  bool approximate = false,
}) async {
  final px = await renderBody(
    _doc(maskAttrs, content),
    approximate: approximate,
  );
  return alphaAt(px, _inside, _inside);
}

/// 遮罩是否被判定可用裁剪替代（先绘制一次触发判定）。
Future<bool> _eligible(String maskAttrs, String content) async {
  final doc = parseBody(_doc(maskAttrs, content));
  await renderDoc(doc, approximate: true);
  return doc.masks.values.single.maskClipEligible ?? false;
}

void main() {
  group('精确管线', () {
    test('luminance（默认）：深色填充几乎全遮住', () async {
      expect(await _centerAlpha('', _darkRect), lessThan(30));
    });

    test('alpha：同样的内容完全显示', () async {
      expect(await _centerAlpha('mask-type="alpha"', _darkRect), 255);
    });

    test('alpha：遮罩外区域覆盖度为 0', () async {
      final px = await renderBody(_doc('mask-type="alpha"', _darkRect));
      expect(alphaAt(px, 5, 5), 0);
      expect(alphaAt(px, 95, 95), 0);
    });

    test('alpha：半透明内容约 50%', () async {
      final alpha = await _centerAlpha(
        'mask-type="alpha"',
        '<rect x="10" y="10" width="80" height="80" fill="$_dark" '
            'opacity=".5"/>',
      );
      expect(alpha, inInclusiveRange(124, 132));
    });

    test('alpha：fill-opacity 同样按 alpha 计', () async {
      final alpha = await _centerAlpha(
        'mask-type="alpha"',
        '<rect x="10" y="10" width="80" height="80" fill="#fff" '
            'fill-opacity=".25"/>',
      );
      expect(alpha, inInclusiveRange(60, 68));
    });

    test('alpha：颜色无关，纯黑与纯白覆盖度相同', () async {
      final black = await _centerAlpha(
        'mask-type="alpha"',
        '<rect x="10" y="10" width="80" height="80" fill="#000"/>',
      );
      final white = await _centerAlpha(
        'mask-type="alpha"',
        '<rect x="10" y="10" width="80" height="80" fill="#fff"/>',
      );
      expect(black, 255);
      expect(white, 255);
    });
  });

  group('写法与取值', () {
    test('style 内联写法', () async {
      expect(await _centerAlpha('style="mask-type:alpha"', _darkRect), 255);
    });

    test('<style> 规则写法', () async {
      final px = await renderBody(
        '<style>#m{mask-type:alpha}</style>${_doc('', _darkRect)}',
      );
      expect(alphaAt(px, _inside, _inside), 255);
    });

    test('大小写与空白不敏感', () async {
      expect(await _centerAlpha('mask-type=" ALPHA "', _darkRect), 255);
    });

    test('非法值与显式 luminance 都与默认逐像素一致', () async {
      final base = await renderBody(_doc('', _darkRect));
      final bogus = await renderBody(_doc('mask-type="bogus"', _darkRect));
      final explicit = await renderBody(
        _doc('mask-type="luminance"', _darkRect),
      );
      expect(samePixels(base, bogus), isTrue);
      expect(samePixels(base, explicit), isTrue);
    });

    test('默认 luminance：白色遮罩仍然完全显示（回归）', () async {
      expect(
        await _centerAlpha(
          '',
          '<rect x="10" y="10" width="80" height="80" fill="#fff"/>',
        ),
        255,
      );
    });
  });

  group('近似管线', () {
    test('alpha：深色不透明形状判定为可替代，luminance 下不可', () async {
      expect(await _eligible('mask-type="alpha"', _darkRect), isTrue);
      expect(await _eligible('', _darkRect), isFalse);
    });

    test('alpha：近似与精确在内部与外部像素一致', () async {
      final exact = await renderBody(_doc('mask-type="alpha"', _darkRect));
      final approx = await renderBody(
        _doc('mask-type="alpha"', _darkRect),
        approximate: true,
      );
      for (final (x, y) in [(50, 50), (20, 20), (80, 80), (5, 5), (95, 50)]) {
        expect(alphaAt(approx, x, y), alphaAt(exact, x, y), reason: '($x,$y)');
      }
    });

    test('alpha：未写 fill（默认黑色不透明）算完全显示', () async {
      const content = '<rect x="10" y="10" width="80" height="80"/>';
      expect(await _eligible('mask-type="alpha"', content), isTrue);
      expect(
        await _centerAlpha('mask-type="alpha"', content, approximate: true),
        255,
      );
      expect(await _centerAlpha('mask-type="alpha"', content), 255);
    });

    test('alpha：半透明形状不合格，近似开关下结果仍与精确一致', () async {
      const content =
          '<rect x="10" y="10" width="80" height="80" fill="#fff" '
          'opacity=".5"/>';
      expect(await _eligible('mask-type="alpha"', content), isFalse);
      final exact = await _centerAlpha('mask-type="alpha"', content);
      final approx = await _centerAlpha(
        'mask-type="alpha"',
        content,
        approximate: true,
      );
      expect(approx, exact);
      expect(exact, inInclusiveRange(124, 132));
    });

    test('alpha：#RRGGBBAA 的 alpha=0 形状不覆盖也不擦除', () async {
      const content =
          '<rect x="10" y="10" width="80" height="80" fill="$_dark"/>'
          '<rect x="40" y="40" width="20" height="20" fill="#00000000"/>';
      expect(await _eligible('mask-type="alpha"', content), isTrue);
      for (final approximate in [false, true]) {
        expect(
          await _centerAlpha(
            'mask-type="alpha"',
            content,
            approximate: approximate,
          ),
          255,
          reason: 'approximate=$approximate：透明形状不会在不透明形状上打洞',
        );
      }
    });

    test('alpha：fill="none" 的形状什么都不贡献', () async {
      const content =
          '<rect x="10" y="10" width="80" height="80" fill="none"/>';
      for (final approximate in [false, true]) {
        expect(
          await _centerAlpha(
            'mask-type="alpha"',
            content,
            approximate: approximate,
          ),
          0,
        );
      }
    });

    test('luminance 近似语义不变：黑色打洞、白色显示', () async {
      const content =
          '<rect x="10" y="10" width="80" height="80" fill="#fff"/>'
          '<rect x="40" y="40" width="20" height="20" fill="#000"/>';
      final px = await renderBody(_doc('', content), approximate: true);
      expect(alphaAt(px, _inside, _inside), 0);
      expect(alphaAt(px, 20, 20), 255);
    });
  });

  group('带动画的 alpha 遮罩', () {
    test('遮罩内容动画期间仍按 alpha 取覆盖度', () async {
      final doc = parseBody(
        _doc(
          'mask-type="alpha"',
          '<rect x="10" y="10" width="80" height="80" fill="$_dark">'
              '<animate attributeName="opacity" from="1" to="0.5" dur="2s" '
              'fill="freeze"/></rect>',
        ),
      );
      final start = await renderDoc(doc);
      final end = await renderDoc(doc, time: const Duration(seconds: 3));
      expect(alphaAt(start, _inside, _inside), 255);
      expect(alphaAt(end, _inside, _inside), inInclusiveRange(124, 132));
    });
  });
}
