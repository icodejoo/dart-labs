import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/css_animation_values.dart';
import 'package:svgx/src/animation/css_stylesheet.dart';

/// 覆盖典型导出结构的原创样式样例。
const _svgator = '''
/* 导出样式 */
<![CDATA[<!--
#root #dot, .moving {
  animation: Travel 3s linear infinite forwards, Fade 1s steps(2, end);
  animation-delay: -.5s;
  offset-path: path("M0 0 C1 2 3 4 5 6");
}
@keyframes Travel {
  0%,50% {
    transform: translate(0px, 1px) rotate(10deg) scale(1, 2);
    animation-timing-function: cubic-bezier(.25, .1, .25, 1);
    d: path("M0 0;L1 1}");
  }
  60.5% { offset-distance: 60.5%; animation-timing-function: steps(3, jump-none) }
  to { transform: translate(10px, 20px) skewX(5deg) }
}
@keyframes Fade { from { opacity: 0 } to { opacity: 1 } }
-->]]>
''';

/// 执行样式表模型、词法边界及容错测试。
void main() {
  test('完整导出样例保留规则、关键帧及原始值', () {
    final sheet = parseCssStylesheet(_svgator);
    expect(sheet.rules, hasLength(1));
    final rule = sheet.rules.single;
    expect(rule.selectors, hasLength(2));
    expect(rule.order, 0);
    final animations = parseCssAnimations(rule.declarations);
    expect(animations.map((a) => a.name), [_travelName, _fadeName]);
    expect(animations.every((a) => a.delay.inMilliseconds == -500), isTrue);
    expect(animations.first.iterationCount, double.infinity);
    expect(rule.declarations.last.value, 'path("M0 0 C1 2 3 4 5 6")');
    final stops = sheet.keyframes[_travelName]!.stops;
    expect(stops.map((s) => s.offset), [0, .5, .605, 1]);
    expect(stops[0].declarations.map((d) => d.property), [
      'transform',
      'animation-timing-function',
      _pathProperty,
    ]);
    expect(
      stops[0].declarations.first.value,
      'translate(0px, 1px) rotate(10deg) scale(1, 2)',
    );
    expect(stops[0].declarations.last.value, _quotedPath);
    expect(
      parseCssTimingFunction(stops[0].declarations[1].value),
      CssTimingFunction.ease,
    );
    expect(
      parseCssTimingFunction(stops[2].declarations[1].value),
      const CssTimingFunction.steps(3, CssStepPosition.jumpNone),
    );
    expect(sheet.keyframes[_fadeName]!.stops.map((s) => s.offset), [0, 1]);
  });

  test('普通规则顺序与不支持的选择器相互独立', () {
    final sheet = parseCssStylesheet('''
      :hover { a: b } #one { a: b }
      [a], .ok, a + b, a ~ b, #no:hover, rect[a="x,y"] { a: c }
      path { a: d }
    ''');
    expect(sheet.rules.map((r) => r.order), [0, 1, 2]);
    expect(sheet.rules[1].selectors, hasLength(1));
    expect(sheet.rules[1].selectors.single.compounds.single.classes, [
      _validName,
    ]);
  });

  test('复合、后代、子代和通配选择器计算优先级', () {
    final rules = parseCssStylesheet(
      'svg.outer > rect.a#b .c, * > #x { opacity: 1 }',
    ).rules;
    final selectors = rules.single.selectors;
    expect(selectors.first.compounds.map((c) => c.tag), ['svg', 'rect', null]);
    expect(selectors.first.compounds[1].id, _nameB);
    expect(selectors.first.compounds[1].classes, [_nameA]);
    expect(selectors.first.combinators, [
      CssCombinator.child,
      CssCombinator.descendant,
    ]);
    expect(selectors.first.specificity, (1 << 16) | (3 << 8) | 2);
    expect(selectors.last.compounds.first.tag, isNull);
    expect(selectors.last.specificity, 1 << 16);
  });

  test('标识符支持非英文、数字及简单和十六进制转义', () {
    final selectors = parseCssStylesheet(
      r'#a\.b, .\31 23, #\000041名, rect.中文, #\1f600, #\0 , #\110000 { a:b }',
    ).rules.single.selectors;
    expect(selectors[0].compounds.single.id, 'a.b');
    expect(selectors[1].compounds.single.classes, ['123']);
    expect(selectors[2].compounds.single.id, 'A名');
    expect(selectors[3].compounds.single.classes, ['中文']);
    expect(selectors[4].compounds.single.id, '😀');
    expect(selectors[5].compounds.single.id, _replacementCharacter);
    expect(selectors[6].compounds.single.id, _replacementCharacter);
  });

  for (final selector in [
    _empty,
    '#',
    '.',
    '> a',
    'a >',
    'a >> b',
    'a#x#y',
    'a:hover',
    'a::before',
    '[a]',
    'a+b',
    'a~b',
    'a|b',
  ]) {
    test('非法或不支持的选择器独立丢弃：$selector', () {
      expect(
        parseCssStylesheet('$selector, #ok { a:b }').rules.single.selectors,
        hasLength(1),
      );
    });
  }

  test('跳过语句及嵌套块规则，不读取其内部动画', () {
    final sheet = parseCssStylesheet('''
      @import url("x;{}.css"); @charset "UTF-8";
      @namespace svg url(http://example.test);
      @media screen { @supports (display: grid) {
        #hidden { animation: hidden 1s } @keyframes hidden { to { a:b } }
      } }
      @font-face { font-family: "x}"; src: url(data:x;abc) }
      @page { @top-left { content: "}" } }
      #visible { opacity: 1 }
    ''');
    expect(sheet.rules, hasLength(1));
    expect(sheet.rules.single.selectors.single.compounds.single.id, 'visible');
    expect(sheet.keyframes, isEmpty);
  });

  for (final prefix in [_empty, '-webkit-', '-moz-', '-o-', '-ms-']) {
    test('关键帧规则前缀与关键字忽略大小写：$prefix', () {
      final sheet = parseCssStylesheet(
        '@${prefix.toUpperCase()}KEYFRAMES "Keep Case" { FROM { a:b } TO { a:c } }',
      );
      expect(sheet.keyframes['Keep Case']!.stops.map((s) => s.offset), [0, 1]);
    });
  }

  test('同名定义整体覆盖，名称解码并区分大小写', () {
    final sheet = parseCssStylesheet(r'''
      @keyframes a { from { old: 1 } }
      @keyframes A { to { upper: 1 } }
      @-webkit-keyframes "a" { 50% { newer: 1 } }
      @keyframes \31 name { to { escaped: 1 } }
    ''');
    expect(sheet.keyframes.keys, [_nameA, 'A', '1name']);
    expect(sheet.keyframes[_nameA]!.stops.single.offset, .5);
    expect(
      sheet.keyframes[_nameA]!.stops.single.declarations.single.property,
      'newer',
    );
  });

  test('位置排序、同位置声明拼接，非法百分数只丢弃该项', () {
    final stops = parseCssStylesheet('''
      @keyframes a {
        to { a:1 } 50%,bad,-1%,101%,NaN%,10e1%,20px { b:2 }
        from, .5% { c:3 } 50% { b:4 } BAD { nope:0 }
        60.5%,+70% { d:5 }
      }
    ''').keyframes[_nameA]!.stops;
    expect(stops.map((s) => s.offset), [0, .005, .5, .605, .7, 1]);
    expect(stops[2].declarations.map((d) => d.value), [_twoText, '4']);
  });

  test('注释与包裹标记被剥离，字符串内部文本保持', () {
    final sheet = parseCssStylesheet('''
      <![CDATA[<!-- #a/**/.b { OPACITY: /*值*/ .5;
      content: "/*原文*/ <!-- --> <![CDATA[ ]]>"; } -->]]>
      #b { opacity:1 } /*未闭合
    ''');
    expect(sheet.rules, hasLength(2));
    expect(sheet.rules.first.selectors.single.compounds.single.classes, [
      _nameB,
    ]);
    expect(sheet.rules.first.declarations.first.value, _halfText);
    expect(
      sheet.rules.first.declarations.last.value,
      '"/*原文*/ <!-- --> <![CDATA[ ]]>"',
    );
  });

  test('声明保护括号、引号、转义分号及右花括号', () {
    final declarations = parseCssDeclarations(r'''
      OPACITY:  .5  ! IMPORTANT ; --Custom:  var(--Other, a  b);
      d: path("M0 0;L1 1}"); image: url(data:image/png;base64,xxx);
      content: 'a;\'b}'; escaped: a\;b; final: yes
    ''');
    expect(declarations.map((d) => d.property), [
      'opacity',
      '--Custom',
      _pathProperty,
      'image',
      'content',
      'escaped',
      'final',
    ]);
    expect(declarations.first.value, _halfText);
    expect(declarations.first.important, isTrue);
    expect(declarations[1].value, 'var(--Other, a  b)');
    expect(declarations[2].value, _quotedPath);
    expect(declarations[4].value, r"'a;\'b}'");
    expect(declarations[5].value, r'a\;b');
  });

  test('字符串中的重要标记不参与优先级', () {
    final declarations = parseCssDeclarations(
      'a: "!important"; b: fn(!important); c: x !imPORTant; d: x ! nope; e: !important',
    );
    expect(declarations.map((d) => d.important), [false, false, true, false]);
    expect(declarations[2].value, 'x');
  });

  test('坏声明不影响下一个分号之后的声明', () {
    final declarations = parseCssDeclarations(
      'bad; :x; empty:; bad prop:x; OK: yes; --X: 1; last: 2',
    );
    expect(declarations.map((d) => d.property), [_validName, '--X', 'last']);
    expect(declarations.map((d) => d.value), ['yes', _oneText, _twoText]);
  });

  test('截断块仍保留此前读到的声明', () {
    final sheet = parseCssStylesheet('#a { x:1 } @keyframes a { from { x:2');
    expect(sheet.rules.single.declarations.single.value, _oneText);
    expect(
      sheet.keyframes[_nameA]!.stops.single.declarations.single.value,
      _twoText,
    );
  });

  test('同一块的位置去重，共享声明且后续合并不污染其他位置', () {
    final sheet = parseCssStylesheet('''
      @keyframes shared { 0%,50%,from { x:1 } to { x:2 } }
      @keyframes merged { 0%,50% { x:1 } from { x:3 } }
    ''');
    final shared = sheet.keyframes['shared']!.stops;
    expect(shared.first.declarations, hasLength(1));
    expect(identical(shared[0].declarations, shared[1].declarations), isTrue);
    final merged = sheet.keyframes['merged']!.stops;
    expect(merged.first.declarations.map((d) => d.value), [_oneText, '3']);
    expect(merged.last.declarations.single.value, _oneText);
  });

  for (final source in [
    _empty,
    ' \n\t ',
    '@',
    '}',
    '{{{',
    '@import',
    '@keyframes',
    '@keyframes "',
    '#a { x: fn(',
    '#a { x: "',
    '@media { a { b:c }',
    '/*',
    '#\\',
    '@unknown fn(";{")',
  ]) {
    test('畸形输入安全结束：$source', () {
      expect(() => parseCssStylesheet(source), returnsNormally);
      expect(() => parseCssDeclarations(source), returnsNormally);
    });
  }

  test('样例的每一个前缀均安全结束', () {
    for (var i = 0; i <= _svgator.length; i++) {
      final prefix = _svgator.substring(0, i);
      expect(
        () => parseCssStylesheet(prefix),
        returnsNormally,
        reason: '前缀长度 $i',
      );
      expect(
        () => parseCssDeclarations(prefix),
        returnsNormally,
        reason: '声明长度 $i',
      );
    }
  });

  test('固定种子随机输入在时间限制内安全结束', () {
    final random = Random(20261103);
    const alphabet = 'abcXYZ019-_%#.@!:/;{}[]()<>+~*=, \\ \n\t\r\'"中文';
    final watch = Stopwatch()..start();
    for (var run = 0; run < 5000; run++) {
      final text = String.fromCharCodes(
        List.generate(
          random.nextInt(201),
          (_) => alphabet.codeUnitAt(random.nextInt(alphabet.length)),
        ),
      );
      final sheet = parseCssStylesheet(text);
      parseCssAnimations(parseCssDeclarations(text));
      for (final rule in sheet.rules) {
        for (final selector in rule.selectors) {
          expect(selector.combinators.length, selector.compounds.length - 1);
        }
      }
    }
    expect(watch.elapsed, lessThan(const Duration(seconds: 15)));
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('大段注释和大量嵌套未知块不递归或反复扫描', () {
    final comment = '/*${'x' * 100000}*/';
    final nested = '${'@unknown {' * 10000}${'}' * 10000}';
    final sheet = parseCssStylesheet('$comment$nested#a { opacity: 1 }');
    expect(sheet.rules, hasLength(1));
  });
}

/// 重复使用的解析符号或样例文本。
const _travelName = 'Travel';

/// 重复使用的解析符号或样例文本。
const _fadeName = 'Fade';

/// 重复使用的解析符号或样例文本。
const _pathProperty = 'd';

/// 重复使用的解析符号或样例文本。
const _quotedPath = 'path("M0 0;L1 1}")';

/// 重复使用的解析符号或样例文本。
const _validName = 'ok';

/// 重复使用的解析符号或样例文本。
const _nameB = 'b';

/// 重复使用的解析符号或样例文本。
const _nameA = 'a';

/// 重复使用的解析符号或样例文本。
const _replacementCharacter = '\uFFFD';

/// 重复使用的解析符号或样例文本。
const _empty = '';

/// 重复使用的解析符号或样例文本。
const _twoText = '2';

/// 重复使用的解析符号或样例文本。
const _halfText = '.5';

/// 重复使用的解析符号或样例文本。
const _oneText = '1';
