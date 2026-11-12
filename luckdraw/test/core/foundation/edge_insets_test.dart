import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/luckdraw.dart';

/// 验证 CSS 简写顺序及内边距的复制、相等性。
void main() {
  group('LuckyEdgeInsets', () {
    test('insets differing only in left are unequal in both directions', () {
      const original = LuckyEdgeInsets.only(left: 1);
      final changed = original.copyWith(left: original.left + 1);
      expect(original == changed, isFalse);
      expect(changed == original, isFalse);
      expect(original.copyWith(), original);
      expect(original.copyWith().hashCode, original.hashCode);
    });
    test('css shorthand with 1 value applies to all sides', () {
      final insets = LuckyEdgeInsets.css([8]);
      expect(insets, const LuckyEdgeInsets.all(8));
      expect(
          [insets.top, insets.right, insets.bottom, insets.left], [8, 8, 8, 8]);
      expect(insets.copyWith(), insets);
      expect(insets.copyWith().hashCode, insets.hashCode);
      expect(LuckyEdgeInsets.zero, const LuckyEdgeInsets.only());
      expect(insets == Object(), isFalse);
    });
    test('css shorthand with 2 values is vertical then horizontal', () {
      final insets = LuckyEdgeInsets.css([4, 8]);
      expect(
          insets, const LuckyEdgeInsets.symmetric(vertical: 4, horizontal: 8));
      expect(
          [insets.top, insets.right, insets.bottom, insets.left], [4, 8, 4, 8]);
      expect(insets.copyWith(top: 2, right: 3, bottom: 6, left: 7),
          const LuckyEdgeInsets.only(top: 2, right: 3, bottom: 6, left: 7));
    });
    test('css shorthand with 3 values is top, horizontal, bottom', () {
      final insets = LuckyEdgeInsets.css([2, 4, 6]);
      expect(
          [insets.top, insets.right, insets.bottom, insets.left], [2, 4, 6, 4]);
    });
    test('css shorthand with 4 values follows CSS top-right-bottom-left order',
        () {
      final insets = LuckyEdgeInsets.css([1, 2, 3, 4]);
      expect(
          [insets.top, insets.right, insets.bottom, insets.left], [1, 2, 3, 4]);
    });
    test('css shorthand rejects empty or more than 4 values', () {
      expect(() => LuckyEdgeInsets.css([]), throwsArgumentError);
      expect(() => LuckyEdgeInsets.css([1, 2, 3, 4, 5]), throwsArgumentError);
    });
  });
}
