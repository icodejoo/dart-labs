import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'pixel_test_utils.dart';

/// 把毫秒转换为采样时间。
Duration _at(int ms) => Duration(milliseconds: ms);

/// 返回不透明像素在 x 方向的最左与最右坐标，没有则为空。
(int, int)? _xRange(ByteData pixels, int y) {
  int? left, right;
  for (var x = 0; x < kPixelSize; x++) {
    if (alphaAt(pixels, x, y) < 128) continue;
    left ??= x;
    right = x;
  }
  return left == null ? null : (left, right!);
}

/// 统计一行上不透明段的数量，用于判断虚线图案。
int _runs(ByteData pixels, int y) {
  var runs = 0;
  var inRun = false;
  for (var x = 0; x < kPixelSize; x++) {
    final on = alphaAt(pixels, x, y) > 200;
    if (on && !inRun) runs++;
    inRun = on;
  }
  return runs;
}

/// 验证阶段四通道经完整解析后在像素上生效。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fill 颜色关键帧：中点为两端色的混合，无 forwards 时结束回静态', () async {
    final doc = parsePixelDoc('''<style>
@keyframes c{from{fill:#f00}to{fill:#00f}}
#r{animation:c 1s linear}</style>
<rect id="r" width="20" height="20" fill="#0f0"/>''');
    final mid = await renderAt(doc, _at(500));
    expect(redAt(mid, 10, 10), inInclusiveRange(125, 130));
    final after = await renderAt(doc, _at(1500));
    expect(redAt(after, 10, 10), 0, reason: '静态绿色：红通道为 0');
  });

  test('fill 与 none 之间切换：过半后透明', () async {
    final doc = parsePixelDoc('''<style>
@keyframes c{from{fill:#f00}to{fill:none}}
#r{animation:c 1s linear forwards}</style>
<rect id="r" width="20" height="20" fill="#f00"/>''');
    expect(alphaAt(await renderAt(doc, _at(100)), 10, 10), 255);
    expect(alphaAt(await renderAt(doc, _at(900)), 10, 10), 0);
  });

  test('offset-path 运动：沿水平线从左到右', () async {
    final doc = parsePixelDoc('''<style>
@keyframes m{from{offset-distance:0%}to{offset-distance:100%}}
#r{offset-path:path("M10 50 L90 50");animation:m 1s linear forwards}</style>
<rect id="r" x="-5" y="-5" width="10" height="10" fill="#f00"/>''');
    final start = _xRange(await renderAt(doc, _at(0)), 50)!;
    final mid = _xRange(await renderAt(doc, _at(500)), 50)!;
    final end = _xRange(await renderAt(doc, _at(1000)), 50)!;
    expect((start.$1 + start.$2) / 2, closeTo(10, 2));
    expect((mid.$1 + mid.$2) / 2, closeTo(50, 2));
    expect((end.$1 + end.$2) / 2, closeTo(90, 2));
  });

  test('d 变形：命令兼容时中点为两形状的插值', () async {
    final doc = parsePixelDoc('''<style>
@keyframes s{from{d:path("M0 0H20V20H0Z")}to{d:path("M0 0H60V20H0Z")}}
#p{animation:s 1s linear forwards}</style>
<path id="p" d="M0 0H20V20H0Z" fill="#f00"/>''');
    expect(_xRange(await renderAt(doc, _at(0)), 10)!.$2, closeTo(19, 1));
    expect(_xRange(await renderAt(doc, _at(500)), 10)!.$2, closeTo(39, 1));
    expect(_xRange(await renderAt(doc, _at(1000)), 10)!.$2, closeTo(59, 1));
  });

  test('stroke-dasharray 列表动画：虚线段数随关键帧变化', () async {
    final doc = parsePixelDoc(
      '''<style>
@keyframes d{from{stroke-dasharray:10 10}to{stroke-dasharray:40 40}}
#l{animation:d 1s linear forwards}</style>
<line id="l" x1="0" y1="50" x2="100" y2="50" stroke="#f00" stroke-width="6"/>''',
    );
    final first = _runs(await renderAt(doc, _at(0)), 50);
    final last = _runs(await renderAt(doc, _at(1000)), 50);
    expect(first, 5);
    expect(last, 2);
  });

  test('渐变 stop 的 stop-color CSS 动画被编译到 stop 节点', () {
    final doc = parsePixelDoc('''<style>
@keyframes c{from{stop-color:#f00}to{stop-color:#00f}}
#s{animation:c 1s linear infinite}</style>
<defs><linearGradient id="g"><stop id="s" offset="0" stop-color="#f00"/>
<stop offset="1" stop-color="#000"/></linearGradient></defs>
<rect width="50" height="50" fill="url(#g)"/>''');
    final stops = doc.gradients['g']!.stopNodes;
    expect(stops.first.colorAnimations, hasLength(1));
    expect(stops.first.colorAnimations.single.attributeName, 'stop-color');
    expect(doc.hasIndefiniteLoop, isTrue);
  });
}
