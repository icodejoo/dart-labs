import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';

/// 固定宽度测量，隔离坐标和样式解析测试。
final class _Measurer implements LuckyTextMeasurer {
  /// 每码点十像素。
  @override
  double measure(String text, TextStyle style) => text.runes.length * 10.0;

  /// 固定字母基线。
  @override
  double baseline(TextStyle style) => 8;

  /// 无本地资源。
  @override
  void dispose() {}
}

/// 验证文字行的全部回退、换行回调和基线坐标。
void main() {
  group('layoutLuckyTextLines', () {
    test('resolves overrides without using active font size as line height',
        () {
      final measurer = _Measurer();
      addTearDown(measurer.dispose);
      expect(measurer.baseline(const TextStyle()), 8);
      final lines = layoutLuckyTextLines(
          text: const LuckyText('a\nb',
              fontSize: 18.8,
              top: LuckyLength.percent(10),
              left: LuckyLength.percent(20)),
          defaults: const LuckyTextDefaults(),
          override: const LuckyTextOverride(
              fontSize: 30.9,
              color: Color(0xFFFF0000),
              fontFamily: 'Roboto',
              fontFamilyFallback: ['serif'],
              fontWeight: FontWeight.w700),
          measurer: measurer,
          box: const Rect.fromLTWH(10, 20, 100, 200),
          leftBase: 50,
          topBase: 200,
          maxWidthOf: (_, __) => 100,
          wrap: false);
      expect(lines.map((line) => line.text), ['a', 'b']);
      expect(lines.first.x, 65);
      expect(lines.first.baselineY, 20 + 20 + 18.8);
      expect(lines.last.baselineY, 20 + 20 + 2 * 18.8);
      expect(lines.first.style.fontSize, 30);
      expect(lines.first.style.height, isNull);
      expect(lines.first.style.color, const Color(0xFFFF0000));
      expect(lines.first.style.fontFamily, 'Roboto');
      expect(lines.first.style.fontFamilyFallback, ['serif']);
      expect(lines.first.style.fontWeight, FontWeight.w700);
    });
    test(
        'wrap callback receives untruncated baseline and empty lines can be dropped',
        () {
      final calls = <(int, double)>[];
      final measurer = _Measurer();
      final wrapped = layoutLuckyTextLines(
          text: const LuckyText('a\nbc', fontSize: 18.8),
          defaults: const LuckyTextDefaults(),
          measurer: measurer,
          box: Rect.zero,
          leftBase: 100,
          topBase: 100,
          maxWidthOf: (i, y) {
            calls.add((i, y));
            return 10;
          });
      expect(wrapped.map((line) => line.text), ['a', 'b', 'c']);
      expect(calls, [(0, 18.8), (0, 18.8), (1, 37.6)]);
      final dropped = layoutLuckyTextLines(
          text: const LuckyText('\na\n\nb', wordWrap: false),
          defaults: const LuckyTextDefaults(lineHeight: 25),
          measurer: measurer,
          box: Rect.zero,
          leftBase: 100,
          topBase: 100,
          maxWidthOf: (_, __) => throw StateError('不应换行'),
          dropEmptyLines: true);
      expect(dropped.map((line) => line.text), ['a', 'b']);
      expect(dropped.map((line) => line.baselineY), [25, 50]);
      expect(dropped.first.x, -5);
      final activeHeight = layoutLuckyTextLines(
          text: const LuckyText('a', lineHeight: 15),
          defaults: const LuckyTextDefaults(lineHeight: 25),
          override: const LuckyTextOverride(lineHeight: 40),
          measurer: measurer,
          box: Rect.zero,
          leftBase: 100,
          topBase: 100,
          maxWidthOf: (_, __) => 100);
      expect(activeHeight.single.baselineY, 40);
      final defaultsOnly = layoutLuckyTextLines(
          text: const LuckyText('a'),
          defaults: const LuckyTextDefaults(),
          measurer: measurer,
          box: Rect.zero,
          leftBase: 100,
          topBase: 100,
          maxWidthOf: (_, __) => 100);
      expect(defaultsOnly.single.baselineY, 18);
    });
  });
}
