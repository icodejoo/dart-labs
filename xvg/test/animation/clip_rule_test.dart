// `clip-rule` 的像素测试：`<clipPath>` 内带孔形状按规则裁剪、默认逐像素不变、
// nonzero 与 evenodd 子形状混用、继承与覆盖、变换，以及 fill-rule 不影响裁剪。

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pixel_test_utils.dart';
import 'rule_pixel_utils.dart';

/// 嵌套路径中心（内框内部）。
const int _center = 50;

/// 外框与内框之间的圆环区域内一点。
const int _ring = 20;

/// 用 [clipContent] 构造 `<clipPath id="c">` 并裁剪红色满画布内容后渲染。
Future<ByteData> _clipped(String clipContent, {String clipAttrs = ''}) =>
    renderBody(
      '<clipPath id="c" $clipAttrs>$clipContent</clipPath>'
      '<g clip-path="url(#c)">$kRedFill</g>',
    );

void main() {
  group('单个带孔形状', () {
    test('默认 nonzero：中心不被挖空', () async {
      final px = await _clipped('<path d="$kNestedSameDir"/>');
      expect(alphaAt(px, _center, _center), 255);
      expect(alphaAt(px, _ring, _ring), 255);
      expect(alphaAt(px, 5, 5), 0);
    });

    test('属性 clip-rule=evenodd：中心被裁出孔', () async {
      final px = await _clipped(
        '<path d="$kNestedSameDir" clip-rule="evenodd"/>',
      );
      expect(alphaAt(px, _center, _center), 0);
      expect(alphaAt(px, _ring, _ring), 255);
    });

    test('style 内联与 <style> 规则写法', () async {
      final inline = await _clipped(
        '<path d="$kNestedSameDir" style="clip-rule:evenodd"/>',
      );
      expect(alphaAt(inline, _center, _center), 0);
      final sheet = await renderBody(
        '<style>#p{clip-rule:evenodd}</style>'
        '<clipPath id="c"><path id="p" d="$kNestedSameDir"/></clipPath>'
        '<g clip-path="url(#c)">$kRedFill</g>',
      );
      expect(alphaAt(sheet, _center, _center), 0);
    });

    test('大小写与空白不敏感；非法值回落为默认', () async {
      final loose = await _clipped(
        '<path d="$kNestedSameDir" clip-rule=" EVENODD "/>',
      );
      expect(alphaAt(loose, _center, _center), 0);
      final bogus = await _clipped(
        '<path d="$kNestedSameDir" clip-rule="bogus"/>',
      );
      expect(alphaAt(bogus, _center, _center), 255);
    });

    test('fill-rule 不影响裁剪，clip-rule 不影响填充', () async {
      final fillRuleOnly = await _clipped(
        '<path d="$kNestedSameDir" fill-rule="evenodd"/>',
      );
      expect(alphaAt(fillRuleOnly, _center, _center), 255);
      final clipRuleOnPaint = await renderBody(
        '<path d="$kNestedSameDir" fill="#00f" clip-rule="evenodd"/>',
      );
      expect(alphaAt(clipRuleOnPaint, _center, _center), 255);
    });

    test('默认路径逐像素回归：显式 nonzero 与不写完全相同', () async {
      final implicit = await _clipped('<path d="$kNestedSameDir"/>');
      final explicit = await _clipped(
        '<path d="$kNestedSameDir" clip-rule="nonzero"/>',
      );
      expect(samePixels(implicit, explicit), isTrue);
    });
  });

  group('继承', () {
    test('<clipPath clip-rule> 继承给子形状', () async {
      final px = await _clipped(
        '<path d="$kNestedSameDir"/>',
        clipAttrs: 'clip-rule="evenodd"',
      );
      expect(alphaAt(px, _center, _center), 0);
    });

    test('<g clip-rule> 继承，子元素可覆盖', () async {
      final inherited = await _clipped(
        '<g clip-rule="evenodd"><path d="$kNestedSameDir"/></g>',
      );
      expect(alphaAt(inherited, _center, _center), 0);
      final overridden = await _clipped(
        '<g clip-rule="evenodd">'
        '<path d="$kNestedSameDir" clip-rule="nonzero"/></g>',
      );
      expect(alphaAt(overridden, _center, _center), 255);
    });
  });

  group('混用 nonzero 与 evenodd 子形状', () {
    test('各自按自己的规则成区域后再合并', () async {
      // 左上：evenodd 环（孔应保留）；右下：nonzero 环（孔应被填满）。
      final px = await _clipped(
        '<path d="M5 5H45V45H5Z M15 15H35V35H15Z" clip-rule="evenodd"/>'
        '<path d="M55 55H95V95H55Z M65 65H85V85H65Z"/>',
      );
      expect(alphaAt(px, 25, 25), 0, reason: 'evenodd 子形状的孔');
      expect(alphaAt(px, 10, 10), 255);
      expect(alphaAt(px, 75, 75), 255, reason: 'nonzero 子形状无孔');
      expect(alphaAt(px, 60, 60), 255);
    });

    test('nonzero 子形状盖住 evenodd 孔时，并集会补上那块', () async {
      final px = await _clipped(
        '<path d="$kNestedSameDir" clip-rule="evenodd"/>'
        '<rect x="40" y="40" width="20" height="20"/>',
      );
      expect(alphaAt(px, _center, _center), 255, reason: '被矩形补回');
      expect(alphaAt(px, 35, 35), 0, reason: '孔的其余部分仍挖空');
      expect(alphaAt(px, _ring, _ring), 255);
    });

    test('evenodd 子形状带 transform', () async {
      final px = await _clipped(
        '<path d="M5 5H45V45H5Z M15 15H35V35H15Z" clip-rule="evenodd">'
        '<animateTransform attributeName="transform" type="translate" '
        'from="40 0" to="40 0" dur="1s" fill="freeze"/></path>',
      );
      expect(alphaAt(px, 65, 25), 0, reason: '平移后的孔');
      expect(alphaAt(px, 25, 25), 0, reason: '原位置已无内容');
      expect(alphaAt(px, 50, 10), 255);
    });

    test('嵌套分组里混用时继承各自成立', () async {
      final px = await _clipped(
        '<g clip-rule="evenodd">'
        '<path d="M5 5H45V45H5Z M15 15H35V35H15Z"/>'
        '<path d="M55 55H95V95H55Z M65 65H85V85H65Z" clip-rule="nonzero"/>'
        '</g>',
      );
      expect(alphaAt(px, 25, 25), 0);
      expect(alphaAt(px, 75, 75), 255);
    });

    test('裁剪结果跨帧稳定（每帧重算也一致）', () async {
      final doc = parseBody(
        '<clipPath id="c"><path d="$kNestedSameDir" clip-rule="evenodd"/>'
        '</clipPath><g clip-path="url(#c)">$kRedFill</g>',
      );
      final a = await renderDoc(doc);
      final b = await renderDoc(doc, time: const Duration(seconds: 1));
      expect(samePixels(a, b), isTrue);
      expect(alphaAt(b, _center, _center), 0);
    });
  });
}
