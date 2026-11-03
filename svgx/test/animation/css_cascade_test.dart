import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/css_animation_values.dart';
import 'package:svgx/src/animation/css_cascade.dart';
import 'package:svgx/src/animation/css_stylesheet.dart';

/// 与 XML 无关的测试树。
class _Element implements CssElement {
  /// 创建带原始属性的测试元素。
  _Element(this.localName, {this.attrs = const {}, this.parent});

  /// 本地标签名。
  @override
  final String localName;

  /// 原始属性表。
  final Map<String, String> attrs;

  /// 父元素。
  @override
  final _Element? parent;

  /// 读取测试属性。
  @override
  String? attribute(String name) => attrs[name];
}

/// 记录读取次数以验证查询只检查候选桶。
class _CountingElement extends _Element {
  /// 创建固定标识的计数元素。
  _CountingElement() : super('rect', attrs: {'id': 'selected'});

  /// 查询过程的属性读取次数。
  int reads = 0;

  /// 记录选择器及索引读取的总次数。
  @override
  String? attribute(String name) {
    reads++;
    return super.attribute(name);
  }
}

/// 从规则文本取出一个选择器。
CssSelector _selector(String source) =>
    parseCssStylesheet('$source {opacity:1}').rules.single.selectors.single;

/// 对指定测试元素计算样式。
CssComputed _compute(String source, _Element element, [String inline = '']) =>
    computeCssStyle(
      CssRuleIndex(parseCssStylesheet(source)),
      element,
      parseCssDeclarations(inline),
    );

/// 暴力遍历所有规则的独立排序参照。
List<CssDeclaration> _brute(
  CssStylesheet sheet,
  CssElement element,
  List<CssDeclaration> inline,
) {
  final entries = <(CssDeclaration, int, int, int, int, int)>[];
  for (final rule in sheet.rules) {
    final matching = rule.selectors.where(
      (s) => cssSelectorMatches(s, element),
    );
    if (matching.isEmpty) continue;
    final specificity = matching.map((s) => s.specificity).reduce(max);
    for (var i = 0; i < rule.declarations.length; i++) {
      final d = rule.declarations[i];
      entries.add((d, d.important ? 1 : 0, 0, specificity, rule.order, i));
    }
  }
  for (var i = 0; i < inline.length; i++) {
    final d = inline[i];
    entries.add((d, d.important ? 1 : 0, 1, 0, 0, i));
  }
  entries.sort((a, b) {
    final left = [a.$2, a.$3, a.$4, a.$5, a.$6];
    final right = [b.$2, b.$3, b.$4, b.$5, b.$6];
    for (var i = 0; i < left.length; i++) {
      final result = left[i].compareTo(right[i]);
      if (result != 0) return result;
    }
    return 0;
  });
  return entries.map((e) => e.$1).toList();
}

