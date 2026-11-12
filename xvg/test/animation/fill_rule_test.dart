// `fill-rule` 的像素测试：属性/style/<style> 三种来源、继承与覆盖、非法值、
// 渐变填充、描边不受影响、动画期间稳定，以及共享几何缓存不被污染。

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pixel_test_utils.dart';
import 'rule_pixel_utils.dart';

/// 嵌套路径中心（内框内部）。
const int _center = 50;

/// 外框与内框之间的圆环区域内一点。
const int _ring = 20;

/// 渲染一个以 [attrs] 修饰的嵌套路径。
Future<ByteData> _nested(String attrs, {String d = kNestedSameDir}) =>
    renderBody('<path d="$d" fill="#00f" $attrs/>');

void main() {
  group('来源', () {
    test('默认 nonzero：同向嵌套中心被填满', () async {
      final px = await _nested('');
      expect(alphaAt(px, _center, _center), 255);
      expect(alphaAt(px, _ring, _ring), 255);
    });

    test('属性写法 evenodd：中心挖空、圆环保留', () async {
      final px = await _nested('fill-rule="evenodd"');
      expect(alphaAt(px, _center, _center), 0);
      expect(alphaAt(px, _ring, _ring), 255);
      expect(alphaAt(px, 5, 5), 0, reason: '外框之外本来就没有填充');
    });

    test('style 内联写法', () async {
      final px = await _nested('style="fill-rule:evenodd"');
      expect(alphaAt(px, _center, _center), 0);
    });

    test('<style> 规则写法（类选择器与元素选择器）', () async {
      final byClass = await renderBody(
        '<style>.eo{fill-rule:evenodd}</style>'
        '<path class="eo" d="$kNestedSameDir" fill="#00f"/>',
      );
      expect(alphaAt(byClass, _center, _center), 0);
      final byTag = await renderBody(
        '<style>path{fill-rule:evenodd}</style>'
        '<path d="$kNestedSameDir" fill="#00f"/>',
      );
      expect(alphaAt(byTag, _center, _center), 0);
    });

    test('取值大小写不敏感且忽略首尾空白', () async {
      final px = await _nested('fill-rule=" EvenOdd "');
      expect(alphaAt(px, _center, _center), 0);
      final explicitNonZero = await _nested('fill-rule="NONZERO"');
      expect(alphaAt(explicitNonZero, _center, _center), 255);
    });
  });

  group('嵌套方向', () {
    test('反向嵌套：nonzero 与 evenodd 都挖空', () async {
      final nonZero = await _nested('', d: kNestedReverseDir);
      final evenOdd = await _nested(
        'fill-rule="evenodd"',
        d: kNestedReverseDir,
      );
      expect(alphaAt(nonZero, _center, _center), 0);
      expect(alphaAt(evenOdd, _center, _center), 0);
      expect(alphaAt(nonZero, _ring, _ring), 255);
      expect(alphaAt(evenOdd, _ring, _ring), 255);
    });

    test('同向嵌套才是两种规则的分水岭', () async {
      final nonZero = await _nested('');
      final evenOdd = await _nested('fill-rule="evenodd"');
      expect(samePixels(nonZero, evenOdd), isFalse);
    });
  });

  group('继承', () {
    test('<g fill-rule> 继承给子路径', () async {
      final px = await renderBody(
        '<g fill-rule="evenodd"><path d="$kNestedSameDir" fill="#00f"/></g>',
      );
      expect(alphaAt(px, _center, _center), 0);
    });

    test('子元素覆盖父元素', () async {
      final px = await renderBody(
        '<g fill-rule="evenodd">'
        '<path d="$kNestedSameDir" fill="#00f" fill-rule="nonzero"/></g>',
      );
      expect(alphaAt(px, _center, _center), 255);
    });

    test('非法值保持继承值', () async {
      final inherited = await renderBody(
        '<g fill-rule="evenodd">'
        '<path d="$kNestedSameDir" fill="#00f" fill-rule="bogus"/></g>',
      );
      expect(alphaAt(inherited, _center, _center), 0);
      final noParent = await _nested('fill-rule="bogus"');
      expect(alphaAt(noParent, _center, _center), 255);
    });
  });

  group('其它绘制路径', () {
    test('渐变填充同样遵守', () async {
      const gradient =
          '<defs><linearGradient id="g" x1="0" x2="1" y1="0" y2="0">'
          '<stop offset="0" stop-color="#f00"/>'
          '<stop offset="1" stop-color="#00f"/></linearGradient></defs>';
      final evenOdd = await renderBody(
        '$gradient<path d="$kNestedSameDir" fill="url(#g)" '
        'fill-rule="evenodd"/>',
      );
      final nonZero = await renderBody(
        '$gradient<path d="$kNestedSameDir" fill="url(#g)"/>',
      );
      expect(alphaAt(evenOdd, _center, _center), 0);
      expect(alphaAt(evenOdd, _ring, _ring), 255);
      expect(alphaAt(nonZero, _center, _center), 255);
    });

    test('描边不受 fill-rule 影响', () async {
      const stroked =
          '<path d="$kNestedSameDir" fill="none" stroke="#00f" '
          'stroke-width="6"';
      final a = await renderBody('$stroked/>');
      final b = await renderBody('$stroked fill-rule="evenodd"/>');
      expect(samePixels(a, b), isTrue);
      expect(alphaAt(b, 10, _center), 255, reason: '外框描边仍然存在');
    });

    test('填充描边并存：evenodd 只挖空填充，描边照画', () async {
      final px = await renderBody(
        '<path d="$kNestedSameDir" fill="#00f" stroke="#f00" '
        'stroke-width="6" fill-rule="evenodd"/>',
      );
      expect(alphaAt(px, _center, _center), 0);
      expect(alphaAt(px, 30, _center), 255, reason: '内框描边');
    });
  });

  group('动画与缓存', () {
    test('其它属性动画期间 fill-rule 保持稳定', () async {
      final doc = parseBody(
        '<path d="$kNestedSameDir" fill="#00f" fill-rule="evenodd">'
        '<animate attributeName="opacity" from="1" to="0.5" dur="2s" '
        'fill="freeze"/></path>',
      );
      for (final ms in [0, 500, 1000, 3000]) {
        final px = await renderDoc(doc, time: Duration(milliseconds: ms));
        expect(alphaAt(px, _center, _center), 0, reason: 't=$ms 中心应挖空');
        expect(alphaAt(px, _ring, _ring), greaterThan(100), reason: 't=$ms');
      }
    });

    test('共用同一 d 的两个节点互不影响，缓存几何始终是 nonzero', () async {
      const small = 'M5 5H35V35H5Z M15 15H25V25H15Z';
      final doc = parseBody(
        '<path d="$small" fill="#00f" fill-rule="evenodd"/>'
        '<path d="$small" fill="#00f">'
        '<animateTransform attributeName="transform" type="translate" '
        'from="50 0" to="50 0" dur="1s" fill="freeze"/></path>',
      );
      for (var frame = 0; frame < 2; frame++) {
        final px = await renderDoc(doc);
        expect(alphaAt(px, 20, 20), 0, reason: '左侧 evenodd 挖空');
        expect(alphaAt(px, 70, 20), 255, reason: '右侧默认填满');
        expect(alphaAt(px, 8, 8), 255);
        expect(alphaAt(px, 58, 8), 255);
      }
      for (final node in doc.root.children) {
        expect(
          node.cachedGeometry!.fillType,
          ui.PathFillType.nonZero,
          reason: '共享缓存画完必须还原',
        );
      }
    });
  });

  group('mask 近似管线中的内容也遵守 fill-rule', () {
    const mask =
        '<mask id="m"><path d="$kNestedSameDir" fill="#fff" '
        'fill-rule="evenodd"/></mask>';
    for (final approximate in [false, true]) {
      test('approximate=$approximate：白色 evenodd 环挖出洞', () async {
        final px = await renderBody(
          '$mask<g mask="url(#m)">$kRedFill</g>',
          approximate: approximate,
        );
        expect(alphaAt(px, _center, _center), 0);
        expect(alphaAt(px, _ring, _ring), 255);
      });
    }
  });
}
