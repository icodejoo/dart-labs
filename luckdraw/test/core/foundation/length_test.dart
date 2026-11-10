import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/luckdraw.dart';

/// 验证长度解析顺序、零值与值相等性。
void main() {
  group('LuckyLength', () {
    test('px resolves to its value regardless of base', () {
      const length = LuckyLength.px(-12.5);
      expect(length.resolve(0), -12.5);
      expect(length.resolve(300), -12.5);
      expect(length.resolve(double.nan), -12.5);
    });
    test('percent resolves as value * (base / 100) like upstream changeUnits',
        () {
      const value = 73.31;
      const base = 123.4567;
      const length = LuckyLength.percent(value);
      expect(length.resolve(base), value * (base / 100));
      expect(const LuckyLength.percent(-50).resolve(200), -100);
      expect(length.resolve(0), 0);
    });
    test('equality and hashCode are value based', () {
      final px = const LuckyPx(12).copyWith();
      final percent = const LuckyPercent(12).copyWith();
      expect(px, const LuckyLength.px(12));
      expect(px.hashCode, const LuckyLength.px(12).hashCode);
      expect(percent, const LuckyLength.percent(12));
      expect(percent.hashCode, const LuckyLength.percent(12).hashCode);
      expect(px, isNot(percent));
      expect(px.copyWith(value: 20), const LuckyPx(20));
      expect(percent.copyWith(value: 20), const LuckyPercent(20));
      expect(px, isNot(const LuckyPx(13)));
      expect(percent, isNot(const LuckyPercent(13)));
      expect(px == Object(), isFalse);
      expect(percent == Object(), isFalse);
    });
    test('zero constant resolves to 0', () {
      expect(LuckyLength.zero.resolve(400), 0);
      expect(LuckyLength.zero, const LuckyLength.px(0));
    });
  });
}