/// 验证选择器、层叠、分流及索引完整性。
void main() {
  final root = _Element('svg', attrs: {'id': 'root'});
  final group = _Element('g', parent: root, attrs: {'class': 'outer'});
  final inner = _Element('g', parent: group);
  final rect = _Element(
    'rect',
    parent: inner,
    attrs: {'id': 'r', 'class': 'a b\tc\nd\re\ff'},
  );
  final cases = <String, bool>{
    'rect': true, 'Rect': false, '*': true, '#r': true, '#x': false,
    '.a.b.c.d.e.f': true, 'rect#r.a.b': true, 'circle#r': false,
    'svg rect': true, '.outer rect': true, 'g > rect': true,
    'svg > rect': false, '.outer > rect': false,
    'svg > g rect': true, 'svg > g > rect': false,
    // 最近的 g 不满足左侧子代条件时必须回溯更早的 g。
    'svg > g rect.a': true,
  };
  for (final entry in cases.entries) {
    test('选择器 ${entry.key}', () {
      expect(cssSelectorMatches(_selector(entry.key), rect), entry.value);
    });
  }
  test('选择器后代匹配需要回溯', () {
    final deep = _Element('rect', parent: _Element('g', parent: inner));
    expect(cssSelectorMatches(_selector('svg > g rect'), deep), isTrue);
  });
  final cascadeCases = <(String, String, String)>[
    ('#r{fill:id}.a{fill:class}rect{fill:tag}*{fill:any}', '', 'id'),
    ('.a{fill:first}.b{fill:last}', '', 'last'),
    ('#r{fill:id}*{fill:important!important}', '', 'important'),
    ('#r{fill:id}', 'fill:inline', 'inline'),
    ('#r{fill:rule!important}', 'fill:inline', 'rule'),
    ('#r{fill:rule!important}', 'fill:inline!important', 'inline'),
    ('*{fill:first;fill:last}', '', 'last'),
    ('', 'fill:first!important;fill:last!important', 'last'),
    ('#r,.a{fill:first}.b{fill:last}', '', 'first'),
  ];
  for (var i = 0; i < cascadeCases.length; i++) {
    test('层叠顺序 $i', () {
      final c = cascadeCases[i];
      expect(_compute(c.$1, rect, c.$2).attributes['fill'], c.$3);
    });
  }
  test('animation 简写长写按排序后的完整声明序列解析', () {
    final result = _compute(
      '''
      #r{animation-duration:3s!important}
      .a{animation:fade 1s linear 2s 4 reverse both paused}
      *{animation-duration:9s}
    ''',
      rect,
      'animation-duration:2s;animation-delay:-1s',
    );
    final animation = result.animations.single;
    expect(animation.name, 'fade');
    expect(animation.duration, const Duration(seconds: 3));
    expect(animation.delay, const Duration(seconds: -1));
    expect(animation.timing, CssTimingFunction.linear);
    expect(animation.iterationCount, 4);
    expect(animation.direction, CssAnimationDirection.reverse);
    expect(animation.fillMode, CssAnimationFillMode.both);
    expect(animation.paused, isTrue);
    expect(result.attributes, isEmpty);
    expect(result.properties, isEmpty);
    expect(
      _compute(
        '*{animation:fade 1s;animation-duration:4s;animation:other 2s}',
        rect,
      ).animations.single.duration,
      const Duration(seconds: 2),
    );
  });
  const cssOnly = [
    'transform',
    'transform-origin',
    'transform-box',
    'offset',
    'offset-path',
    'offset-distance',
    'offset-rotate',
    'offset-anchor',
    'offset-position',
    'd',
    'mix-blend-mode',
    'isolation',
  ];
  for (final property in cssOnly) {
    test('$property 仅进入保留属性', () {
      final result = _compute('*{$property:original;$property:final}', rect);
      expect(result.attributes, isEmpty);
      expect(result.properties, {property: 'final'});
    });
  }
  for (final value in [
    'var(--x)',
    'calc(2px + 1px)',
    'ENV(x)',
    'InHerit',
    'initial',
    'UNSET',
    'revert',
    'revert-layer',
  ]) {
    test('忽略不支持值 $value 并保留先前声明', () {
      final result = _compute(
        '*{fill:#abc;fill:$value;animation:$value;transform:$value}',
        rect,
      );
      expect(result.attributes, {'fill': '#abc'});
      expect(result.properties, isEmpty);
      expect(result.animations, isEmpty);
    });
  }
  test('丢弃 transition 和自定义属性', () {
    expect(
      identical(
        _compute('*{transition:all;transition-delay:1s;--x:2}', rect),
        CssComputed.empty,
      ),
      isTrue,
    );
  });
  for (final value in [
    '2px',
    '.5px',
    '-1.5px',
    '+2px',
    '1e2px',
    '2em',
    '50%',
    '1.5',
    '2px 3px',
  ]) {
    test('像素规范化 $value', () {
      final expected = value.endsWith('px') && !value.contains(' ')
          ? value.substring(0, value.length - 2)
          : value;
      expect(
        _compute('*{stroke-width:$value}', rect).attributes['stroke-width'],
        expected,
      );
    });
  }
  test('所有桶命中，多选择器只产出一次声明', () {
    final index = CssRuleIndex(
      parseCssStylesheet('*{a:1}rect{b:2}.a{c:3}#r,.a,rect{d:4}'),
    );
    expect(index.cascade(rect).map((d) => d.property), ['a', 'b', 'c', 'd']);
    expect(index.isEmpty, isFalse);
    expect(CssRuleIndex(const CssStylesheet([], {})).isEmpty, isTrue);
  });
  test('未命中与无声明复用共享空结果', () {
    expect(
      identical(_compute('#missing{fill:#f00}', rect), CssComputed.empty),
      isTrue,
    );
    expect(identical(_compute('*{}', rect), CssComputed.empty), isTrue);
  });
  test('class 桶哈希碰撞仍需精确匹配，重复类名不重复产出', () {
    final element = _Element('rect', attrs: {'class': 'Aa Aa'});
    final result = _compute('.Aa{fill:#f00}.BB{fill:#00f}', element);
    expect(result.attributes, {'fill': '#f00'});
    final index = CssRuleIndex(parseCssStylesheet('.Aa{opacity:.5}'));
    expect(index.cascade(element), hasLength(1));
  });
  test('大量无关规则不参与元素查询', () {
    final source = StringBuffer('#selected{opacity:.5}');
    for (var i = 0; i < 2000; i++) {
      source.write('#other$i{opacity:1}');
    }
    final element = _CountingElement();
    final index = CssRuleIndex(parseCssStylesheet(source.toString()));
    expect(index.cascade(element).single.value, '.5');
    expect(element.reads, lessThanOrEqualTo(3));
  });
  test('固定种子 600 个随机树查询与暴力扫描一致', () {
    final random = Random(74219);
    const tags = ['svg', 'g', 'rect', 'path'];
    const atoms = [
      '*',
      'g',
      'rect',
      'path',
      '#n0',
      '#n1',
      '#n2',
      '.a',
      '.b',
      '.c',
      'rect.a',
      '#n1.b',
    ];
    final nodes = <_Element>[];
    for (var i = 0; i < 600; i++) {
      nodes.add(
        _Element(
          tags[random.nextInt(tags.length)],
          parent: nodes.isEmpty ? null : nodes[random.nextInt(nodes.length)],
          attrs: {
            'id': 'n${random.nextInt(3)}',
            'class': '${random.nextBool() ? 'a' : 'c'} b',
          },
        ),
      );
    }
    final source = StringBuffer();
    for (var i = 0; i < 180; i++) {
      final a = atoms[random.nextInt(atoms.length)];
      final b = atoms[random.nextInt(atoms.length)];
      final selector = switch (random.nextInt(4)) {
        0 => '$a > $b',
        1 => '$a $b',
        2 => '$a,$b',
        _ => a,
      };
      source.write(
        '$selector{p:$i${random.nextBool() ? '!important' : ''};q:${i + 1}}',
      );
    }
    final sheet = parseCssStylesheet(source.toString());
    final index = CssRuleIndex(sheet);
    for (final node in nodes) {
      final inline = random.nextBool()
          ? parseCssDeclarations('p:inline;q:strong!important')
          : <CssDeclaration>[];
      expect(index.cascade(node, inline: inline), _brute(sheet, node, inline));
    }
  });
}
