import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';

/// 测试自然尺寸。
const Size _natural = Size(120, 60);

/// 用固定自然尺寸和容器测试图片缩放。
Size _box({LuckyLength? width, LuckyLength? height}) => computeImageBox(
    natural: _natural,
    width: width,
    height: height,
    maxWidth: 200,
    maxHeight: 300);

/// 验证上游尺寸分支与图片偏移。
void main() {
  group('computeImageBox', () {
    test('no width and height uses natural size', () {
      expect(_box(), _natural);
    });
    test('only width scales height proportionally', () {
      expect(_box(width: const LuckyLength.px(90)), const Size(90, 45));
    });
    test('only height scales width proportionally', () {
      expect(_box(height: const LuckyLength.px(90)), const Size(180, 90));
    });
    test('both width and height are used as given', () {
      expect(
          _box(
              width: const LuckyLength.px(80),
              height: const LuckyLength.px(70)),
          const Size(80, 70));
    });
    test('percent sizes resolve against the provided max box', () {
      expect(
          _box(
              width: const LuckyLength.percent(50),
              height: const LuckyLength.percent(25)),
          const Size(100, 75));
    });
    test('placement centers in its box and resolves independent offset bases',
        () {
      const image = LuckyImage(AssetImage('unused'),
          width: LuckyLength.percent(50),
          left: LuckyLength.percent(10),
          top: LuckyLength.percent(20));
      final placement = LuckyImagePlacement(
          slot: const LuckyImageSlot('prize', 0, 0),
          image: image.copyWith(),
          box: const Rect.fromLTWH(10, 20, 200, 300),
          maxWidth: 200,
          maxHeight: 300,
          leftBase: 50,
          topBase: 100,
          yOffset: -10);
      expect(placement.place(_natural), const Rect.fromLTWH(65, 30, 100, 50));
      expect(placement.slot, const LuckyImageSlot('prize', 0, 0));
      const centered = LuckyImagePlacement(
          slot: LuckyImageSlot('button', 0, 0),
          image: LuckyImage(AssetImage('unused')),
          box: Rect.zero,
          maxWidth: 100,
          maxHeight: 100,
          leftBase: 100,
          topBase: 100);
      expect(centered.place(_natural), const Rect.fromLTWH(-60, 0, 120, 60));
    });
  });
}
