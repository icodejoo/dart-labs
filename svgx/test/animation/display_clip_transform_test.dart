import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/svgx.dart' show RustLib;

import 'pixel_test_utils.dart';

/// 验证 `display="none"` 与"clip-path 跟随节点自身 transform"的像素语义。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var nativeReady = false;
  setUpAll(() async {
    try {
      await RustLib.init();
      nativeReady = true;
    } catch (_) {
      // 静态 transform 需要原生库解析，缺失时对应用例自跳过。
    }
  });

  test('display="none" 的分组整棵子树不绘制', () async {
    final doc = parsePixelDoc('''
<g display="none"><rect width="20" height="20" fill="#f00"/></g>
<rect x="50" y="50" width="20" height="20" fill="#00f"/>''');
    final pixels = await renderAt(doc, Duration.zero);
    expect(alphaAt(pixels, 10, 10), 0);
    expect(alphaAt(pixels, 60, 60), 255);
  });

  test('display="none" 的节点上的子元素即使显式可见也不绘制', () async {
    final doc = parsePixelDoc('''
<g display="none"><g display="inline">
<rect width="20" height="20" fill="#f00"/></g></g>''');
    expect(alphaAt(await renderAt(doc, Duration.zero), 10, 10), 0);
  });

  test('clip-path 与 transform 在同一节点：裁剪随节点变换', () async {
    if (!nativeReady) {
      markTestSkipped('原生库不可用，无法解析静态 transform');
      return;
    }
    // 裁剪矩形在节点局部坐标 (0,0,10,10)；节点平移 (40,40) 后，
    // 可见区域应落在 (40..50, 40..50)，而不是父坐标系的 (0..10, 0..10)。
    final doc = parsePixelDoc('''
<defs><clipPath id="c"><rect width="10" height="10"/></clipPath></defs>
<g transform="translate(40 40)" clip-path="url(#c)">
<rect width="30" height="30" fill="#f00"/></g>''');
    final pixels = await renderAt(doc, Duration.zero);
    expect(alphaAt(pixels, 45, 45), 255);
    expect(alphaAt(pixels, 5, 5), 0);
    expect(alphaAt(pixels, 60, 60), 0, reason: '超出局部裁剪矩形');
  });

  test('clip-path 与 SMIL 平移动画同节点：裁剪跟着动画走', () async {
    final doc = parsePixelDoc('''
<defs><clipPath id="c"><rect width="10" height="10"/></clipPath></defs>
<g clip-path="url(#c)"><animateTransform attributeName="transform"
type="translate" from="0 0" to="60 0" dur="1s" fill="freeze"/>
<rect width="30" height="30" fill="#f00"/></g>''');
    final end = await renderAt(doc, const Duration(seconds: 2));
    expect(alphaAt(end, 65, 5), 255);
    expect(alphaAt(end, 5, 5), 0);
  });

  test('无 transform 的节点裁剪行为不变', () async {
    final doc = parsePixelDoc('''
<defs><clipPath id="c"><rect width="10" height="10"/></clipPath></defs>
<rect width="30" height="30" fill="#f00" clip-path="url(#c)"/>''');
    final pixels = await renderAt(doc, Duration.zero);
    expect(alphaAt(pixels, 5, 5), 255);
    expect(alphaAt(pixels, 20, 20), 0);
  });

  test('mask 与 transform 在同一节点：遮罩随节点变换', () async {
    if (!nativeReady) {
      markTestSkipped('原生库不可用，无法解析静态 transform');
      return;
    }
    final doc = parsePixelDoc('''
<defs><mask id="m"><rect width="10" height="10" fill="#fff"/></mask></defs>
<g transform="translate(40 40)" mask="url(#m)">
<rect width="30" height="30" fill="#f00"/></g>''');
    final pixels = await renderAt(doc, Duration.zero);
    expect(alphaAt(pixels, 45, 45), 255);
    expect(alphaAt(pixels, 5, 5), 0);
    expect(alphaAt(pixels, 60, 60), 0, reason: '超出局部遮罩矩形');
  });

  test('mask 与 SMIL 平移同节点：遮罩跟着动画走', () async {
    final doc = parsePixelDoc('''
<defs><mask id="m"><rect width="10" height="10" fill="#fff"/></mask></defs>
<g mask="url(#m)"><animateTransform attributeName="transform"
type="translate" from="0 0" to="60 0" dur="1s" fill="freeze"/>
<rect width="30" height="30" fill="#f00"/></g>''');
    final end = await renderAt(doc, const Duration(seconds: 2));
    expect(alphaAt(end, 65, 5), 255);
    expect(alphaAt(end, 5, 5), 0);
  });

  test('clipPath 子形状上的 animateMotion 也参与裁剪区域', () async {
    final doc = parsePixelDoc('''
<defs><clipPath id="c"><rect width="10" height="10">
<animateMotion path="M0 0 L60 0" dur="1s" fill="freeze"/></rect></clipPath></defs>
<rect width="100" height="30" fill="#f00" clip-path="url(#c)"/>''');
    final end = await renderAt(doc, const Duration(seconds: 2));
    expect(alphaAt(end, 65, 5), 255);
    expect(alphaAt(end, 5, 5), 0);
  });
}
