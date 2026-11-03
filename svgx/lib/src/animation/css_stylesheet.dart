import 'css_chars.dart';

/// 一条保留原始值文本的声明。
class CssDeclaration {
  /// 创建声明。
  const CssDeclaration(this.property, this.value, {this.important = false});

  /// 属性名，普通属性统一为小写。
  final String property;

  /// 去掉注释、首尾空白及重要标记的值。
  final String value;

  /// 是否包含重要标记。
  final bool important;
}

/// 相邻复合选择器的关系。
enum CssCombinator {
  /// 任意层级后代。
  descendant,

  /// 直接子代。
  child,
}

/// 同一元素需要同时满足的选择条件。
class CssCompoundSelector {
  /// 创建复合选择器。
  const CssCompoundSelector({this.tag, this.id, this.classes = const []});

  /// 类型名，空值表示不限类型。
  final String? tag;

  /// 元素标识。
  final String? id;

  /// 类名集合。
  final List<String> classes;
}

/// 支持后代和子代关系的选择器。
class CssSelector {
  /// 创建选择器。
  const CssSelector(this.compounds, this.combinators);

  /// 从左到右排列的复合条件。
  final List<CssCompoundSelector> compounds;

  /// 每对相邻条件之间的关系。
  final List<CssCombinator> combinators;

  /// 标识、类及类型分别占据三个字节的优先级。
  int get specificity {
    var ids = 0, classes = 0, tags = 0;
    for (final part in compounds) {
      if (part.id != null) ids++;
      classes += part.classes.length;
      if (part.tag != null) tags++;
    }
    return (ids << 16) | (classes << 8) | tags;
  }
}

/// 一条普通样式规则。
class CssRule {
  /// 创建规则。
  const CssRule(this.selectors, this.declarations, this.order);

  /// 规则支持的选择器。
  final List<CssSelector> selectors;

  /// 按源码顺序保留的声明。
  final List<CssDeclaration> declarations;

  /// 保留的普通规则在源码中的序号。
  final int order;
}

/// 一个归一化时间点上的关键帧声明。
class CssKeyframeStop {
  /// 创建关键帧。
  const CssKeyframeStop(this.offset, this.declarations);

  /// 零到一之间的时间位置。
  final double offset;

  /// 同位置声明按源码顺序拼接。
  final List<CssDeclaration> declarations;
}

/// 一个具名关键帧集合。
class CssKeyframes {
  /// 创建关键帧集合。
  const CssKeyframes(this.name, this.stops);

  /// 区分大小写的动画名。
  final String name;

  /// 按位置升序排列且位置不重复的关键帧。
  final List<CssKeyframeStop> stops;
}

/// 与渲染及层叠计算无关的样式表。
class CssStylesheet {
  /// 创建样式表。
  const CssStylesheet(this.rules, this.keyframes);

  /// 按源码顺序排列的普通规则。
  final List<CssRule> rules;

  /// 后出现的同名定义覆盖前者。
  final Map<String, CssKeyframes> keyframes;
}

/// 解析样式表全文，畸形或截断的输入保留已经读到的结果。
///
/// 参数 [source] 是样式标签内的文本，可包含注释或兼容包裹标记。
/// 返回只含支持的选择器、普通规则及关键帧的样式表，不抛解析异常。
///
/// ```dart
/// final sheet = parseCssStylesheet('#dot { opacity: .5 }');
/// print(sheet.rules.first.declarations.first.value);
/// ```
CssStylesheet parseCssStylesheet(String source) {
  final reader = _Reader(_clean(source));
  final rules = <CssRule>[];
  final keyframes = <String, CssKeyframes>{};
  while (reader.skipSpace()) {
    final header = reader.until(_ruleDelimiters).trim();
    if (reader.end) break;
    final delimiter = reader.take();
    if (delimiter != _openBrace) continue;
    final body = reader.block();
    if (header.startsWith('@')) {
      final at = _Reader(header);
      at.take();
      final keyword = at.identifier().toLowerCase();
      if (!_keyframeKeywords.contains(keyword)) continue;
      at.skipSpace();
      final name = at.name();
      if (name == null || !at.endAfterSpace) continue;
      keyframes[name] = _parseKeyframes(name, body);
    } else {
      final selectors = <CssSelector>[];
      for (final text in _splitSelectors(header)) {
        final selector = _parseSelector(text);
        if (selector != null) selectors.add(selector);
      }
      if (selectors.isNotEmpty) {
        rules.add(CssRule(selectors, _declarations(body), rules.length));
      }
    }
  }
  return CssStylesheet(rules, keyframes);
}

/// 解析行内样式或声明块，忽略格式错误的声明。
///
/// 参数 [source] 是不包含外层花括号的声明文本。
/// 返回按源码顺序排列的声明，保留值内部空白，不抛解析异常。
///
/// ```dart
/// final declarations = parseCssDeclarations('opacity: .5 !important');
/// print(declarations.single.important);
/// ```
List<CssDeclaration> parseCssDeclarations(String source) =>
    _declarations(_clean(source));

