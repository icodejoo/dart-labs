// Regression tests for the 2026-08-26 Dart-side perf round: `parseSvgHexColor`
// switched from `substring` + `int.parse` to direct `codeUnitAt` digit reads,
// `stroke-dasharray` parsing became memoized and regex-free, and `dashPath`
// stopped materializing its union path until a second dash needs appending.
// All three are pure rewrites, so what needs pinning is that the values did
// not move.
//
// 2026-08-26 Dart 侧性能轮次的回归测试：`parseSvgHexColor` 从
// `substring` + `int.parse` 改成直接用 `codeUnitAt` 逐位取值，
// `stroke-dasharray` 解析改为带记忆且不用正则，`dashPath` 则推迟到真的需要追加
// 第二段虚线时才创建并集路径。三者都是纯重写，要钉住的正是"结果没变"。

import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/svg_path_data.dart';
import 'package:svgx/src/animation/svg_style.dart';
import 'package:svgx/src/animation/svg_theme.dart';

void main() {
  group('parseSvgHexColor', () {
    test('expands #RGB by duplicating each nibble', () {
      expect(parseSvgHexColor('#f30'), const Color(0xFFFF3300));
      expect(parseSvgHexColor('#ABC'), const Color(0xFFAABBCC));
    });

    test('reads #RRGGBB as opaque', () {
      expect(parseSvgHexColor('#FF7A00'), const Color(0xFFFF7A00));
      expect(parseSvgHexColor('#000000'), const Color(0xFF000000));
    });

    test('reads #RRGGBBAA with the alpha last', () {
      expect(parseSvgHexColor('#11223380'), const Color(0x80112233));
    });

    test('is case insensitive', () {
      expect(parseSvgHexColor('#aabbcc'), parseSvgHexColor('#AABBCC'));
    });

    test('returns null for non-hex and wrong-length values', () {
      expect(parseSvgHexColor(''), isNull);
      expect(parseSvgHexColor('red'), isNull);
      expect(parseSvgHexColor('#12345'), isNull);
      // Invalid digits now yield null instead of throwing — same answer this
      // function already gave for a wrong-length value.
      // 非法数字现在返回 null 而不是抛异常——与它本就对长度不合法的值给出的
      // 答案一致。
      expect(parseSvgHexColor('#ZZZZZZ'), isNull);
    });
  });

  group('ResolvedStyle.inherit stroke-dasharray', () {
    const theme = SvgxTheme();

    test('splits on whitespace and commas alike', () {
      expect(
        ResolvedStyle.initial.inherit({
          'stroke-dasharray': '4 2',
        }, theme).strokeDasharray,
        <double>[4, 2],
      );
      expect(
        ResolvedStyle.initial.inherit({
          'stroke-dasharray': ' 4 , 2,6 ',
        }, theme).strokeDasharray,
        <double>[4, 2, 6],
      );
    });

    test('treats none/blank as a solid stroke', () {
      expect(
        ResolvedStyle.initial.inherit({
          'stroke-dasharray': 'none',
        }, theme).strokeDasharray,
        isEmpty,
      );
      expect(
        ResolvedStyle.initial.inherit({
          'stroke-dasharray': '  ',
        }, theme).strokeDasharray,
        isEmpty,
      );
    });

    test('memoized results are equal across repeated resolves', () {
      // Same string parsed twice must give the same dashes — the memo is keyed
      // on the raw attribute value.
      // 同一个字符串解析两次必须得到相同的虚线段——记忆表就是按原始属性值索引的。
      final first = ResolvedStyle.initial.inherit({
        'stroke-dasharray': '9 3',
      }, theme).strokeDasharray;
      final second = ResolvedStyle.initial.inherit({
        'stroke-dasharray': '9 3',
      }, theme).strokeDasharray;
      expect(second, first);
    });

    test('a value that is not a number degrades to zero, not a throw', () {
      expect(
        ResolvedStyle.initial.inherit({
          'stroke-dasharray': '4 oops',
        }, theme).strokeDasharray,
        <double>[4, 0],
      );
    });
  });

  group('dashPath', () {
    // A 100-unit horizontal line: contour length is exactly known, so the
    // dashes a pattern must produce are arithmetic rather than guesswork.
    // 一条 100 单位的水平线：轮廓长度完全已知，因此某个图案应当产出哪些虚线段
    // 是算出来的，不是猜的。
    ui.Path line() => ui.Path()
      ..moveTo(0, 0)
      ..lineTo(100, 0);

    test('a pattern longer than the contour leaves it fully drawn', () {
      final dashed = dashPath(line(), dashArray: const [200, 200]);
      expect(dashed.getBounds().width, closeTo(100, 0.001));
    });

    test('a dense pattern emits several dashes and keeps the bounds', () {
      final dashed = dashPath(line(), dashArray: const [10, 10]);
      final bounds = dashed.getBounds();
      expect(bounds.left, closeTo(0, 0.001));
      expect(bounds.right, closeTo(90, 0.5));
    });

    test('an odd-length array behaves like the doubled pattern', () {
      final odd = dashPath(line(), dashArray: const [10]).getBounds();
      final doubled = dashPath(
        line(),
        dashArray: const [10, 10, 10, 10],
      ).getBounds();
      expect(odd.left, closeTo(doubled.left, 0.001));
      expect(odd.right, closeTo(doubled.right, 0.001));
    });

    test('dashOffset shifts the on/off phase along the contour', () {
      // [50, 50] over a 100-unit contour: at offset 0 the first half is drawn,
      // at offset 50 the phase has moved on by one segment and the second half
      // is drawn instead.
      // [50, 50] 作用在 100 单位的轮廓上：偏移 0 时画前一半，偏移 50 时相位前移
      // 了一段，改为画后一半。
      final atZero = dashPath(line(), dashArray: const [50, 50]).getBounds();
      expect(atZero.left, closeTo(0, 0.5));
      expect(atZero.right, closeTo(50, 0.5));

      final atHalf = dashPath(
        line(),
        dashArray: const [50, 50],
        dashOffset: 50,
      ).getBounds();
      expect(atHalf.left, closeTo(50, 0.5));
      expect(atHalf.right, closeTo(100, 0.5));
    });

    test('an all-zero pattern returns the source untouched', () {
      final source = line();
      expect(
        identical(dashPath(source, dashArray: const [0, 0]), source),
        true,
      );
    });
  });
}
