import 'dart:io';

/// Checks exact file/group/test references without an analyzer dependency.
/// 无分析器依赖，校验精确的文件/group/test 引用。
/// This small lexer supports the repository's literal names and literal-list
/// parameterized tests; unsupported dynamic names fail explicitly.
/// 轻量词法器支持仓库的字面量名称及字面量列表参数化测试；不支持的动态名称明确失败。
void main(List<String> args) {
  final matrixPath = args
          .where((arg) => arg.startsWith('--matrix='))
          .map((arg) => arg.substring('--matrix='.length))
          .firstOrNull ??
      'test/ACCEPTANCE.md';
  final registrations = <String>{};
  try {
    for (final file in Directory('test')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('_test.dart'))) {
      registrations.addAll(testNames(file));
    }
    final matrix = File(matrixPath).readAsStringSync();
    final references = RegExp(r'`(test/[^`\n]+\.dart :: [^`\n]+)`')
        .allMatches(matrix)
        .map((match) => match[1]!)
        .toList();
    final missing =
        references.where((ref) => !registrations.contains(ref)).toSet();
    final unmapped = registrations.difference(references.toSet());
    for (final ref in missing) {
      stderr.writeln('MISSING / 不存在: $ref');
    }
    for (final ref in unmapped) {
      stderr.writeln('UNMAPPED / 矩阵未引用: $ref');
    }
    if (references.isEmpty || missing.isNotEmpty || unmapped.isNotEmpty) {
      stderr.writeln('FAIL: acceptance references / 验收引用校验失败');
      exitCode = 1;
    } else {
      stdout.writeln('PASS: ${references.length} references resolve; '
          '${registrations.length} registered tests all mapped. / 全部测试引用有效且无遗漏');
    }
  } catch (error) {
    stderr.writeln('FAIL: $error');
    exitCode = 1;
  }
}

/// Extracts names while tracking group body depth and ignoring strings/comments.
/// 跟踪 group 函数体深度，忽略字符串与注释中的括号。
Set<String> testNames(File file) {
  final source = file.readAsStringSync();
  final path = file.path.replaceAll('\\', '/');
  final lexemes = RegExp(
      r'''//[^\n]*|/\*[\s\S]*?\*/|'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*"|[a-zA-Z_$][\w$]*|[^\s]''');
  final tokens = lexemes
      .allMatches(source)
      .map((m) => m[0]!)
      .where((token) => !token.startsWith('//') && !token.startsWith('/*'))
      .toList();
  final parameters = <String, List<String>>{};
  for (final loop in RegExp(r'for\s*\(\s*final\s+(\w+)\s+in\s+\[([^\]]+)\]')
      .allMatches(source)) {
    parameters[loop[1]!] = loop[2]!.split(',').map((v) => v.trim()).toList();
  }
  final bodies = <int, String>{};
  final groups = <(String, int)>[];
  final names = <String>{};
  var depth = 0;
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    if (token == '{') {
      depth++;
      final group = bodies[i];
      if (group != null) groups.add((group, depth));
    } else if (token == '}') {
      if (groups.isNotEmpty && groups.last.$2 == depth) groups.removeLast();
      depth--;
    }
    if (!['group', 'test', 'testWidgets'].contains(token) ||
        i + 2 >= tokens.length ||
        tokens[i + 1] != '(') {
      continue;
    }
    final literal = tokens[i + 2];
    if (!literal.startsWith("'") && !literal.startsWith('"')) {
      throw FormatException('Nonliteral test/group name / 非字面量名称: $path');
    }
    final name = literal
        .substring(1, literal.length - 1)
        .replaceAllMapped(RegExp(r'\\(.)'), (match) => match[1]!);
    if (token == 'group') {
      final body = tokens.indexOf('{', i + 3);
      if (body < 0) throw FormatException('Missing group body: $path :: $name');
      bodies[body] = name;
    } else {
      final full = [...groups.map((g) => g.$1), name].join(' > ');
      names.addAll(_expand(full, parameters).map((value) => '$path :: $value'));
    }
  }
  return names;
}

/// Expands literal loop parameters such as synchronous=false/true.
/// 展开同步标记等字面量循环参数。
Iterable<String> _expand(String name, Map<String, List<String>> parameters) {
  var names = [name];
  for (final variable in RegExp(r'\$\{(\w+)\}|\$(\w+)').allMatches(name)) {
    final key = variable[1] ?? variable[2]!;
    final values = parameters[key];
    if (values == null) {
      throw FormatException('Unknown test name parameter: $key');
    }
    names = [
      for (final name in names)
        for (final value in values) name.replaceAll(variable[0]!, value)
    ];
  }
  return names;
}
