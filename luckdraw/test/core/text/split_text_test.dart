import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';

/// 每码点固定十像素，避免字体环境影响算法。
double _measure(String text) => text.runes.length * 10.0;

/// 验证换行算法逐字行为。
void main() {
  group('splitLuckyText', () {
    test('returns the whole text as one line when it fits', () {
      expect(splitLuckyText('abc', _measure, (_) => 30), ['abc']);
    });
    test('breaks lines exactly when measured width exceeds max width', () {
      expect(splitLuckyText('abcde', _measure, (_) => 20), ['ab', 'cd', 'e']);
    });
    test('maxWidthOf receives the number of finished lines', () {
      final calls = <int>[];
      expect(
          splitLuckyText('abcde', _measure, (i) {
            calls.add(i);
            return i == 0 ? 20 : 10;
          }),
          ['ab', 'c', 'd', 'e']);
      expect(calls, [0, 0, 0, 1, 2]);
    });
    test('lineClamp appends ellipsis and counts its width on the last line',
        () {
      expect(splitLuckyText('abcdef', _measure, (_) => 50, lineClamp: 1),
          ['ab...']);
      expect(splitLuckyText('abcdefghijk', _measure, (_) => 50, lineClamp: 2),
          ['abcde', 'fg...']);
    });
    test('lineClamp of zero or negative means unlimited', () {
      expect(splitLuckyText('abc', _measure, (_) => 10, lineClamp: 0),
          ['a', 'b', 'c']);
      expect(splitLuckyText('abc', _measure, (_) => 10, lineClamp: -1),
          ['a', 'b', 'c']);
    });
    test('negative max width returns the lines collected so far', () {
      expect(splitLuckyText('abc', _measure, (_) => -1), isEmpty);
      expect(splitLuckyText('abcd', _measure, (i) => i == 0 ? 10 : -1), ['a']);
    });
    test('empty text yields a single empty line', () {
      expect(splitLuckyText('', _measure, (_) => 10), ['']);
    });
    test(
        'a first character wider than max width produces a leading empty line like upstream',
        () {
      expect(splitLuckyText('a', _measure, (_) => 5), ['', 'a']);
    });
    test('iterates by code point so surrogate pairs are never split (IMP-06)',
        () {
      expect(splitLuckyText('a😀b', _measure, (_) => 10), ['a', '😀', 'b']);
    });
    test('removeLineBreaks strips only newline characters', () {
      expect(removeLineBreaks('a\r\nb\nc'), 'a\rbc');
    });
  });
}
