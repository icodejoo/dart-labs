import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/src/core/foundation/color_utils.dart';

/// 验证跨 Flutter 版本的八位透明度读取和乘法。
void main() {
  group('colorAlpha8', () {
    test('reads alpha of opaque and translucent colors', () {
      expect(colorAlpha8(const Color(0xFF123456)), 255);
      expect(colorAlpha8(const Color(0x80123456)), 128);
      expect(colorAlpha8(const Color(0x00123456)), 0);
    });
    test('colorWithAlphaFactor multiplies alpha and rounds', () {
      const color = Color(0xFF123456);
      expect(colorWithAlphaFactor(color, 0.5), const Color(0x80123456));
      expect(colorWithAlphaFactor(const Color(0x03123456), 0.5),
          const Color(0x02123456));
      expect(colorWithAlphaFactor(color, 0), const Color(0x00123456));
      expect(colorWithAlphaFactor(color, 1), color);
      expect(colorWithAlphaFactor(color, -1), const Color(0x00123456));
      expect(colorWithAlphaFactor(color, 2), color);
    });
  });
}
