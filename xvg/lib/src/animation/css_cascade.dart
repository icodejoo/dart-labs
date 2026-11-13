import 'css_animation_values.dart';
import 'css_chars.dart';
import 'css_stylesheet.dart';
import 'number_syntax.dart';

/// 选择器所需的元素视图；属性和父链由调用方提供，返回匹配所需文本。
///
/// ```dart
/// bool matches(CssElement node) => cssSelectorMatches(
///   parseCssStylesheet('* {opacity:1}').rules.single.selectors.single, node);
/// ```
abstract class CssElement {
  /// 区分大小写的本地标签名。
  String get localName;

  /// 读取 [name] 属性，缺失时返回空值。
  String? attribute(String name);

  /// 父元素，根元素返回空值。
  CssElement? get parent;
}

/// 对一段类名计算小整数哈希，查询时无需创建子串；碰撞交给精确匹配排除。
int _classHash(String source, int start, int end) {
  var hash = 0;
  for (var i = start; i < end; i++) {
    hash = (hash * 31 + source.codeUnitAt(i)) & 0x3fffffff;
  }
  return hash;
}

/// 无分配地验证空白分隔的类名集合是否包含指定类名。
bool _hasClass(String source, String name) {
  var start = 0;
  for (var end = 0; end <= source.length; end++) {
    if (end < source.length && !isCssSpace(source.codeUnitAt(end))) continue;
    if (end - start == name.length) {
      var matches = true;
      for (var i = 0; i < name.length; i++) {
        if (source.codeUnitAt(start + i) != name.codeUnitAt(i)) {
          matches = false;
          break;
        }
      }
      if (matches) return true;
    }
    start = end + 1;
  }
  return false;
}

/// 判断 [element] 是否匹配 [selector]，返回右到左匹配结果。
///
/// ```dart
/// final selector = parseCssStylesheet('g > rect {opacity:1}')
///     .rules.single.selectors.single;
/// // cssSelectorMatches(selector, element);
/// ```
bool cssSelectorMatches(CssSelector selector, CssElement element) =>
    _matchesAt(selector, selector.compounds.length - 1, element, {});

/// 递归验证一段条件，后代关系允许回溯祖先链。
bool _matchesAt(
  CssSelector selector,
  int position,
  CssElement element,
  Map<(CssElement, int), bool> memo,
) {
  final key = (element, position);
  return memo[key] ??= _matchesUncached(selector, position, element, memo);
}

/// 在当前选择器位置执行匹配，递归子问题由外层记忆化避免重复遍历祖先。
bool _matchesUncached(
  CssSelector selector,
  int position,
  CssElement element,
  Map<(CssElement, int), bool> memo,
) {
  final part = selector.compounds[position];
  if (part.tag != null && part.tag != element.localName) return false;
  if (part.id != null && part.id != element.attribute(_idAttribute)) {
    return false;
  }
  if (part.classes.isNotEmpty) {
    final classes = element.attribute(_classAttribute);
    if (classes == null) return false;
    for (final name in part.classes) {
      if (!_hasClass(classes, name)) return false;
    }
  }
  if (position == 0) return true;
  var parent = element.parent;
  if (selector.combinators[position - 1] == CssCombinator.child) {
    return parent != null && _matchesAt(selector, position - 1, parent, memo);
  }
  while (parent != null) {
    if (_matchesAt(selector, position - 1, parent, memo)) return true;
    parent = parent.parent;
  }
  return false;
}

/// 一次构建的选择器索引，参数 [sheet] 提供规则，查询返回有序声明。
///
/// ```dart
/// final index = CssRuleIndex(parseCssStylesheet('#r {opacity:.5}'));
/// print(index.isEmpty);
/// ```
class CssRuleIndex {
  /// 按最右条件将 [sheet] 中的选择器加入候选桶。
  CssRuleIndex(CssStylesheet sheet) {
    for (final rule in sheet.rules) {
      for (final selector in rule.selectors) {
        final part = selector.compounds.last;
        final entry = _Candidate(rule, selector);
        if (part.id != null) {
          (_ids[part.id!] ??= []).add(entry);
        } else if (part.classes.isNotEmpty) {
          final name = part.classes.first;
          (_classes[_classHash(name, 0, name.length)] ??= []).add(entry);
        } else if (part.tag != null) {
          (_tags[part.tag!] ??= []).add(entry);
        } else {
          _universal.add(entry);
        }
      }
    }
  }

