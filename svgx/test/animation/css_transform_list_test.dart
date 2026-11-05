import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/css_transform_list.dart';

/// 模糊测试每类随机输入的数量。
const _fuzzRuns = 2000;

/// 模糊测试单个输入的最大长度。
const _fuzzMaxLength = 120;

/// 模糊测试固定种子，保证每次结果可复现。
const _fuzzSeed = 20261103;

/// 全部模糊测试允许的总耗时。
const _fuzzBudget = Duration(seconds: 5);

/// 数值比较的容许误差。
const _epsilon = 1e-9;

/// 随机字符集：变换函数里常见的字符。
const _fuzzChars = '(),; .+-eE0123456789xyztlsrkwdnpagmuh%\n\t';

/// 随机词片：能拼出接近合法的输入。
const _fuzzPieces = [
  'translate(',
  'translateX(',
  'scale(',
  'rotate(',
  'skew(',
  'skewY(',
  'matrix(',
  'none',
  'px',
  'deg',
  'turn',
  'rad',
  'grad',
  '%',
  ') ',
  '),',
  ',',
  ' ',
  '0',
  '.5',
  '-1e2',
  '(',
  ')',
];

/// 变异用的合法样例。
const _fuzzSeeds = [
  'translate(50px,50px) rotate(90deg) translate(-50px,-50px)',
  'scale(0.5) skewX(1deg)skewY(2rad)',
  'translateY(1px) matrix(1,0,0,1,5,6) skew(1deg, 2turn)',
  'none',
];

/// 随机输入的总量：纯随机串与合法样例的变异串各 [_fuzzRuns] 个。
///
/// 全部使用固定种子，长度不超过 [_fuzzMaxLength]，每次运行结果相同。
List<String> _fuzzInputs() {
  final random = Random(_fuzzSeed);
  final result = <String>[];

  /// 随机取一个字符或词片。
  String piece() => random.nextBool()
      ? _fuzzPieces[random.nextInt(_fuzzPieces.length)]
      : _fuzzChars[random.nextInt(_fuzzChars.length)];
  for (var n = 0; n < _fuzzRuns; n++) {
    final target = random.nextInt(_fuzzMaxLength + 1);
    final buffer = StringBuffer();
    while (buffer.length < target) {
      buffer.write(piece());
    }
    result.add(buffer.toString());
  }
  for (var n = 0; n < _fuzzRuns; n++) {
    var text = _fuzzSeeds[random.nextInt(_fuzzSeeds.length)];
    // 删除、插入或替换一到三处。
    for (var k = random.nextInt(3); k >= 0 && text.isNotEmpty; k--) {
      final at = random.nextInt(text.length);
      final op = random.nextInt(3);
      text =
          text.substring(0, at) +
          (op == 0 ? '' : piece()) +
          text.substring(op == 1 ? at : at + 1);
    }
    result.add(text);
  }
  return [
    for (final text in result)
      text.length > _fuzzMaxLength ? text.substring(0, _fuzzMaxLength) : text,
  ];
}

/// 用矩阵 [m]（SVG 顺序）变换点 ([x], [y])。
List<double> _apply(List<double> m, double x, double y) => [
  m[0] * x + m[2] * y + m[4],
  m[1] * x + m[3] * y + m[5],
];

/// 解析 [text]，要求成功，返回操作列表。
List<CssTransformOp> _parse(String text) {
  final ops = parseCssTransformList(text);
  expect(ops, isNotNull, reason: text);
  return ops!;
}

/// 断言 [actual] 与 [expected] 逐项相差不超过 [_epsilon]。
void _expectClose(List<double> actual, List<double> expected) {
  expect(actual.length, expected.length);
  for (var i = 0; i < expected.length; i++) {
    expect(actual[i], closeTo(expected[i], _epsilon), reason: '第 $i 项');
  }
}

/// 构造平移操作。
CssTransformOp _translate(double x, double y) =>
    CssTransformOp(CssTransformKind.translate, [x, y]);

/// 构造缩放操作。
CssTransformOp _scale(double x, double y) =>
    CssTransformOp(CssTransformKind.scale, [x, y]);

/// 构造单角度操作。
CssTransformOp _angleOp(CssTransformKind kind, double degrees) =>
    CssTransformOp(kind, [degrees]);

