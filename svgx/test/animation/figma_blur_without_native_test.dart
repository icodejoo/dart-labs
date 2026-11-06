import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';

// Deliberately omit RustLib.init(): transparent Figma prefixes must work with
// the Dart color parser even when the native bridge is unavailable.
// 刻意不调用 RustLib.init()：即使原生桥接不可用，Dart 颜色解析也应能识别
// Figma 的透明前缀，且不能把不透明或非法颜色误认成透明。
void main() {
  for (final color in [
    'transparent',
    ' TrAnSpArEnT ',
    '#ff000000',
    'rgba(255, 0, 0, 0)',
    '#ff0000',
    'invalid',
  ]) {
    for (final input in ['', 'in="blend"']) {
      test('Figma flood $color $input without native initialization', () {
        final doc = parseAnimatedSvgDocument(
          '<svg><defs><filter id="f">'
          '<feFlood flood-color="$color" result="bg"/>'
          '<feBlend mode="normal" in="SourceGraphic" in2="bg" result="blend"/>'
          '<feGaussianBlur $input stdDeviation="3"/>'
          '</filter></defs><rect filter="url(#f)"/></svg>',
        );
        expect(
          doc.root.children.single.blurSigma,
          ['#ff0000', 'invalid'].contains(color) ? isNull : equals(3),
        );
      });
    }
  }
}
