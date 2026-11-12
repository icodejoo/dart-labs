// feGaussianBlur 的 stdDeviation 两值写法（`"40,40"`）：SVGator 等工具一律这么写，
// 此前只认单个数值，导致滤镜被静默丢弃、模糊的光晕渲染成边缘锐利的形状。

import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/svg_document_parser.dart';

/// 解析带一个模糊滤镜的矩形，返回矩形节点的模糊 σ。
double? _sigmaOf(String stdDeviation) {
  final doc = parseAnimatedSvgDocument(
    '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">'
    '<defs><filter id="f"><feGaussianBlur stdDeviation="$stdDeviation"/></filter></defs>'
    '<rect width="5" height="5" filter="url(#f)"/></svg>',
  );
  return doc.root.children.single.blurSigma;
}

void main() {
  test('单值写法保持不变', () {
    expect(_sigmaOf('3'), 3);
    expect(_sigmaOf('2.5'), 2.5);
  });

  test('两值相等：逗号、空白、逗号加空白都解析为同一个 σ', () {
    expect(_sigmaOf('40,40'), 40);
    expect(_sigmaOf('7 7'), 7);
    expect(_sigmaOf('24, 24'), 24);
    expect(_sigmaOf('  30 , 30  '), 30);
  });

  test('两值不等：取平均作近似（引擎只支持各向同性）', () {
    expect(_sigmaOf('2,6'), 4);
  });

  test('0,0 解析为 0，不产生模糊', () {
    expect(_sigmaOf('0,0'), 0);
  });

  test('畸形写法返回 null 而不抛异常', () {
    for (final bad in ['', 'abc', '1,abc', 'abc,1', '1,2,3', ',', '--1']) {
      expect(() => _sigmaOf(bad), returnsNormally, reason: bad);
      expect(_sigmaOf(bad), isNull, reason: bad);
    }
  });
}