/// 执行变换列表解析与矩阵连乘的单元测试。
void main() {
  group('CssTransformOp', () {
    test('相等、散列与文本', () {
      expect(_translate(1, 2), _translate(1, 2));
      expect(_translate(1, 2).hashCode, _translate(1, 2).hashCode);
      expect(_translate(1, 2), isNot(_translate(1, 3)));
      expect(_translate(1, 2), isNot(_scale(1, 2)));
      expect(
        const CssTransformOp(CssTransformKind.rotate, [1]),
        isNot(const CssTransformOp(CssTransformKind.rotate, [1, 0])),
      );
      expect(_translate(1, 2).toString(), 'translate(1.0, 2.0)');
      expect(_angleOp(CssTransformKind.skewX, 5).toString(), 'skewX(5.0)');
    });
  });

  group('parseCssTransformList 各函数', () {
    test('translate 及 translateX/Y', () {
      expect(_parse('translate(10px, 20px)'), [_translate(10, 20)]);
      expect(_parse('translate(10px)'), [_translate(10, 0)]);
      expect(_parse('translate(0)'), [_translate(0, 0)]);
      expect(_parse('translate(-0, 0px)'), [_translate(0, 0)]);
      expect(_parse('translate(0, 5px)'), [_translate(0, 5)]);
      expect(_parse('translateX(5px)'), [_translate(5, 0)]);
      expect(_parse('translateY(5px)'), [_translate(0, 5)]);
      expect(_parse('translateX(0)'), [_translate(0, 0)]);
    });

    test('scale 及 scaleX/Y', () {
      expect(_parse('scale(2)'), [_scale(2, 2)]);
      expect(_parse('scale(2, 3)'), [_scale(2, 3)]);
      expect(_parse('scale(-1.5, .5)'), [_scale(-1.5, 0.5)]);
      expect(_parse('scale(0,0)'), [_scale(0, 0)]);
      expect(_parse('scale(+3)'), [_scale(3, 3)]);
      expect(_parse('scale(1e1)'), [_scale(10, 10)]);
      expect(_parse('scaleX(2)'), [_scale(2, 1)]);
      expect(_parse('scaleY(3)'), [_scale(1, 3)]);
    });

    test('rotate、rotateZ 与角度单位', () {
      const rotate = CssTransformKind.rotate;
      expect(_parse('rotate(45deg)'), [_angleOp(rotate, 45)]);
      expect(_parse('rotate(0)'), [_angleOp(rotate, 0)]);
      expect(_parse('rotate(0deg)'), [_angleOp(rotate, 0)]);
      expect(_parse('rotate(-60.491761deg)'), [_angleOp(rotate, -60.491761)]);
      expect(_parse('rotateZ(10deg)'), [_angleOp(rotate, 10)]);
      expect(_parse('rotate(.25turn)'), [_angleOp(rotate, 90)]);
      expect(_parse('rotate(0.25turn)'), [_angleOp(rotate, 90)]);
      expect(_parse('rotate(1turn)'), [_angleOp(rotate, 360)]);
      expect(_parse('rotate(+.5turn)'), [_angleOp(rotate, 180)]);
      expect(_parse('rotate(100grad)'), [_angleOp(rotate, 90)]);
      expect(_parse('rotate(200grad)'), [_angleOp(rotate, 180)]);
      expect(_parse('rotate(400grad)'), [_angleOp(rotate, 360)]);
      expect(
        _parse('rotate(3.14159265358979rad)').single.args.single,
        closeTo(180, _epsilon),
      );
      expect(
        _parse('rotate(${pi}rad)').single.args.single,
        closeTo(180, _epsilon),
      );
      expect(
        _parse('rotate(1rad)').single.args.single,
        closeTo(180 / pi, _epsilon),
      );
    });

    test('skewX、skewY', () {
      expect(_parse('skewX(10deg)'), [_angleOp(CssTransformKind.skewX, 10)]);
      expect(_parse('skewY(-5deg)'), [_angleOp(CssTransformKind.skewY, -5)]);
      expect(_parse('skewX(0)'), [_angleOp(CssTransformKind.skewX, 0)]);
      expect(_parse('skewY(.5turn)'), [_angleOp(CssTransformKind.skewY, 180)]);
    });

    test('skew 归一成矩阵', () {
      final one = _parse('skew(10deg)').single;
      expect(one.kind, CssTransformKind.matrix);
      _expectClose(one.args, [1, 0, tan(10 * pi / 180), 1, 0, 0]);
      final two = _parse('skew(10deg, 20deg)').single;
      expect(two.kind, CssTransformKind.matrix);
      _expectClose(two.args, [
        1,
        tan(20 * pi / 180),
        tan(10 * pi / 180),
        1,
        0,
        0,
      ]);
      _expectClose(_parse('skew(45deg, -45deg)').single.args, [
        1,
        -1,
        1,
        1,
        0,
        0,
      ]);
      _expectClose(_parse('skew(0)').single.args, [1, 0, 0, 1, 0, 0]);
    });

    test('matrix', () {
      expect(_parse('matrix(1,2,3,4,5,6)'), [
        const CssTransformOp(CssTransformKind.matrix, [1, 2, 3, 4, 5, 6]),
      ]);
      expect(_parse('matrix(1, 0, 0, 1, 0.5, -0.5)'), [
        const CssTransformOp(CssTransformKind.matrix, [1, 0, 0, 1, 0.5, -0.5]),
      ]);
    });

    test('none 得到空列表', () {
      expect(_parse('none'), isEmpty);
      expect(_parse('NONE'), isEmpty);
      expect(_parse('  none \n'), isEmpty);
    });
  });

  group('parseCssTransformList 写法', () {
    test('函数名不区分大小写', () {
      expect(_parse('TranslateX(1PX)'), [_translate(1, 0)]);
      expect(_parse('sCaLe(2)'), [_scale(2, 2)]);
      expect(_parse('ROTATE(10DEG)'), [_angleOp(CssTransformKind.rotate, 10)]);
      expect(_parse('ROTATEZ(1Turn)'), [
        _angleOp(CssTransformKind.rotate, 360),
      ]);
    });

    test('函数之间可无空白', () {
      expect(_parse('translate(1px)rotate(1deg)'), [
        _translate(1, 0),
        _angleOp(CssTransformKind.rotate, 1),
      ]);
      expect(_parse('translate(1px,2px)scale(2)rotate(0)'), [
        _translate(1, 2),
        _scale(2, 2),
        _angleOp(CssTransformKind.rotate, 0),
      ]);
    });

    test('任意空白与换行', () {
      expect(_parse('  translate( 1px ,\n 2px )   rotate( 1deg )\n\t'), [
        _translate(1, 2),
        _angleOp(CssTransformKind.rotate, 1),
      ]);
    });

    test('数字写法', () {
      expect(_parse('translate(+1px, .5px)'), [_translate(1, 0.5)]);
      expect(_parse('translate(1e2px, -1.5e-1px)'), [_translate(100, -0.15)]);
      expect(_parse('translate(1E1PX)'), [_translate(10, 0)]);
    });

    test('同类函数可重复出现', () {
      expect(_parse('translate(1px,1px) translate(2px,2px)'), [
        _translate(1, 1),
        _translate(2, 2),
      ]);
    });

    test('真实样本写法', () {
      expect(
        _parse('translate(295.100006px,872.539978px) scale(0.733169,0.733169)'),
        [_translate(295.100006, 872.539978), _scale(0.733169, 0.733169)],
      );
      expect(_parse('translate(61.480105px,64.034448px) rotate(0deg)'), [
        _translate(61.480105, 64.034448),
        _angleOp(CssTransformKind.rotate, 0),
      ]);
      expect(_parse('scale(1,1)'), [_scale(1, 1)]);
    });
  });

  group('parseCssTransformList 非法写法整体作废', () {
    test('百分比、其他单位与无单位非零数', () {
      const bad = [
        'translate(10%, 0)',
        'translate(0, 10%)',
        'translateX(50%)',
        'translate(1em)',
        'translate(1vh)',
        'translate(1pt)',
        'translate(1rem)',
        'translate(1)',
        'translate(1px, 2)',
        'translate(1.px)',
        'translate(--1px)',
        'translate(NaNpx)',
        'rotate(45)',
        'rotate(10px)',
        'rotate(1s)',
        'rotate(10%)',
        'skewX(5)',
        'skew(1deg, 2)',
        'scale(1px)',
        'scale(50%)',
        'scaleX(1deg)',
        'matrix(1,2,3,4,5,6px)',
        'matrix(1,2,3,4,5,0x6)',
        'rotate(1e999deg)',
        'rotate(1e308turn)',
        'translate(1e999px)',
      ];
      for (final text in bad) {
        expect(parseCssTransformList(text), isNull, reason: text);
      }
    });

    test('三维函数、var() 与 calc()', () {
      const bad = [
        'translate3d(1px,2px,3px)',
        'translateZ(1px)',
        'rotateX(1deg)',
        'rotateY(1deg)',
        'rotate3d(1,1,1,1deg)',
        'scale3d(1,1,1)',
        'scaleZ(2)',
        'perspective(100px)',
        'matrix3d(1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1)',
        'var(--x)',
        'translate(var(--x), 0)',
        'translate(calc(1px + 2px), 0)',
        'calc(1px)',
        'rotate(calc(1deg))',
        'translate(1px) var(--x)',
      ];
      for (final text in bad) {
        expect(parseCssTransformList(text), isNull, reason: text);
      }
    });

    test('参数个数与逗号错误', () {
      const bad = [
        'translate()',
        'translate(,)',
        'translate(1px,)',
        'translate(,1px)',
        'translate(1px,,2px)',
        'translate(1px,2px,3px)',
        'translateX(1px,2px)',
        'translateX()',
        'scale(1,2,3)',
        'scale()',
        'rotate()',
        'rotate(1deg,2deg)',
        'rotate(1deg 2deg)',
        'translate(1px 2px)',
        'skew(1deg,2deg,3deg)',
        'matrix(1,2,3)',
        'matrix(1,2,3,4,5,6,7)',
        'matrix()',
      ];
      for (final text in bad) {
        expect(parseCssTransformList(text), isNull, reason: text);
      }
    });

    test('结构错误、未知函数与乱码', () {
      const bad = [
        '',
        '   ',
        'translate(1px',
        'translate 1px)',
        'translate (1px)',
        'translate(1px) rotate(',
        'translate(1px))',
        'translate(1px), rotate(1deg)',
        'translate(1px);',
        'translate(1px) foo',
        'translate(1px) none',
        'none none',
        'none translate(1px)',
        'foo(1px)',
        'garbage',
        '(((',
        ')))',
        ',',
        '((',
        'a((',
        '\u0000',
        'inherit',
        'initial',
        'unset',
        'translate(1px)rotate',
        'rotate(1deg)é(1)',
      ];
      for (final text in bad) {
        expect(parseCssTransformList(text), isNull, reason: text);
      }
    });
  });

  group('cssTransformMatrix', () {
    test('空列表为单位矩阵', () {
      expect(cssTransformMatrix(const []), [1, 0, 0, 1, 0, 0]);
      expect(cssTransformMatrix(_parse('none')), [1, 0, 0, 1, 0, 0]);
    });

    test('单个函数', () {
      expect(cssTransformMatrix(_parse('translate(5px, 6px)')), [
        1,
        0,
        0,
        1,
        5,
        6,
      ]);
      expect(cssTransformMatrix(_parse('scale(2, 3)')), [2, 0, 0, 3, 0, 0]);
      _expectClose(cssTransformMatrix(_parse('rotate(90deg)')), [
        0,
        1,
        -1,
        0,
        0,
        0,
      ]);
      _expectClose(cssTransformMatrix(_parse('rotate(.5turn)')), [
        -1,
        0,
        0,
        -1,
        0,
        0,
      ]);
      _expectClose(cssTransformMatrix(_parse('skewX(45deg)')), [
        1,
        0,
        1,
        1,
        0,
        0,
      ]);
      _expectClose(cssTransformMatrix(_parse('skewY(45deg)')), [
        1,
        1,
        0,
        1,
        0,
        0,
      ]);
      expect(cssTransformMatrix(_parse('matrix(1,2,3,4,5,6)')), [
        1,
        2,
        3,
        4,
        5,
        6,
      ]);
    });

    test('连乘顺序：先写的在左', () {
      // 点先被右侧的缩放作用，再被左侧的平移作用。
      final a = cssTransformMatrix(_parse('translate(10px, 0) scale(2)'));
      expect(a, [2, 0, 0, 2, 10, 0]);
      expect(_apply(a, 1, 0), [12, 0]);
      final b = cssTransformMatrix(_parse('scale(2) translate(10px, 0)'));
      expect(b, [2, 0, 0, 2, 20, 0]);
      expect(_apply(b, 1, 0), [22, 0]);
    });

    test('绕中心点旋转', () {
      final m = cssTransformMatrix(
        _parse('translate(50px,50px) rotate(90deg) translate(-50px,-50px)'),
      );
      _expectClose(_apply(m, 50, 50), [50, 50]);
      _expectClose(_apply(m, 100, 50), [50, 100]);
      _expectClose(_apply(m, 50, 0), [100, 50]);
    });

    test('三函数混合', () {
      final m = cssTransformMatrix(
        _parse('translate(10px,20px) rotate(90deg) scale(2)'),
      );
      _expectClose(_apply(m, 1, 0), [10, 22]);
      _expectClose(_apply(m, 0, 1), [8, 20]);
    });

    test('skew 矩阵作用于点', () {
      final m = cssTransformMatrix(_parse('skew(45deg, 0)'));
      _expectClose(_apply(m, 0, 1), [1, 1]);
      final n = cssTransformMatrix(_parse('skew(0, 45deg)'));
      _expectClose(_apply(n, 1, 0), [1, 1]);
    });

    test('与逐步手算一致，且结果写回 matrix() 后不变', () {
      final m = cssTransformMatrix(
        _parse('translate(3px,4px) scale(2,3) rotate(30deg)'),
      );
      // 点 (1, 0) 依次经过旋转、缩放、平移。
      final r = 30 * pi / 180;
      _expectClose(_apply(m, 1, 0), [2 * cos(r) + 3, 3 * sin(r) + 4]);
      _expectClose(cssTransformMatrix(_parse('matrix(${m.join(',')})')), m);
    });
  });

  group('往返属性测试', () {
    test('随机生成的合法写法能还原为预期操作', () {
      final random = Random(_fuzzSeed);
      const commas = [',', ', ', ' ,', ' , ', ',\n'];
      const gaps = ['', ' ', '  ', '\n', '\t '];
      const pads = ['', ' ', '  '];

      /// 取一个随机整数，范围为负一百到一百。
      int number() => random.nextInt(201) - 100;

      /// 返回随机的函数内边距。
      String pad() => pads[random.nextInt(pads.length)];

      /// 用随机逗号和边距拼接 [args]。
      String args(List<String> items) =>
          '${pad()}${items.join(commas[random.nextInt(commas.length)])}${pad()}';

      for (var n = 0; n < 500; n++) {
        final text = StringBuffer();
        final expected = <CssTransformOp>[];
        final count = 1 + random.nextInt(4);
        for (var i = 0; i < count; i++) {
          if (i > 0) text.write(gaps[random.nextInt(gaps.length)]);
          final x = number(), y = number();
          switch (random.nextInt(7)) {
            case 0:
              text.write('translate(${args(['${x}px', '${y}px'])})');
              expected.add(_translate(x.toDouble(), y.toDouble()));
            case 1:
              text.write('translateY(${args(['${y}px'])})');
              expected.add(_translate(0, y.toDouble()));
            case 2:
              text.write('scale(${args(['$x', '$y'])})');
              expected.add(_scale(x.toDouble(), y.toDouble()));
            case 3:
              text.write('scaleX(${args(['$x'])})');
              expected.add(_scale(x.toDouble(), 1));
            case 4:
              text.write('rotate(${args(['${x}deg'])})');
              expected.add(_angleOp(CssTransformKind.rotate, x.toDouble()));
            case 5:
              text.write('skewY(${args(['${x}turn'])})');
              expected.add(_angleOp(CssTransformKind.skewY, x * 360.0));
            default:
              text.write(
                'matrix(${args(['$x', '$y', '$x', '$y', '$x', '$y'])})',
              );
              expected.add(
                CssTransformOp(
                  CssTransformKind.matrix,
                  [x, y, x, y, x, y].map((e) => e.toDouble()).toList(),
                ),
              );
          }
        }
        expect(
          parseCssTransformList(text.toString()),
          expected,
          reason: text.toString(),
        );
      }
    });
  });

  group('容错', () {
    const sample =
        'translate(50px,50px) rotate(90deg) translate(-50px,-50px) '
        'skew(1deg, .5turn) matrix(1,0,0,1,0,0) scale(2)';

    test('逐个前缀不抛异常', () {
      for (var i = 0; i <= sample.length; i++) {
        expect(
          () => parseCssTransformList(sample.substring(0, i)),
          returnsNormally,
          reason: '前缀 $i',
        );
      }
    });

    test('随机输入不抛异常且快速返回', () {
      final watch = Stopwatch()..start();
      var parsed = 0;
      for (final input in _fuzzInputs()) {
        final ops = parseCssTransformList(input);
        if (ops == null) continue;
        parsed++;
        // 非空结果须能连乘，且参数个数符合约定。
        expect(cssTransformMatrix(ops), hasLength(6));
        for (final op in ops) {
          expect(op.args.every((e) => e.isFinite), isTrue, reason: input);
        }
      }
      expect(parsed, greaterThan(0));
      expect(watch.elapsed, lessThan(_fuzzBudget));
    });

    test('超长输入保持线性耗时', () {
      final watch = Stopwatch()..start();
      expect(parseCssTransformList('(' * 100000), isNull);
      expect(parseCssTransformList('a(' * 50000), isNull);
      expect(parseCssTransformList('a(1)' * 50000), isNull);
      expect(parseCssTransformList('translate(' * 20000), isNull);
      expect(parseCssTransformList('translate(1px,${'1,' * 50000})'), isNull);
      expect(parseCssTransformList('translate(1px)' * 20000), hasLength(20000));
      expect(parseCssTransformList('rotate(${'1' * 50000}deg)'), isNull);
      expect(watch.elapsed, lessThan(_fuzzBudget));
    });
  });
}
