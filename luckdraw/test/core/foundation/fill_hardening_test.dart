import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';

/// 验证渐变值对象各字段独立参与相等性。
void main() {
  test('gradient directions with different keywords are unequal both ways', () {
    const top = LuckyLegacyGradientDirection.keyword(LuckyGradientKeyword.top);
    const bottom =
        LuckyLegacyGradientDirection.keyword(LuckyGradientKeyword.bottom);
    const rect = Rect.fromLTWH(3, 5, 40, 60);
    expect(top.degrees, isNull);
    expect(bottom.degrees, isNull);
    expect(top == bottom, isFalse);
    expect(bottom == top, isFalse);
    expect(top.endpoints(rect), (rect.bottomLeft, rect.topLeft));
    expect(bottom.endpoints(rect), (rect.topLeft, rect.bottomLeft));
  });

  test('color stops with the same color and different offsets are unequal', () {
    const color = Color(0xffff0000);
    const firstOffset = 0.25;
    const nextOffset = 0.75;
    const first = LuckyColorStop(color, firstOffset);
    const next = LuckyColorStop(color, nextOffset);
    expect(first == next, isFalse);
    expect(next == first, isFalse);
    final copied = first.copyWith(offset: nextOffset);
    expect(copied.color, first.color);
    expect(copied.offset, nextOffset);
    expect(copied, next);
    expect(copied == first, isFalse);
    expect(first.copyWith(), first);
  });
}