/// 识别支持的关键帧规则名。
const _keyframeKeywords = {
  'keyframes',
  '-webkit-keyframes',
  '-moz-keyframes',
  '-o-keyframes',
  '-ms-keyframes',
};

/// 扫描使用的字符编码。
const _lf = 10,
    _cr = 13,
    _slash = 47,
    _star = 42,
    _escape = 92,
    _single = 39,
    _double = 34,
    _openParen = 40,
    _closeParen = 41,
    _openBrace = 123,
    _closeBrace = 125,
    _openBracket = 91,
    _closeBracket = 93,
    _hash = 35,
    _dot = 46,
    _child = 62;

/// 单遍剥离字符串外的注释及兼容包裹标记。
String _clean(String source) {
  final out = StringBuffer();
  var i = 0, quote = 0;
  while (i < source.length) {
    final c = source.codeUnitAt(i);
    if (c == _escape && i + 1 < source.length) {
      out.write(source.substring(i, i + 2));
      i += 2;
      continue;
    }
    if (quote != 0) {
      out.writeCharCode(c);
      if (c == quote) quote = 0;
      i++;
      continue;
    }
    if (c == _single || c == _double) quote = c;
    if (c == _slash &&
        i + 1 < source.length &&
        source.codeUnitAt(i + 1) == _star) {
      final end = source.indexOf('*/', i + 2);
      i = end < 0 ? source.length : end + 2;
      continue;
    }
    var markerLength = 0;
    for (final marker in const ['<!--', '-->', '<![CDATA[', ']]>']) {
      if (source.startsWith(marker, i)) {
        markerLength = marker.length;
        break;
      }
    }
    if (markerLength != 0) {
      i += markerLength;
    } else {
      out.writeCharCode(c);
      i++;
    }
  }
  return out.toString();
}

/// 持有单向移动位置的词法扫描器。
class _Reader {
  /// 创建扫描器。
  _Reader(this.source);

  /// 当前扫描文本。
  final String source;

  /// 下一个字符的位置。
  int index = 0;

  /// 是否抵达末尾。
  bool get end => index >= source.length;

  /// 当前字符，末尾为负数。
  int get current => end ? -1 : source.codeUnitAt(index);

  /// 跳过空白后是否抵达末尾。
  bool get endAfterSpace => !skipSpace();

  /// 读取一个字符。
  int take() => end ? -1 : source.codeUnitAt(index++);

  /// 跳过空白并返回是否还有字符。
  bool skipSpace() {
    while (!end && isCssSpace(current)) {
      index++;
    }
    return !end;
  }

  /// 解码一个转义，位置须位于反斜杠。
  String escape() {
    index++;
    if (end) return '';
    var value = 0, digits = 0;
    while (!end && digits < 6 && cssHexValue(current) >= 0) {
      value = value * 16 + cssHexValue(take());
      digits++;
    }
    if (digits == 0) return String.fromCharCode(take());
    if (!end && isCssSpace(current)) {
      final whitespace = take();
      if (whitespace == _cr && current == _lf) {
        index++;
      }
    }
    if (value == 0 ||
        value > 0x10ffff ||
        (value >= 0xd800 && value <= 0xdfff)) {
      value = 0xfffd;
    }
    return String.fromCharCode(value);
  }

  /// 读取并解码标识符。
  String identifier() {
    final out = StringBuffer();
    while (!end) {
      if (current == _escape) {
        out.write(escape());
      } else if (isCssNameChar(current)) {
        out.writeCharCode(take());
      } else {
        break;
      }
    }
    return out.toString();
  }

  /// 读取标识符或闭合的字符串名。
  String? name() {
    if (current != _single && current != _double) {
      final result = identifier();
      return result.isEmpty ? null : result;
    }
    final quote = take();
    final out = StringBuffer();
    while (!end && current != quote) {
      if (current == _escape) {
        out.write(escape());
      } else {
        out.writeCharCode(take());
      }
    }
    if (end) return null;
    take();
    return out.toString();
  }

  /// 扫描到顶层分隔符，保留括号和引号内部的分隔符。
  String until(String delimiters) {
    final start = index;
    var parentheses = 0, brackets = 0, quote = 0;
    while (!end) {
      final c = current;
      if (c == _escape) {
        index++;
        if (!end) index++;
        continue;
      }
      if (quote != 0) {
        if (c == quote) quote = 0;
      } else if (c == _single || c == _double) {
        quote = c;
      } else if (parentheses == 0 &&
          brackets == 0 &&
          delimiters.contains(String.fromCharCode(c))) {
        break;
      } else if (c == _openParen) {
        parentheses++;
      } else if (c == _closeParen && parentheses > 0) {
        parentheses--;
      } else if (c == _openBracket) {
        brackets++;
      } else if (c == _closeBracket && brackets > 0) {
        brackets--;
      }
      index++;
    }
    return source.substring(start, index);
  }

