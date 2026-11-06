import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/css_animation_values.dart';
import 'package:xvg/src/animation/css_stylesheet.dart';

/// 用声明文本构造动画配置。
List<CssAnimation> _parse(String text) =>
    parseCssAnimations(parseCssDeclarations(text));

/// 执行时间、缓动、列表和动画声明测试。
void main() {
  test('逗号列表保留函数嵌套、字符串和转义', () {
    expect(splitCssList(r''' a, fn(1, nested("x,y", 2)), 'b,c', d\,e, , '''), [
      _nameA,
      'fn(1, nested("x,y", 2))',
      "'b,c'",
      r'd\,e',
    ]);
    expect(splitCssList(' , , '), isEmpty);
  });

  test('空白词元保留函数、引号、转义及十六进制尾随空白', () {
    expect(
      splitCssTokens(r''' a fn(1, nested("x y", 2)) 'b c' d\ e \31 name '''),
      [_nameA, 'fn(1, nested("x y", 2))', "'b c'", r'd\ e', r'\31 name'],
    );
    expect(splitCssTokens(' \n\t\r\f'), isEmpty);
    expect(splitCssTokens('a\tb\nc\rd\fe'), [_nameA, _nameB, _nameC, 'd', 'e']);
  });

  for (final entry in <String, int>{
    '3000ms': 3000000,
    '2s': 2000000,
    '.5s': 500000,
    '-1s': -1000000,
    '1.5e0s': 1500000,
    '+2E-3S': 2000,
    '-.25MS': -250,
    '0ms': 0,
    '0s': 0,
    ' .000001s ': 1,
    '1.s': 1000000,
  }.entries) {
    test('解析有单位的时间：${entry.key}', () {
      expect(parseCssTime(entry.key), Duration(microseconds: entry.value));
    });
  }

  for (final value in [
    _empty,
    '0',
    '1',
    '-1',
    's',
    '2 sec',
    '2 s',
    '2px',
    'NaNs',
    'Infinitys',
    '1e999s',
    '1e30s',
    '--1s',
    '1.2.3s',
  ]) {
    test('拒绝非法或溢出的时间：$value', () {
      expect(parseCssTime(value), isNull);
    });
  }

  for (final entry in <String, CssTimingFunction>{
    'LINEAR': CssTimingFunction.linear,
    _easeKeyword: CssTimingFunction.ease,
    'ease-in': CssTimingFunction.easeIn,
    'ease-out': CssTimingFunction.easeOut,
    'ease-in-out': CssTimingFunction.easeInOut,
    'step-start': CssTimingFunction.stepStart,
    'step-end': CssTimingFunction.stepEnd,
    'cubic-bezier(0, -2, 1, 3)': const CssTimingFunction.cubicBezier(
      0,
      -2,
      1,
      3,
    ),
    ' CUBIC-BEZIER(.25, .1, .25, 1) ': CssTimingFunction.ease,
    'steps(2)': const CssTimingFunction.steps(2),
    'steps(+2, START)': const CssTimingFunction.steps(2, CssStepPosition.start),
    _twoSteps: const CssTimingFunction.steps(2),
    'steps(2, jump-start)': const CssTimingFunction.steps(
      2,
      CssStepPosition.start,
    ),
    'steps(2, jump-end)': const CssTimingFunction.steps(2),
    'steps(2, jump-none)': const CssTimingFunction.steps(
      2,
      CssStepPosition.jumpNone,
    ),
    'steps(1, jump-both)': const CssTimingFunction.steps(
      1,
      CssStepPosition.jumpBoth,
    ),
  }.entries) {
    test('解析全部缓动形式：${entry.key}', () {
      expect(parseCssTimingFunction(entry.key), entry.value);
    });
  }

  for (final value in [
    _empty,
    'unknown',
    'linear()',
    'cubic-bezier(-.1,0,1,1)',
    'cubic-bezier(0,0,1.1,1)',
    'cubic-bezier(0,0,1)',
    'cubic-bezier(0,0,1,1,2)',
    'cubic-bezier(0,NaN,1,1)',
    'cubic-bezier(0,1e999,1,1)',
    'cubic-bezier(,0,0,1,1)',
    'cubic-bezier(0,,1,1)',
    'steps(0)',
    'steps(-2)',
    'steps(1.5)',
    'steps(2.0)',
    'steps(1, jump-none)',
    'steps(2, middle)',
    'steps(2,)',
    'steps(,2)',
    'steps(2,,end)',
    'steps(2,end,end)',
    'steps()',
    'steps(999999999999999999999999999999999)',
    'steps(2) tail',
  ]) {
    test('拒绝非法缓动：$value', () {
      expect(parseCssTimingFunction(value), isNull);
    });
  }

  test('缓动值的相等、散列、线性判定和诊断文本', () {
    const a = CssTimingFunction.cubicBezier(.2, .3, .7, .8);
    final b = parseCssTimingFunction('cubic-bezier(.2,.3,.7,.8)')!;
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect({a, b}, hasLength(1));
    expect(a == CssTimingFunction.ease, isFalse);
    expect(a == const CssTimingFunction.steps(2), isFalse);
    expect(CssTimingFunction.linear.isLinear, isTrue);
    expect(
      const CssTimingFunction.cubicBezier(.2, .2, .8, .8).isLinear,
      isTrue,
    );
    expect(CssTimingFunction.ease.isLinear, isFalse);
    expect(CssTimingFunction.stepEnd.isLinear, isFalse);
    expect(CssTimingFunction.stepEnd.isSteps, isTrue);
    expect(a.toString(), 'cubic-bezier(0.2, 0.3, 0.7, 0.8)');
    expect(const CssTimingFunction.steps(2).toString(), _twoSteps);
  });

  test('空声明和单个名字使用初始值', () {
    expect(_parse(_empty), isEmpty);
    final animation = _parse('animation: Travel').single;
    expect(animation.name, _travelName);
    expect(animation.duration, Duration.zero);
    expect(animation.delay, Duration.zero);
    expect(animation.timing, CssTimingFunction.ease);
    expect(animation.iterationCount, 1);
    expect(animation.direction, CssAnimationDirection.normal);
    expect(animation.fillMode, CssAnimationFillMode.none);
    expect(animation.paused, isFalse);
  });

  test('简写词元乱序，两个时间按出现顺序分配', () {
    final animation = _parse('''animation:
      PAUSED forwards INFINITE alternate-reverse steps(3, jump-none) 2s Travel -.5s
    ''').single;
    expect(animation.name, _travelName);
    expect(animation.duration, const Duration(seconds: 2));
    expect(animation.delay, const Duration(milliseconds: -500));
    expect(
      animation.timing,
      const CssTimingFunction.steps(3, CssStepPosition.jumpNone),
    );
    expect(animation.iterationCount, double.infinity);
    expect(animation.direction, CssAnimationDirection.alternateReverse);
    expect(animation.fillMode, CssAnimationFillMode.forwards);
    expect(animation.paused, isTrue);
  });

  test('逗号多动画与无单位零迭代次数', () {
    final animations = _parse(
      'animation: a 1s 0 linear, b 2s 2.5 ease-in, c 3s infinite',
    );
    expect(animations.map((a) => a.name), [_nameA, _nameB, _nameC]);
    expect(animations.map((a) => a.iterationCount), [0, 2.5, double.infinity]);
    expect(animations[0].duration, const Duration(seconds: 1));
    expect(animations[1].timing, CssTimingFunction.easeIn);
  });

  test('长写列循环取值，并按名字列决定长度', () {
    final animations = _parse('''
      animation-name: a, b, c, d, e;
      animation-duration: 1s, 2s;
      animation-delay: -1s, 0s, 1s;
      animation-timing-function: linear, steps(2, start);
      animation-iteration-count: infinite, 0;
      animation-direction: reverse, alternate;
      animation-fill-mode: both, backwards;
      animation-play-state: paused, running;
    ''');
    expect(animations, hasLength(5));
    expect(animations.map((a) => a.duration.inSeconds), [1, 2, 1, 2, 1]);
    expect(animations.map((a) => a.delay.inSeconds), [-1, 0, 1, -1, 0]);
    expect(animations[2].timing, CssTimingFunction.linear);
    expect(animations[3].iterationCount, 0);
    expect(animations[2].direction, CssAnimationDirection.reverse);
    expect(animations[3].fillMode, CssAnimationFillMode.backwards);
    expect(animations.map((a) => a.paused), [true, false, true, false, true]);
  });

  test('简写后长写只替换对应列', () {
    final animations = _parse('''
      animation: a 2s 1s linear infinite reverse both paused, b 3s;
      animation-duration: 4s; animation-name: X, Y, Z;
    ''');
    expect(animations.map((a) => a.name), ['X', 'Y', 'Z']);
    expect(animations.every((a) => a.duration.inSeconds == 4), isTrue);
    expect(animations[2].delay, const Duration(seconds: 1));
    expect(animations[2].timing, CssTimingFunction.linear);
    expect(animations[2].iterationCount, double.infinity);
    expect(animations[2].direction, CssAnimationDirection.reverse);
    expect(animations[2].fillMode, CssAnimationFillMode.both);
    expect(animations[2].paused, isTrue);
  });

  test('后续简写将全部长写列重置为初始值', () {
    final animation = _parse('''
      animation: old 5s -1s linear infinite alternate both paused;
      animation-name: other, more; animation: New;
    ''').single;
    expect(animation.name, 'New');
    expect(animation.duration, Duration.zero);
    expect(animation.delay, Duration.zero);
    expect(animation.timing, CssTimingFunction.ease);
    expect(animation.iterationCount, 1);
    expect(animation.direction, CssAnimationDirection.normal);
    expect(animation.fillMode, CssAnimationFillMode.none);
    expect(animation.paused, isFalse);
  });

  test('空名字项不产出动画但仍占用循环下标', () {
    final animations = _parse(
      'animation-name: none, A, NONE, B; animation-duration: 1s, 2s',
    );
    expect(animations.map((a) => a.name), ['A', 'B']);
    expect(animations.map((a) => a.duration.inSeconds), [2, 2]);
    expect(_parse('animation: none'), isEmpty);
    expect(_parse('animation: a 2s; animation: none'), isEmpty);
  });

  test('关键字槽位已占用时该关键字可作为名字', () {
    final animations = _parse('''animation:
      ease ease 1s, reverse reverse 1s, both both 1s,
      paused paused 1s, infinite infinite 1s, none none 1s
    ''');
    expect(animations.map((a) => a.name), [
      _easeKeyword,
      'reverse',
      'both',
      'paused',
      'infinite',
    ]);
  });

  test('名称保留大小写并解码转义或字符串', () {
    final animations = _parse(
      r'''ANIMATION: "Keep Case" 1S, \31 name 2s, a\.b 3s''',
    );
    expect(animations.map((a) => a.name), ['Keep Case', '1name', 'a.b']);
    expect(animations[0].duration, const Duration(seconds: 1));
  });

  test('重要标记不在值解析阶段重新排序', () {
    final animation = parseCssAnimations(const [
      CssDeclaration('animation', 'a 2s', important: true),
      CssDeclaration('ANIMATION-DURATION', '3S'),
    ]).single;
    expect(animation.duration, const Duration(seconds: 3));
  });

  for (final invalid in [
    'animation-name: a,',
    'animation-name: a b',
    'animation-duration: 3s, nope',
    'animation-duration: -1s',
    'animation-delay: 0',
    'animation-timing-function: steps(0)',
    'animation-iteration-count: -1',
    'animation-direction: sideways',
    'animation-fill-mode: other',
    'animation-play-state: stopped',
    'animation: -1s b',
    'animation: b 1s 2s 3s',
    'animation: b -1',
    'animation: b invalid',
    'animation: b 1s, nope bad',
    'animation: b cubic-bezier(2,0,1,1)',
    'animation: b steps(2,)',
    'animation: b,',
    'animation: ,b',
    'animation: b,,c',
    'animation: "unclosed',
    'animation: b fn(',
    'animation-duration: 1e999s',
    'animation-iteration-count: NaN',
  ]) {
    test('非法声明整条忽略：$invalid', () {
      final animation = _parse('animation: Original 2s; $invalid').single;
      expect(animation.name, 'Original');
      expect(animation.duration, const Duration(seconds: 2));
    });
  }

  test('合法的后续声明正常覆盖，未知属性不影响动画', () {
    final animation = _parse('''
      animation: a 1s; unknown: x; animation-duration: bad;
      animation-duration: 3s; animation-play-state: paused;
    ''').single;
    expect(animation.duration, const Duration(seconds: 3));
    expect(animation.paused, isTrue);
  });

  test('长转义标识符单遍解析，非法尾字符不会触发回溯', () {
    final escaped = r'\aaaaaa' * 30000;
    final watch = Stopwatch()..start();
    final animations = parseCssAnimations([
      CssDeclaration(_nameProperty, '$escaped!'),
      const CssDeclaration(_nameProperty, _validAnimationName),
    ]);
    expect(animations.single.name, _validAnimationName);
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
  });
}

/// 测试使用的动画名称属性。
const _nameProperty = 'animation-name';

/// 长标识符测试中最终生效的动画名。
const _validAnimationName = 'valid';

/// 重复使用的解析符号或样例文本。
const _nameA = 'a';

/// 重复使用的解析符号或样例文本。
const _nameB = 'b';

/// 重复使用的解析符号或样例文本。
const _nameC = 'c';

/// 重复使用的解析符号或样例文本。
const _empty = '';

/// 重复使用的解析符号或样例文本。
const _easeKeyword = 'ease';

/// 重复使用的解析符号或样例文本。
const _twoSteps = 'steps(2, end)';

/// 重复使用的解析符号或样例文本。
const _travelName = 'Travel';