  /// 标识候选桶。
  final _ids = <String, List<_Candidate>>{};

  /// 类名候选桶。
  final _classes = <int, List<_Candidate>>{};

  /// 标签候选桶。
  final _tags = <String, List<_Candidate>>{};

  /// 通用候选桶。
  final _universal = <_Candidate>[];

  /// 是否没有任何候选规则。
  bool get isEmpty =>
      _ids.isEmpty && _classes.isEmpty && _tags.isEmpty && _universal.isEmpty;

  /// 返回对 [element] 生效的声明，含 [inline]，按层叠顺序升序排列。
  List<CssDeclaration> cascade(
    CssElement element, {
    List<CssDeclaration> inline = const [],
  }) {
    var matches = _collectMatches(_universal, element, null);
    matches = _collectMatches(
      _ids[element.attribute(_idAttribute)],
      element,
      matches,
    );
    final classes = element.attribute(_classAttribute);
    if (classes != null && _classes.isNotEmpty) {
      var start = 0;
      for (var end = 0; end <= classes.length; end++) {
        if (end < classes.length && !isCssSpace(classes.codeUnitAt(end))) {
          continue;
        }
        if (end > start) {
          matches = _collectMatches(
            _classes[_classHash(classes, start, end)],
            element,
            matches,
          );
        }
        start = end + 1;
      }
    }
    matches = _collectMatches(_tags[element.localName], element, matches);
    if (matches == null && inline.isEmpty) return const [];
    final ordered = <_OrderedDeclaration>[];
    matches?.forEach((rule, specificity) {
      for (var i = 0; i < rule.declarations.length; i++) {
        ordered.add(
          _OrderedDeclaration(
            rule.declarations[i],
            false,
            specificity,
            rule.order,
            i,
          ),
        );
      }
    });
    for (var i = 0; i < inline.length; i++) {
      ordered.add(_OrderedDeclaration(inline[i], true, 0, 0, i));
    }
    ordered.sort(_compareDeclarations);
    return [for (final entry in ordered) entry.declaration];
  }

  /// 精确验证单个桶，首次命中时才分配规则去重表。
  Map<CssRule, int>? _collectMatches(
    List<_Candidate>? candidates,
    CssElement element,
    Map<CssRule, int>? matches,
  ) {
    if (candidates == null) return matches;
    for (final candidate in candidates) {
      if (!cssSelectorMatches(candidate.selector, element)) continue;
      final specificity = candidate.specificity;
      final found = matches ??= <CssRule, int>{};
      final previous = found[candidate.rule];
      if (previous == null || specificity > previous) {
        found[candidate.rule] = specificity;
      }
    }
    return matches;
  }
}

/// 带预先计算优先级的候选。
class _Candidate {
  /// 记录规则及其选择器。
  _Candidate(this.rule, this.selector) : specificity = selector.specificity;

  /// 所属规则。
  final CssRule rule;

  /// 匹配条件。
  final CssSelector selector;

  /// 构建时计算的优先级。
  final int specificity;
}

/// 声明的完整排序键。
class _OrderedDeclaration {
  /// 创建排序项。
  const _OrderedDeclaration(
    this.declaration,
    this.inline,
    this.specificity,
    this.order,
    this.position,
  );

  /// 原始声明。
  final CssDeclaration declaration;

  /// 是否行内样式。
  final bool inline;

  /// 选择器优先级。
  final int specificity;

  /// 规则源码次序。
  final int order;

  /// 声明源码次序。
  final int position;
}

