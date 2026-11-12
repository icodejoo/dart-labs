import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/luckdraw.dart';

/// 验证阴影空间换算及填充透明度的合成规则。
void main() {
  group('LuckyShadow', () {
    const color = Color(0x80123456);
    test('shadows differing only in offsetX are unequal in both directions',
        () {
      const original = LuckyShadow(color: color);
      final changed = original.copyWith(offsetX: 1);
      expect(original == changed, isFalse);
      expect(changed == original, isFalse);
      expect(changed.offsetY, original.offsetY);
      expect(changed.blur, original.blur);
      expect(changed.color, original.color);
      expect(changed.blurSpace, original.blurSpace);
      expect(original.copyWith(), original);
    });
    test('shadows differing only in blurSpace are unequal in both directions',
        () {
      const original = LuckyShadow(blur: 10, color: color);
      final changed = original.copyWith(blurSpace: LuckyShadowBlurSpace.device);
      expect(original == changed, isFalse);
      expect(changed == original, isFalse);
      expect(changed.offsetX, original.offsetX);
      expect(changed.offsetY, original.offsetY);
      expect(changed.blur, original.blur);
      expect(changed.color, original.color);
      const dpr = 2.0;
      const logicalSigma = 5.0;
      expect(original.sigma(dpr), logicalSigma);
      expect(changed.sigma(dpr), logicalSigma / dpr);
      expect(original.copyWith(), original);
    });
    test('logical blur converts to sigma blur / 2', () {
      const shadow = LuckyShadow(blur: 10, color: color);
      expect(shadow.sigma(1), 5);
      expect(shadow.sigma(3), 5);
      expect(shadow.copyWith(), shadow);
      expect(shadow.copyWith().hashCode, shadow.hashCode);
      expect(shadow == Object(), isFalse);
    });
    test('device blur converts to sigma blur / (2 * dpr)', () {
      const shadow = LuckyShadow(
          blur: 10, color: color, blurSpace: LuckyShadowBlurSpace.device);
      expect(shadow.sigma(1), 5);
      expect(shadow.sigma(2), 2.5);
      expect(shadow.sigma(3), 10 / 2 / 3);
      final changed = shadow.copyWith(
          offsetX: 2,
          offsetY: -3,
          blur: 4,
          color: const Color(0xFFFFFFFF),
          blurSpace: LuckyShadowBlurSpace.logical);
      expect(
          changed,
          const LuckyShadow(
              offsetX: 2, offsetY: -3, blur: 4, color: Color(0xFFFFFFFF)));
    });
    test('zero blur produces no mask filter', () {
      const shadow = LuckyShadow(color: color);
      expect(shadow.sigma(2), 0);
      final paint = Paint();
      if (shadow.sigma(2) > 0) {
        paint.maskFilter = MaskFilter.blur(BlurStyle.normal, shadow.sigma(2));
      }
      expect(paint.maskFilter, isNull);
      expect(
          shadow.copyWith(blurSpace: LuckyShadowBlurSpace.device).sigma(2), 0);
    });
    test('shadow alpha is multiplied by solid fill alpha only', () {
      const shadow = LuckyShadow(color: color);
      expect(shadow.colorOver(const LuckyFill.color(Color(0x80111111))),
          const Color(0x40123456));
      expect(shadow.colorOver(const LuckyFill.color(Color(0x00111111))),
          const Color(0x00123456));
      expect(shadow.colorOver(const LuckyFill.color(Color(0xFFFFFFFF))), color);
      expect(shadow.colorOver(null), color);
      expect(
          shadow.colorOver(
              const LuckyFill.gradient(LinearGradient(colors: [color, color]))),
          color);
      expect(
          shadow.colorOver(const LuckyFill.legacyLinear(
              LuckyLegacyGradientDirection.angle(0),
              [LuckyColorStop(color), LuckyColorStop(color)])),
          color);
    });
  });
}
