import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/xvg.dart' show RustLib;

import 'pixel_test_utils.dart';

/// 公用的不透明红色矩形。
const _rect = '<rect width="10" height="10" fill="#f00"/>';

/// 将毫秒转换为采样时间。
Duration _at(int ms) => Duration(milliseconds: ms);

/// 收集可见像素包围盒，忽略抗锯齿边缘。
(int, int, int, int)? _bounds(ByteData pixels) {
  var left = kPixelSize, top = kPixelSize, right = -1, bottom = -1;
  for (var y = 0; y < kPixelSize; y++) {
    for (var x = 0; x < kPixelSize; x++) {
      if (alphaAt(pixels, x, y) < 16) continue;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }
  return right < 0 ? null : (left, top, right, bottom);
}

/// 一次原生初始化的共享结果。
Future<bool>? _initAttempt;

/// 检查静态变换解析所需的原生库。
Future<bool> _nativeReady() => _initAttempt ??= RustLib.init()
    .then((_) => true)
    .catchError((Object _) => false);

/// 验证 CSS 动画经过绘制后确实改变像素。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('opacity 改变整个矩形内部的 alpha', () async {
    final doc = parsePixelDoc('''<style>
@keyframes a{from{opacity:0}to{opacity:1}}rect{animation:a 1s linear}
</style>$_rect''');
    for (final ms in [250, 500, 750]) {
      final pixels = await renderAt(doc, _at(ms));
      for (var y = 2; y < 8; y++) {
        for (var x = 2; x < 8; x++) {
          expect(alphaAt(pixels, x, y), closeTo(255 * ms / 1000, 1));
        }
      }
    }
  });
  test('translate 改变红色矩形包围盒', () async {
    final doc = parsePixelDoc('''<style>
@keyframes a{from{transform:translate(0px,20px)}to{transform:translate(80px,20px)}}
rect{animation:a 1s linear}</style>$_rect''');
    for (final ms in [250, 500, 750]) {
      final pixels = await renderAt(doc, _at(ms));
      final x = 80 * ms ~/ 1000;
      expect(_bounds(pixels), (x, 20, x + 9, 29));
      for (var column = x + 1; column < x + 9; column++) {
        expect(redAt(pixels, column, 25), 255);
      }
    }
  });
  test('rotate 90 度后矩形位于手算区域', () async {
    final doc = parsePixelDoc(
      '''<style>
@keyframes a{from{transform:translate(50px,50px) rotate(0deg)}
to{transform:translate(50px,50px) rotate(180deg)}}
rect{animation:a 1s linear}</style><rect width="20" height="10" fill="#f00"/>''',
    );
    expect(_bounds(await renderAt(doc, _at(500))), (40, 50, 49, 69));
  });
  test('steps 在跳变前后 1ms 改变像素位置', () async {
    final doc = parsePixelDoc('''<style>
@keyframes a{from{transform:translate(0px)}to{transform:translate(80px)}}
rect{animation:a 1s steps(2,end)}</style>$_rect''');
    expect(_bounds(await renderAt(doc, _at(499))), (0, 0, 9, 9));
    expect(_bounds(await renderAt(doc, _at(501))), (40, 0, 49, 9));
  });
  test('alternate 对称时刻像素逐字节一致', () async {
    final doc = parsePixelDoc('''<style>
@keyframes a{from{transform:translate(0px)}to{transform:translate(80px)}}
rect{animation:a 1s linear infinite alternate}</style>$_rect''');
    for (final ms in [250, 500, 750]) {
      expect(
        (await renderAt(doc, _at(ms))).buffer.asUint8List(),
        (await renderAt(doc, _at(2000 - ms))).buffer.asUint8List(),
      );
    }
  });
  test('三层 SVGator 包装的 translate rotate scale 按矩阵顺序复合', () async {
    final doc = parsePixelDoc('''<style>
@keyframes t{from{transform:translate(20px,20px)}to{transform:translate(60px,60px)}}
@keyframes r{from{transform:rotate(0deg)}to{transform:rotate(180deg)}}
@keyframes s{from{transform:scale(1)}to{transform:scale(3)}}
.to{animation:t 1s linear}.tr{animation:r 1s linear}.ts{animation:s 1s linear}
</style><g class="to"><g class="tr"><g class="ts">$_rect</g></g></g>''');
    // 中点：先放大为 20×20，再旋转 90°，最后平移到 (40,40)。
    expect(_bounds(await renderAt(doc, _at(500))), (20, 40, 39, 59));
  });
  test('M2 mask 内 transform 改变裁剪区域', () async {
    final doc = parsePixelDoc('''<style>
@keyframes a{from{transform:translate(0px)}to{transform:translate(80px)}}
.moving{animation:a 1s linear}</style><defs><mask id="m">
<rect class="moving" width="20" height="20" fill="#fff"/>
</mask></defs><rect width="100" height="100" fill="#f00" mask="url(#m)"/>''');
    for (final approximate in [false, true]) {
      for (final ms in [250, 750]) {
        final pixels = await renderRootAt(
          doc.root,
          _at(ms),
          masks: doc.masks,
          approximateMasks: approximate,
        );
        final x = 80 * ms ~/ 1000;
        expect(_bounds(pixels), (
          x,
          0,
          x + 19,
          19,
        ), reason: 'approximateMasks=$approximate');
      }
    }
  });
  test('M2 mask 内 CSS opacity 动画改变覆盖度', () async {
    final doc = parsePixelDoc('''<style>
@keyframes a{from{opacity:0}to{opacity:1}}.fade{animation:a 1s linear}
</style><defs><mask id="m"><rect class="fade" width="20" height="20" fill="#fff"/>
</mask></defs><rect width="100" height="100" fill="#f00" mask="url(#m)"/>''');
    final track = doc.masks['m']!.children.single.animations.single;
    expect(track.sample(_at(250)), .25);
    expect(track.sample(_at(750)), .75);
    // Sampled opacity must contribute to luminance coverage.
    // 采样后的 opacity 必须计入亮度 mask 的覆盖度。
    final early = await renderAt(doc, _at(250));
    final late = await renderAt(doc, _at(750));
    for (var x = 2; x < 18; x++) {
      expect(alphaAt(early, x, 10), 64);
      expect(alphaAt(late, x, 10), 191);
    }
  });
  test('阶段四：fill 颜色通道生效，动画结束后回到静态外观', () async {
    final doc = parsePixelDoc('''<style>
@keyframes a{from{fill:#00f}to{fill:#0f0}}
rect{animation:a 1s linear}</style>$_rect''');
    final reference = await renderAt(parsePixelDoc(_rect), Duration.zero);
    final start = (await renderAt(doc, _at(1))).buffer.asUint8List();
    expect(start[0], lessThan(10), reason: 'R 通道');
    expect(start[2], greaterThan(245), reason: 'B 通道');
    expect(
      (await renderAt(doc, _at(1001))).buffer.asUint8List(),
      reference.buffer.asUint8List(),
    );
  });
  test('R3 静态 translate 被 CSS 替换，生效期间没有双倍位移', () async {
    if (!await _nativeReady()) {
      markTestSkipped('xvg 原生库不可加载，无法解析静态 transform；无原生覆盖见 painter 级测试');
      return;
    }
    final doc = parsePixelDoc('''<style>
@keyframes a{from{transform:translate(40px)}to{transform:translate(80px)}}
rect{animation:a 2s linear}</style>
<rect transform="translate(40 0)" width="10" height="10" fill="#f00"/>''');
    expect(doc.root.children.single.transform, isNotNull);
    expect(_bounds(await renderAt(doc, _at(1000))), (60, 0, 69, 9));
  });
}