  /// 读取左花括号之后的块体，跳过嵌套块。
  String block() {
    final start = index;
    var depth = 1;
    while (!end) {
      until('{}');
      if (end) break;
      final c = take();
      if (c == _openBrace) depth++;
      if (c == _closeBrace && --depth == 0) {
        return source.substring(start, index - 1);
      }
    }
    return source.substring(start, index);
  }
}

/// 拆开选择器列表，保留属性或字符串内部的逗号。
Iterable<String> _splitSelectors(String source) sync* {
  final reader = _Reader(source);
  while (!reader.end) {
    yield reader.until(',');
    if (!reader.end) reader.take();
  }
}

/// 解析一个受支持的选择器。
CssSelector? _parseSelector(String text) {
  final reader = _Reader(text);
  final compounds = <CssCompoundSelector>[];
  final combinators = <CssCombinator>[];
  reader.skipSpace();
  while (!reader.end) {
    String? tag, id;
    final classes = <String>[];
    if (reader.current == _star) {
      reader.take();
    } else if (isCssNameChar(reader.current) || reader.current == _escape) {
      tag = reader.identifier();
    } else if (reader.current != _hash && reader.current != _dot) {
      return null;
    }
    while (reader.current == _hash || reader.current == _dot) {
      final kind = reader.take();
      final name = reader.identifier();
      if (name.isEmpty) return null;
      if (kind == _hash) {
        if (id != null) return null;
        id = name;
      } else {
        classes.add(name);
      }
    }
    compounds.add(CssCompoundSelector(tag: tag, id: id, classes: classes));
    final before = reader.index;
    reader.skipSpace();
    if (reader.end) break;
    if (reader.current == _child) {
      reader.take();
      reader.skipSpace();
      if (reader.end) return null;
      combinators.add(CssCombinator.child);
    } else if (reader.index > before) {
      combinators.add(CssCombinator.descendant);
    } else {
      return null;
    }
  }
  return compounds.isEmpty ? null : CssSelector(compounds, combinators);
}

/// 匹配声明末尾的重要标记。
final _important = RegExp(r'!\s*important\s*$', caseSensitive: false);

/// 解析已清理的声明文本。
List<CssDeclaration> _declarations(String source) {
  final reader = _Reader(source);
  final result = <CssDeclaration>[];
  while (reader.skipSpace()) {
    final text = reader.until(';}');
    if (!reader.end) reader.take();
    final colon = text.indexOf(':');
    if (colon < 0) continue;
    var property = text.substring(0, colon).trim();
    var value = text.substring(colon + 1).trim();
    if (property.isEmpty || value.isEmpty) continue;
    final propertyReader = _Reader(property);
    propertyReader.identifier();
    if (!propertyReader.end) continue;
    if (!property.startsWith('--')) property = property.toLowerCase();
    final match = _important.firstMatch(value);
    var important = false;
    if (match != null) {
      final prefix = _Reader(value);
      prefix.until(_importantMarker);
      // 只有顶层的末尾标记才具有优先级语义。
      while (!prefix.end && prefix.index < match.start) {
        prefix.take();
        prefix.until(_importantMarker);
      }
      if (prefix.index == match.start) {
        important = true;
        value = value.substring(0, match.start).trimRight();
      }
    }
    if (value.isNotEmpty) {
      result.add(CssDeclaration(property, value, important: important));
    }
  }
  return result;
}

/// 解析并合并同位置的关键帧。
CssKeyframes _parseKeyframes(String name, String body) {
  final reader = _Reader(body);
  final stops = <double, List<List<CssDeclaration>>>{};
  while (reader.skipSpace()) {
    final header = reader.until(_ruleDelimiters);
    if (reader.end) break;
    if (reader.take() != _openBrace) continue;
    final declarations = _declarations(reader.block());
    final blockOffsets = <double>{};
    for (final selector in _splitSelectors(header)) {
      final token = selector.trim().toLowerCase();
      double? offset;
      if (token == 'from') {
        offset = 0;
      } else if (token == 'to') {
        offset = 1;
      } else if (token.endsWith('%')) {
        final number = token.substring(0, token.length - 1);
        if (_percentage.hasMatch(number)) {
          final value = double.tryParse(number);
          if (value != null && value >= 0 && value <= 100) offset = value / 100;
        }
      }
      if (offset != null) blockOffsets.add(offset);
    }
    for (final offset in blockOffsets) {
      (stops[offset] ??= []).add(declarations);
    }
  }
  final offsets = stops.keys.toList()..sort();
  return CssKeyframes(name, [
    for (final offset in offsets)
      CssKeyframeStop(
        offset,
        stops[offset]!.length == 1
            ? stops[offset]!.single
            : [for (final group in stops[offset]!) ...group],
      ),
  ]);
}

/// 百分数允许的十进制形式。
final _percentage = RegExp(r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$');

/// 规则头部的结束符：块开始、语句结束、块结束。
const _ruleDelimiters = '{;}';

/// 声明值里重要标记的起始符。
const _importantMarker = '!';
