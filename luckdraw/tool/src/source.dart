/// 门禁共用的无依赖源码词法工具。
library;

/// Dart 库声明指令。
const String kLibraryDirective = 'library';

/// Dart 导入指令。
const String kImportDirective = 'import';

/// Dart 导出指令。
const String kExportDirective = 'export';

/// Dart 分部指令。
const String kPartDirective = 'part';

/// 覆盖率检查可忽略的库级指令。
const Set<String> kDartDirectives = {
  kLibraryDirective,
  kImportDirective,
  kExportDirective,
  kPartDirective
};

/// 验收矩阵相对包根路径。
const String kAcceptanceMatrixPath = 'test/ACCEPTANCE.md';

/// Dart 源码文件的后缀。
const String kDartFileExtension = '.dart';

/// 单行注释的前缀。
const String kLineCommentPrefix = '//';

/// 块注释的前缀。
const String kBlockCommentPrefix = '/*';

/// 一个保留源码位置的词元。
class SourceToken {
  /// 使用原文 [text] 和字符偏移 [offset] 创建词元。
  const SourceToken(this.text, this.offset, {this.interpolations = const []});

  /// 未解码的原文。
  final String text;

  /// 在源码中的字符偏移。
  final int offset;

  /// 字符串内实际求值的表达式词元；纯文本和原始字符串为空。
  final List<SourceToken> interpolations;

  /// 是否为字符串字面量。
  bool get isString => RegExp(r'''^[rR]?['"]''').hasMatch(text);

  /// 是否为源码中的真实注释，而非字符串内容。
  bool get isComment =>
      text.startsWith(kLineCommentPrefix) ||
      text.startsWith(kBlockCommentPrefix);

  /// 按 Dart 转义规则解码内容；非法转义明确失败。
  String get value {
    final raw = text.startsWith('r') || text.startsWith('R');
    final literal = raw ? text.substring(1) : text;
    final width = literal.startsWith(literal[0] * 3) ? 3 : 1;
    final body = literal.substring(width, literal.length - width);
    if (raw) return body;
    final result = StringBuffer();
    for (var i = 0; i < body.length; i++) {
      if (body[i] != r'\') {
        result.write(body[i]);
        continue;
      }
      if (++i == body.length) throw const FormatException('字符串转义未完成');
      final escape = body[i];
      const escapes = {
        'n': '\n',
        'r': '\r',
        't': '\t',
        'b': '\b',
        'f': '\f',
        'v': '\v',
        "'": "'",
        '"': '"',
        r'\': r'\',
        r'$': r'$'
      };
      if (escapes.containsKey(escape)) {
        result.write(escapes[escape]);
      } else if (escape == 'x' || escape == 'u') {
        final braced =
            escape == 'u' && i + 1 < body.length && body[i + 1] == '{';
        final start = i + (braced ? 2 : 1);
        final end =
            braced ? body.indexOf('}', start) : start + (escape == 'x' ? 2 : 4);
        if (end < start || end > body.length) {
          throw const FormatException('Unicode 转义未完成');
        }
        final digits = body.substring(start, end);
        final value = int.tryParse(digits, radix: 16);
        if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(digits) ||
            value == null ||
            value > 0x10ffff ||
            braced && digits.length > 6) {
          throw const FormatException('Unicode 转义无效');
        }
        result.writeCharCode(value);
        i = braced ? end : end - 1;
      } else {
        throw FormatException('Dart 转义无效: $escape');
      }
    }
    return result.toString();
  }
}

/// 提取保留位置的 Dart 词元；支持嵌套注释、原始串、转义与插值。
///
/// [includeComments] 保留真实注释；[includeInterpolations] 将实际求值的表达式
/// 追加为括号包围的词元，供规则检查；不完整词法结构抛出 [FormatException]。
List<SourceToken> sourceTokens(String source,
    {bool includeComments = false, bool includeInterpolations = false}) {
  final tokens = _SourceScanner(source, includeComments).scan();
  if (!includeInterpolations) return tokens;

  /// 递归保留嵌套字符串内的求值表达式。
  Iterable<SourceToken> expand(List<SourceToken> input) sync* {
    for (final token in input) {
      yield token;
      if (token.interpolations.isNotEmpty) {
        yield SourceToken('(', token.offset);
        yield* expand(token.interpolations);
        yield SourceToken(')', token.offset);
      }
    }
  }

  return expand(tokens).toList();
}

/// 扫描单份源码，所有嵌套结构共享字符偏移。
final class _SourceScanner {
  /// 保存原文与注释策略。
  _SourceScanner(this.source, this.includeComments);

  /// 待扫描原文。
  final String source;

  /// 是否保留注释词元。
  final bool includeComments;

  /// 下一个字符偏移。
  int offset = 0;

