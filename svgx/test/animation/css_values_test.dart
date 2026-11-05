import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/css_values.dart';

/// 模糊测试每类随机输入的数量。
const _fuzzRuns = 2000;

/// 模糊测试单个输入的最大长度。
const _fuzzMaxLength = 120;

/// 模糊测试固定种子，保证每次结果可复现。
const _fuzzSeed = 20261103;

/// 全部模糊测试允许的总耗时。
const _fuzzBudget = Duration(seconds: 5);

/// 随机字符集：颜色、长度、百分数及路径函数里常见的字符。
const _fuzzChars = '#()",;\'\\/% .+-eE0123456789abcdefrgbapthnoswdlxMLZ\n\t';

/// 随机词片：能拼出接近合法的输入。
const _fuzzPieces = [
  'rgb(',
  'rgba(',
  'path(',
  'evenodd',
  'nonzero',
  'transparent',
  '#',
  'px',
  '%',
  'e3',
  '"',
  "'",
  '\\',
  ',',
  ' / ',
  '0',
  '255',
  '.5',
  '-',
  ')',
];

/// 变异用的合法样例，覆盖颜色、路径、长度与百分数。
const _fuzzSeeds = [
  '#f80a',
  'rgb(0 128 255 / 50%)',
  'rgba(0, 0, 0, .5)',
  'rgb(10%, 20%, 30%)',
  'path("M0,0 L10,10")',
  r"path(evenodd, 'M0 0 \4d 1')",
  '-1.5e2px',
  '13.348136%',
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

/// 断言 [parse] 对 [sample] 的每个前缀都不抛异常。
void _expectPrefixesSafe(Object? Function(String) parse, String sample) {
  for (var i = 0; i <= sample.length; i++) {
    expect(
      () => parse(sample.substring(0, i)),
      returnsNormally,
      reason: '前缀 $i',
    );
  }
}

/// 断言 [parse] 对全部随机输入不抛异常且总耗时在预算内，返回非空结果供调用方校验。
List<Object> _expectFuzzSafe(Object? Function(String) parse) {
  final watch = Stopwatch()..start();
  final results = <Object>[];
  for (final input in _fuzzInputs()) {
    final value = parse(input);
    if (value != null) results.add(value);
  }
  expect(watch.elapsed, lessThan(_fuzzBudget));
  return results;
}

/// 执行 CSS 值级解析器的单元测试。
void main() {
  group('parseCssDimension / parseCssNumber', () {
    test('数值与单位', () {
      expect(parseCssDimension('-1.5PX'), (value: -1.5, unit: 'px'));
      expect(parseCssDimension('1e2'), (value: 100.0, unit: ''));
      expect(parseCssDimension('1em'), (value: 1.0, unit: 'em'));
      expect(parseCssDimension('1e3em'), (value: 1000.0, unit: 'em'));
      expect(parseCssDimension('.5%'), (value: 0.5, unit: '%'));
      expect(parseCssDimension('+3'), (value: 3.0, unit: ''));
      expect(parseCssDimension(' 7deg '), (value: 7.0, unit: 'deg'));
    });

    test('非法写法', () {
      for (final bad in [
        '',
        'px',
        '1.',
        '1 px',
        '1,5',
        '--1',
        '+-1',
        '1e999',
        'NaN',
        '1px2',
      ]) {
        expect(parseCssDimension(bad), isNull, reason: bad);
      }
    });

    test('纯数值不接受单位', () {
      expect(parseCssNumber('+.5'), 0.5);
      expect(parseCssNumber('-0'), 0);
      expect(parseCssNumber('1e2'), 100);
      expect(parseCssNumber('1px'), isNull);
      expect(parseCssNumber('50%'), isNull);
      expect(parseCssNumber(''), isNull);
    });
  });

  group('parseCssLengthPx', () {
    test('合法写法', () {
      expect(parseCssLengthPx('12px'), 12);
      expect(parseCssLengthPx('12'), 12);
      expect(parseCssLengthPx('0'), 0);
      expect(parseCssLengthPx('-0'), 0);
      expect(parseCssLengthPx('-1.5px'), -1.5);
      expect(parseCssLengthPx('+3'), 3);
      expect(parseCssLengthPx('.5px'), 0.5);
      expect(parseCssLengthPx('1e2px'), 100);
      expect(parseCssLengthPx('1.5E1'), 15);
      expect(parseCssLengthPx('12PX'), 12);
      expect(parseCssLengthPx(' 7px '), 7);
    });

    test('其他单位、百分比与非法写法', () {
      for (final bad in [
        '12em',
        '12%',
        '12pt',
        '12vh',
        '1.',
        'px',
        '',
        '12 px',
        '1,5',
        'abc',
        'calc(1px)',
        '1e999px',
        'Infinity',
      ]) {
        expect(parseCssLengthPx(bad), isNull, reason: bad);
      }
    });
  });

  group('parseCssPercent', () {
    test('合法写法', () {
      expect(parseCssPercent('50%'), 0.5);
      expect(parseCssPercent('12.5%'), 0.125);
      expect(parseCssPercent('0%'), 0);
      expect(parseCssPercent('100%'), 1);
      expect(parseCssPercent('150%'), 1.5);
      expect(parseCssPercent('-20%'), -0.2);
      expect(parseCssPercent(' 50% '), 0.5);
      expect(parseCssPercent('13.348136%'), closeTo(0.13348136, 1e-12));
    });

    test('不是百分数', () {
      for (final bad in [
        '50',
        '50px',
        '%',
        '5 0%',
        '5%%',
        '',
        '1e999%',
        'abc%',
        '1.%',
      ]) {
        expect(parseCssPercent(bad), isNull, reason: bad);
      }
    });
  });

  group('parseCssColor', () {
    test('十六进制', () {
      expect(parseCssColor('#fff'), 0xFFFFFFFF);
      expect(parseCssColor('#f80'), 0xFFFF8800);
      expect(parseCssColor('#F80'), 0xFFFF8800);
      expect(parseCssColor('#f80a'), 0xAAFF8800);
      expect(parseCssColor('#ff8800'), 0xFFFF8800);
      expect(parseCssColor('#FFAA00cc'), 0xCCFFAA00);
      expect(parseCssColor('#00000000'), 0x00000000);
      expect(parseCssColor('#000'), 0xFF000000);
      expect(parseCssColor('  #123456  '), 0xFF123456);
    });

    test('逗号语法', () {
      expect(parseCssColor('rgb(0, 128, 255)'), 0xFF0080FF);
      expect(parseCssColor('rgb(0,128,255)'), 0xFF0080FF);
      expect(parseCssColor('rgb( 0 , 128 , 255 )'), 0xFF0080FF);
      expect(parseCssColor('rgba(0,0,0,.5)'), 0x80000000);
      expect(parseCssColor('rgba(0, 0, 0, 0)'), 0x00000000);
      expect(parseCssColor('rgba(255,255,255,1)'), 0xFFFFFFFF);
      expect(parseCssColor('rgba(0,0,0,50%)'), 0x80000000);
      expect(parseCssColor('rgb(0,0,0,.5)'), 0x80000000);
      expect(parseCssColor('rgba(1,2,3)'), 0xFF010203);
      expect(parseCssColor('rgb(1e2, 0, 0)'), 0xFF640000);
    });

    test('空格语法', () {
      expect(parseCssColor('rgb(0 128 255)'), 0xFF0080FF);
      expect(parseCssColor('rgb(0 128 255 / 50%)'), 0x800080FF);
      expect(parseCssColor('rgb(0 128 255 / .25)'), 0x400080FF);
      expect(parseCssColor('rgb(0 128 255/50%)'), 0x800080FF);
      expect(parseCssColor('rgb(0  128\n255 /50%)'), 0x800080FF);
      expect(parseCssColor('rgba(1 2 3 / 1)'), 0xFF010203);
      expect(parseCssColor('RGB(1 2 3)'), 0xFF010203);
    });

    test('百分数分量', () {
      expect(parseCssColor('rgb(10%, 20%, 30%)'), 0xFF1A334D);
      expect(parseCssColor('rgb(50% 50% 50%)'), 0xFF808080);
      expect(parseCssColor('rgb(100% 0% 0%)'), 0xFFFF0000);
      // 空格语法允许数值与百分数混用。
      expect(parseCssColor('rgb(10% 20 30)'), 0xFF1A141E);
    });

    test('四舍五入与钳制', () {
      expect(parseCssColor('rgb(0.4, 0.5, 254.5)'), 0xFF0001FF);
      expect(parseCssColor('rgb(-10, 300, 255.9)'), 0xFF00FFFF);
      expect(parseCssColor('rgb(-5% 120% 100%)'), 0xFF00FFFF);
      expect(parseCssColor('rgba(0,0,0,2)'), 0xFF000000);
      expect(parseCssColor('rgba(0,0,0,-1)'), 0x00000000);
      expect(parseCssColor('rgb(0 0 0 / 150%)'), 0xFF000000);
      expect(parseCssColor('rgb(0 0 0 / -5%)'), 0x00000000);
    });

    test('transparent 与大小写', () {
      expect(parseCssColor('transparent'), 0);
      expect(parseCssColor(' TRANSPARENT '), 0);
      expect(parseCssColor('RGBA(0, 0, 0, 1)'), 0xFF000000);
      expect(parseCssColor('Rgb(1,2,3)'), 0xFF010203);
    });

    test('不支持或非法的写法返回空', () {
      const bad = [
        '',
        '   ',
        'red',
        'cornflowerblue',
        'currentcolor',
        'currentColor',
        'inherit',
        'none',
        'hsl(0, 0%, 0%)',
        'hsla(0, 0%, 0%, 1)',
        '#',
        '#12',
        '#12345',
        '#1234567',
        '#123456789',
        '#ggg',
        '#12345g',
        'rgb()',
        'rgb(0,0)',
        'rgb(0,0,0,0,0)',
        'rgb(0 0)',
        'rgb(0 0 0 0)',
        'rgb(0, 0 0)',
        'rgb(0 0 0, 0.5)',
        'rgb(0,0,0 / 0.5)',
        'rgb(10%, 20, 30)',
        'rgb(0,0,)',
        'rgb(,0,0)',
        'rgb(0,,0)',
        'rgb(0 0 0 / )',
        'rgb(0 0 0 / 1 / 1)',
        'rgb(0 0 0',
        'rgb 0 0 0)',
        'rgb (0,0,0)',
        'rgb(0,0,0)x',
        'rgb(0px,0,0)',
        'rgb(none 0 0)',
        'rgb(var(--a),0,0)',
        'rgb(calc(1) 2 3)',
        'rgba(0,0,0,.5deg)',
        'rgb(0.0.0)',
        'rgb(1.,2,3)',
        'rgb(1e999,0,0)',
      ];
      for (final text in bad) {
        expect(parseCssColor(text), isNull, reason: text);
      }
    });
  });

  group('parseCssPathFunction', () {
    test('双引号与单引号', () {
      expect(parseCssPathFunction('path("M0 0 L10 10")'), 'M0 0 L10 10');
      expect(parseCssPathFunction("path('M0 0 L10 10')"), 'M0 0 L10 10');
      expect(parseCssPathFunction('PATH("M0,0 L10,10")'), 'M0,0 L10,10');
      expect(parseCssPathFunction('  path(  "M0 0"  )  '), 'M0 0');
      expect(
        parseCssPathFunction("path('M-131.2,889.8C-131.2,519')"),
        'M-131.2,889.8C-131.2,519',
      );
    });

    test('填充规则首参', () {
      expect(parseCssPathFunction('path(evenodd, "M0 0 Z")'), 'M0 0 Z');
      expect(parseCssPathFunction("path(nonzero,'M0 0')"), 'M0 0');
      expect(parseCssPathFunction('path( EvenOdd , "M0 0" )'), 'M0 0');
    });

    test('路径串内的括号、逗号与另一种引号', () {
      expect(parseCssPathFunction('path("a(b)c,d")'), 'a(b)c,d');
      expect(parseCssPathFunction('path("M0,0 )(")'), 'M0,0 )(');
      expect(parseCssPathFunction('path("it\'s")'), "it's");
      expect(parseCssPathFunction("path('say \"hi\"')"), 'say "hi"');
    });

    test('转义解码', () {
      expect(parseCssPathFunction(r'path("M0 \"1")'), 'M0 "1');
      expect(parseCssPathFunction(r'path("a\\b")'), r'a\b');
      expect(parseCssPathFunction(r'path("\4d 0 0")'), 'M0 0');
      expect(parseCssPathFunction(r'path("\00004d0 0")'), 'M0 0');
      expect(parseCssPathFunction(r'path("\4D")'), 'M');
      expect(parseCssPathFunction(r'path("\0")'), '\uFFFD');
      expect(parseCssPathFunction(r'path("\d800")'), '\uFFFD');
      expect(parseCssPathFunction(r'path("\110000")'), '\uFFFD');
      expect(parseCssPathFunction(r'path("\1F600")'), '\u{1F600}');
      expect(parseCssPathFunction('path("\\4d\r\n0 0")'), 'M0 0');
      expect(parseCssPathFunction('path("M0\\\n0")'), 'M00');
      expect(parseCssPathFunction('path("M0\\\r\n0")'), 'M00');
      expect(parseCssPathFunction(r'path("\zM")'), 'zM');
    });

    test('非法写法返回空', () {
      const bad = [
        '',
        'none',
        'path(none)',
        'path()',
        'path("")',
        'path("   ")',
        "path('')",
        'path("M0 0)',
        'path("M0 0\')',
        'path("M0 0"',
        'path(M0 0)',
        'path("M0 0") x',
        'path("M0 0"))',
        'path(evenodd "M0 0")',
        'path(evenodd,)',
        'path(evenodd, none)',
        'path(foo, "M0 0")',
        'path("M0 0", evenodd)',
        'path("M0 0" "L1 1")',
        'path ("M0 0")',
        'url("x")',
        'path(,"M0")',
        'path(evenodd,, "M0")',
        'path("M0\n0")',
        r'path("M0 0\")',
      ];
      for (final text in bad) {
        expect(parseCssPathFunction(text), isNull, reason: text);
      }
    });
  });

  group('容错', () {
    /// 每个被测函数及一份覆盖面较广的样例。
    final targets = <String, (Object? Function(String), String)>{
      'parseCssDimension': (parseCssDimension, '-1.5e2PX'),
      'parseCssNumber': (parseCssNumber, '+1.5e-2'),
      'parseCssLengthPx': (parseCssLengthPx, '-12.5px'),
      'parseCssPercent': (parseCssPercent, '13.348136%'),
      'parseCssColor': (parseCssColor, 'rgba(0 128 255 / 50%)'),
      'parseCssPathFunction': (
        parseCssPathFunction,
        r'path(evenodd, "M0,0 L\31 0 10\"")',
      ),
    };

    for (final entry in targets.entries) {
      final (parse, sample) = entry.value;
      test('${entry.key} 逐个前缀不抛异常', () => _expectPrefixesSafe(parse, sample));
      test('${entry.key} 随机输入不抛异常且快速返回', () => _expectFuzzSafe(parse));
    }

    test('parseCssColor 随机输入的非空结果都是合法 ARGB', () {
      final values = _expectFuzzSafe(parseCssColor);
      expect(values, isNotEmpty);
      for (final value in values) {
        expect(value as int, inInclusiveRange(0, 0xFFFFFFFF));
      }
    });

    test('parseCssPathFunction 随机输入的非空结果不为空串', () {
      final values = _expectFuzzSafe(parseCssPathFunction);
      expect(values, isNotEmpty);
      for (final value in values) {
        expect((value as String).trim(), isNotEmpty);
      }
    });

    test('超长输入保持线性耗时', () {
      final watch = Stopwatch()..start();
      expect(parseCssColor('rgb(${' 1' * 50000})'), isNull);
      expect(parseCssColor('rgb(${'1,' * 50000})'), isNull);
      expect(parseCssPathFunction('path("${'M0 0 ' * 50000}")'), isNotNull);
      expect(parseCssPathFunction('path("${'M0 0 ' * 50000})'), isNull);
      expect(parseCssPathFunction('path("${r'\\' * 50000}")'), isNotNull);
      expect(parseCssLengthPx('1' * 50000), isNull);
      expect(parseCssPercent('${'1' * 50000}%'), isNull);
      expect(watch.elapsed, lessThan(_fuzzBudget));
    });
  });
}
