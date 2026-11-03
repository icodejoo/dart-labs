// 路径词法器：圆弧标志位的紧凑写法（`A10 10 0 0110 10`）与畸形记号的容错。
// 这两类输入在压缩过的真实 SVG 里很常见，此前会让绘制抛 String->double 转换异常。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/svg_path_data.dart';
import 'package:svgx/src/animation/svg_path_morph.dart';

void main() {
  group('圆弧标志位', () {
    test('标志位紧贴终点 x：A10 10 0 0110 10', () {
      expect(tokenizeSvgPathData('M0 0A10 10 0 0110 10Z'), [
        'M', 0.0, 0.0, //
        'A', 10.0, 10.0, 0.0, 0.0, 1.0, 10.0, 10.0,
        'Z',
      ]);
    });

    test('两个标志位紧挨：A5 5 0 11 5 5', () {
      expect(tokenizeSvgPathData('A5 5 0 11 5 5'), [
        'A',
        5.0,
        5.0,
        0.0,
        1.0,
        1.0,
        5.0,
        5.0,
      ]);
    });

    test('标志位后紧跟负数与小数：a2 2 0 01-2 2、A5 5 0 01.5.5', () {
      expect(tokenizeSvgPathData('a2 2 0 01-2 2'), [
        'a',
        2.0,
        2.0,
        0.0,
        0.0,
        1.0,
        -2.0,
        2.0,
      ]);
      expect(tokenizeSvgPathData('A5 5 0 01.5.5'), [
        'A',
        5.0,
        5.0,
        0.0,
        0.0,
        1.0,
        0.5,
        0.5,
      ]);
    });

    test('带分隔符的标准写法不受影响', () {
      expect(tokenizeSvgPathData('A5,5,0,1,0,10,10'), [
        'A',
        5.0,
        5.0,
        0.0,
        1.0,
        0.0,
        10.0,
        10.0,
      ]);
    });

    test('隐式重复的第二组圆弧参数同样按位置识别标志位', () {
      expect(tokenizeSvgPathData('A5 5 0 1010 10 5 5 0 0120 20'), [
        'A', 5.0, 5.0, 0.0, 1.0, 0.0, 10.0, 10.0, //
        5.0, 5.0, 0.0, 0.0, 1.0, 20.0, 20.0,
      ]);
    });

    test('非圆弧命令后的 0/1 仍是普通数值，换命令后重新计数', () {
      expect(tokenizeSvgPathData('M0 0L1 1'), ['M', 0.0, 0.0, 'L', 1.0, 1.0]);
      expect(tokenizeSvgPathData('A1 1 0 0 1 1 1M0 1'), [
        'A',
        1.0,
        1.0,
        0.0,
        0.0,
        1.0,
        1.0,
        1.0,
        'M',
        0.0,
        1.0,
      ]);
    });

    test('紧凑写法与带空格写法画出完全相同的几何', () {
      const pairs = <(String, String)>[
        // Material 风格圆：a10 10 0 100 20 = rx ry rot 1 0 x=0 y=20
        (
          'M12 2a10 10 0 100 20 10 10 0 000-20z',
          'M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0 -20z',
        ),
        ('M0 0A10 10 0 0110 10Z', 'M0 0A10 10 0 0 1 10 10Z'),
        (
          'M5 5a3 3 0 11-6 0 3 3 0 016 0z',
          'M5 5a3 3 0 1 1 -6 0 3 3 0 0 1 6 0z',
        ),
        ('M1 1a2 2 0 01.5.5', 'M1 1a2 2 0 0 1 .5 .5'),
      ];
      for (final (compact, spaced) in pairs) {
        final a = parseSvgPathData(compact);
        final b = parseSvgPathData(spaced);
        expect(a.getBounds(), b.getBounds(), reason: compact);
        expect(a.computeMetrics().length, b.computeMetrics().length);
      }
    });

    test('路径变形的规范化也能吃紧凑写法', () {
      final compact = buildPathMorphData([
        'M0 0A10 10 0 0110 10Z',
        'M0 0A10 10 0 0120 20Z',
      ]);
      final spaced = buildPathMorphData([
        'M0 0A10 10 0 0 1 10 10Z',
        'M0 0A10 10 0 0 1 20 20Z',
      ]);
      expect(compact, isNotNull);
      expect(compact!.ops, spaced!.ops);
      expect(compact.frames[0], spaced.frames[0]);
      expect(compact.frames[1], spaced.frames[1]);
    });
  });

  group('畸形记号容错', () {
    test('孤立的符号、残缺的指数、孤立的小数点被丢弃而不抛异常', () {
      for (final d in ['M0 0L-', 'M1e L2 2', 'M. 5', 'M--5 5', 'M0 0e', 'L+']) {
        expect(() => tokenizeSvgPathData(d), returnsNormally, reason: d);
        expect(() => parseSvgPathData(d), returnsNormally, reason: d);
      }
      expect(tokenizeSvgPathData('M0 0L-'), ['M', 0.0, 0.0, 'L']);
      expect(tokenizeSvgPathData('M1e L2 2'), ['M', 'L', 2.0, 2.0]);
    });

    test('固定种子随机输入：词法与几何构建都不抛异常', () {
      const alphabet = 'MmLlHhVvCcSsQqTtAaZz0123456789.,- +eE';
      final random = Random(20261103);
      final watch = Stopwatch()..start();
      for (var n = 0; n < 4000; n++) {
        final text = String.fromCharCodes(
          List.generate(
            random.nextInt(80),
            (_) => alphabet.codeUnitAt(random.nextInt(alphabet.length)),
          ),
        );
        expect(() => tokenizeSvgPathData(text), returnsNormally, reason: text);
        expect(() => parseSvgPathData(text), returnsNormally, reason: text);
        expect(
          () => buildPathMorphData([text, text]),
          returnsNormally,
          reason: text,
        );
      }
      expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
    });
  });
}
