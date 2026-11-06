import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';

import 'pixel_test_utils.dart';

/// 包一层带根样式的 `<svg>`，视口 100x100。
SvgDocument _doc(String rootStyle, String body) => parseAnimatedSvgDocument(
  '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" '
  'viewBox="0 0 100 100" $rootStyle>$body</svg>',
);

/// 验证根元素背景色的解析与整面铺底。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('style 里的 background-color 被解析并铺满画面', () async {
    final doc = _doc(
      'style="background-color:#ff0000"',
      '<rect x="40" y="40" width="20" height="20" fill="#0000ff"/>',
    );
    expect(doc.backgroundColor, isNotNull);
    final pixels = await renderAt(doc, Duration.zero);
    expect(redAt(pixels, 5, 5), 255);
    expect(alphaAt(pixels, 5, 5), 255);
    expect(redAt(pixels, 50, 50), 0, reason: '前景矩形盖在背景之上');
  });

  test('background 简写里的纯色也生效；无背景时保持透明', () async {
    final shorthand = _doc('style="background:#00ff00"', '');
    expect(alphaAt(await renderAt(shorthand, Duration.zero), 5, 5), 255);
    final none = _doc('', '');
    expect(none.backgroundColor, isNull);
    expect(alphaAt(await renderAt(none, Duration.zero), 5, 5), 0);
  });

  test('不认识的写法（渐变、命名色之外的值）静默忽略', () {
    expect(_doc('style="background:url(x.png)"', '').backgroundColor, isNull);
    expect(
      _doc('style="background:linear-gradient(red,blue)"', '').backgroundColor,
      isNull,
    );
  });

  test('<style> 规则里的 svg 背景同样生效', () async {
    final doc = _doc('', '<style>svg{background-color:#f00}</style>');
    expect(alphaAt(await renderAt(doc, Duration.zero), 5, 5), 255);
  });
}