  /// 扫描代码；插值模式在与起点匹配的右花括号前结束。
  List<SourceToken> scan({bool interpolation = false}) {
    final result = <SourceToken>[];
    var braces = 0;
    while (offset < source.length) {
      final start = offset;
      final char = source[offset];
      if (interpolation && char == '}' && braces == 0) return result;
      if (RegExp(r'\s').hasMatch(char)) {
        offset++;
        continue;
      }
      if (source.startsWith(kLineCommentPrefix, offset)) {
        final end = source.indexOf('\n', offset);
        offset = end < 0 ? source.length : end;
        if (includeComments) {
          result.add(SourceToken(source.substring(start, offset), start));
        }
        continue;
      }
      if (source.startsWith(kBlockCommentPrefix, offset)) {
        offset += 2;
        var depth = 1;
        while (offset < source.length && depth > 0) {
          if (source.startsWith(kBlockCommentPrefix, offset)) {
            depth++;
            offset += 2;
          } else if (source.startsWith('*/', offset)) {
            depth--;
            offset += 2;
          } else {
            offset++;
          }
        }
        if (depth != 0) throw const FormatException('块注释未闭合');
        if (includeComments) {
          result.add(SourceToken(source.substring(start, offset), start));
        }
        continue;
      }
      final raw = (char == 'r' || char == 'R') &&
          offset + 1 < source.length &&
          _quote(source[offset + 1]);
      if (_quote(char) || raw) {
        result.add(_string(raw));
        continue;
      }
      if (RegExp(r'[a-zA-Z_$]').hasMatch(char)) {
        offset++;
        while (offset < source.length &&
            RegExp(r'[\w$]').hasMatch(source[offset])) {
          offset++;
        }
      } else if (RegExp(r'\d').hasMatch(char)) {
        offset++;
        while (offset < source.length &&
            RegExp(r'[\d.]').hasMatch(source[offset])) {
          offset++;
        }
      } else {
        if (char == '{') braces++;
        if (char == '}') braces--;
        offset++;
      }
      result.add(SourceToken(source.substring(start, offset), start));
    }
    if (interpolation) throw const FormatException('字符串插值未闭合');
    return result;
  }

  /// 是否为 Dart 字符串引号。
  bool _quote(String char) => char == "'" || char == '"';

  /// 扫描完整字符串及其中实际执行的插值表达式。
  SourceToken _string(bool raw) {
    final start = offset;
    if (raw) offset++;
    final quote = source[offset];
    final delimiter = source.startsWith(quote * 3, offset) ? quote * 3 : quote;
    offset += delimiter.length;
    final expressions = <SourceToken>[];
    while (offset < source.length) {
      if (source.startsWith(delimiter, offset)) {
        offset += delimiter.length;
        return SourceToken(source.substring(start, offset), start,
            interpolations: expressions);
      }
      if (!raw && source[offset] == r'\') {
        offset += 2;
        continue;
      }
      if (!raw && source[offset] == r'$') {
        offset++;
        if (offset < source.length && source[offset] == '{') {
          offset++;
          final startExpression = offset;
          expressions.add(SourceToken('(', startExpression));
          expressions.addAll(scan(interpolation: true));
          expressions.add(SourceToken(')', offset));
          offset++;
        } else {
          final startExpression = offset;
          while (offset < source.length &&
              RegExp(r'[\w$]').hasMatch(source[offset])) {
            offset++;
          }
          if (startExpression == offset) throw const FormatException('字符串插值无效');
          expressions.add(SourceToken(
              source.substring(startExpression, offset), startExpression));
        }
        continue;
      }
      if (delimiter.length == 1 &&
          (source[offset] == '\n' || source[offset] == '\r')) {
        throw const FormatException('单行字符串未闭合');
      }
      offset++;
    }
    throw const FormatException('字符串未闭合');
  }
}

/// 将 [path] 的反斜杠和点路径归一化为斜杠路径。
String normalizePath(String path) {
  final parts = <String>[];
  for (final part in path.replaceAll('\\', '/').split('/')) {
    if (part == '.' || part.isEmpty) continue;
    if (part == '..' && parts.isNotEmpty && parts.last != '..') {
      parts.removeLast();
    } else {
      parts.add(part);
    }
  }
  return parts.join('/');
}

/// 返回 [offset] 所在的一基行号。
int sourceLine(String source, int offset) =>
    '\n'.allMatches(source.substring(0, offset)).length + 1;

/// 读取 [root] 下的 Dart 源码是否只包含注释和库指令。
bool isDirectiveOnly(String root) {
  final tokens = sourceTokens(root);
  var i = 0;
  while (i < tokens.length) {
    if (!kDartDirectives.contains(tokens[i].text)) {
      return false;
    }
    while (i < tokens.length && tokens[i].text != ';') {
      i++;
    }
    if (i == tokens.length) return false;
    i++;
  }
  return true;
}