/// 按重要性、来源、优先级和源码次序比较。
int _compareDeclarations(_OrderedDeclaration a, _OrderedDeclaration b) {
  var result = (a.declaration.important ? 1 : 0).compareTo(
    b.declaration.important ? 1 : 0,
  );
  if (result != 0) return result;
  result = (a.inline ? 1 : 0).compareTo(b.inline ? 1 : 0);
  if (result != 0) return result;
  result = a.specificity.compareTo(b.specificity);
  if (result != 0) return result;
  result = a.order.compareTo(b.order);
  return result != 0 ? result : a.position.compareTo(b.position);
}

/// 层叠后的分流结果；参数分别提供表现属性、保留属性及动画列表。
///
/// ```dart
/// final empty = CssComputed.empty;
/// print(empty.attributes.isEmpty);
/// ```
class CssComputed {
  /// 创建分流结果。
  const CssComputed(this.attributes, this.properties, this.animations);

  /// 覆盖到 SVG 属性表的值。
  final Map<String, String> attributes;

  /// 后续阶段消费的 CSS 专用属性。
  final Map<String, String> properties;

  /// 保留简写和长写层叠语义的动画。
  final List<CssAnimation> animations;

  /// 未命中时复用的空结果。
  static const empty = CssComputed({}, {}, []);
}

/// 只供后续阶段消费的属性。
const _cssOnly = {
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
};

/// 暂不支持的全局值。
const _globalValues = {'initial', 'unset', 'revert', 'revert-layer', 'inherit'};

/// 不支持的值函数。
final _unsupportedFunction = RegExp(r'(var|env)\(', caseSensitive: false);

/// calc 不在本引擎支持范围，按解析期非法声明忽略。
final _calcFunction = RegExp(r'calc\(', caseSensitive: false);

/// 自定义属性的逗号回退不求值，保留此前有效声明。
final _varWithFallback = RegExp(
  r'var\(\s*--[^,\s()]+\s*,',
  caseSensitive: false,
);

/// 可去掉单位的完整像素数值。
final _pixels = RegExp('^($numberSyntax)px\$');

/// 动画简写名称。
const _animation = 'animation';

/// 动画长写前缀。
const _animationPrefix = 'animation-';

/// 对 [element] 查询 [index] 并合并 [inline]，返回分流结果。
///
/// ```dart
/// CssComputed styleFor(CssElement element) {
///   final index = CssRuleIndex(parseCssStylesheet('* {fill:#f00}'));
///   return computeCssStyle(index, element, const []);
/// }
/// ```
CssComputed computeCssStyle(
  CssRuleIndex index,
  CssElement element,
  List<CssDeclaration> inline,
) {
  final declarations = index.cascade(element, inline: inline);
  if (declarations.isEmpty) return CssComputed.empty;
  Map<String, String>? attributes, properties;
  List<CssDeclaration>? animations;
  for (final declaration in declarations) {
    final property = declaration.property;
    final value = declaration.value;
    if (_calcFunction.hasMatch(value) || _varWithFallback.hasMatch(value)) {
      continue;
    }
    if (property.startsWith('transition') ||
        property.startsWith('--') ||
        _globalValues.contains(value.toLowerCase()) ||
        _unsupportedFunction.hasMatch(value)) {
      attributes?.remove(property);
      properties?.remove(property);
      animations?.removeWhere(
        (d) => property == _animation
            ? d.property == _animation ||
                  d.property.startsWith(_animationPrefix)
            : d.property == property,
      );
      continue;
    }
    if (property == _animation || property.startsWith(_animationPrefix)) {
      (animations ??= []).add(declaration);
    } else if (_cssOnly.contains(property)) {
      (properties ??= {})[property] = value;
    } else {
      (attributes ??= {})[property] =
          _pixels.firstMatch(value)?.group(1) ?? value;
    }
  }
  if (attributes == null && properties == null && animations == null) {
    return CssComputed.empty;
  }
  return CssComputed(
    attributes ?? const {},
    properties ?? const {},
    animations == null ? const [] : parseCssAnimations(animations),
  );
}

/// 元素标识属性名。
const _idAttribute = 'id';

/// 类名属性名。
const _classAttribute = 'class';
