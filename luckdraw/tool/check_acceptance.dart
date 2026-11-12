import 'dart:convert';
import 'dart:io';

import 'src/source.dart';

/// 测试注册文件的后缀。
const String _testSuffix = '_test.dart';

/// 测试分组的函数名。
const String _groupFunction = 'group';

/// 支持的测试注册函数名称。
const Set<String> _testFunctions = {_groupFunction, 'test', 'testWidgets'};

/// 可注册测试的目录；缺失的目录不会被扫描。
const List<String> kTestRoots = [
  'test/',
  'example/integration_test/',
  'tool/bench/integration_test/',
];

/// 验收矩阵检查结果。
class AcceptanceCheck {
  /// 使用错误、注册集合和引用数量构造结论。
  const AcceptanceCheck(this.errors, this.registrations, this.referenceCount);

  /// 中英双语的错误信息。
  final List<String> errors;

  /// 未跳过的完整测试名。
  final Set<String> registrations;

  /// 矩阵内测试与命令引用的数量。
  final int referenceCount;
}

/// 轻量词法器提取的测试集合。
class TestRegistration {
  /// 使用正常测试和跳过测试构造集合。
  const TestRegistration(this.active, this.skipped);

  /// 应被矩阵引用的测试。
  final Set<String> active;

  /// 不得被矩阵引用的测试。
  final Set<String> skipped;
}

/// 返回括号词元 [start] 配对的位置；格式不完整时抛出异常。
int _closing(List<SourceToken> tokens, int start) {
  const pairs = {'(': ')', '[': ']', '{': '}'};
  final stack = <String>[];
  for (var i = start; i < tokens.length; i++) {
    final text = tokens[i].text;
    if (pairs.containsKey(text)) {
      stack.add(pairs[text]!);
    } else if (pairs.containsValue(text)) {
      if (stack.isEmpty || stack.removeLast() != text) {
        throw const FormatException('括号不匹配');
      }
      if (stack.isEmpty) return i;
    }
  }
  throw const FormatException('括号未闭合');
}

/// 展开名称中的字面量列表变量；未知插值明确失败。
List<String> _expand(String name, Map<String, List<String>> parameters) {
  var values = [name];
  for (final match in RegExp(r'\$\{(\w+)\}|\$(\w+)').allMatches(name)) {
    final key = match[1] ?? match[2]!;
    final options = parameters[key];
    if (options == null) {
      throw FormatException('Unknown test name parameter: $key');
    }
    values = [
      for (final value in values)
        for (final option in options) value.replaceAll(match[0]!, option),
    ];
  }
  if (values.any((v) => v.contains(r'$'))) {
    throw const FormatException('Unsupported interpolation / 不支持的插值');
  }
  return values;
}

/// 从 [source] 提取 [path] 的测试，跟踪嵌套 group、字面量循环及 skip。
///
/// 非字面量名称、不支持的参数表达式、重复循环变量会抛出 [FormatException]。
TestRegistration testNames(String path, String source) {
  final scanner = _RegistrationScanner(path, sourceTokens(source));
  scanner.scan(0, scanner.tokens.length, const [], const {}, false);
  return TestRegistration(scanner.active, scanner.skipped);
}

/// 只遍历 main、group 和真正包含测试注册的字面量循环。
final class _RegistrationScanner {
  /// 保存路径与已排除字符串内容的词元。
  _RegistrationScanner(this.path, this.tokens);

  /// 当前测试文件。
  final String path;

  /// 保留位置的源码词元。
  final List<SourceToken> tokens;

  /// 正常注册名。
  final Set<String> active = {};

  /// 跳过的注册名。
  final Set<String> skipped = {};

  /// 仅测试注册循环需要全文件唯一的变量名。
  final Set<String> loopVariables = {};

  /// 完整测试文件必须从 main 开始注册；无 main 的字面片段仅供快速词法测试。
  bool get _hasMain => tokens.any((token) => token.text == 'main');

  /// 判断真实注册调用，忽略对象成员与纯字符串。
  bool _call(int i) =>
      i + 1 < tokens.length &&
      _testFunctions.contains(tokens[i].text) &&
      tokens[i + 1].text == '(' &&
      (i == 0 || tokens[i - 1].text != '.');

  /// 判断区间是否包含真实注册调用。
  bool _containsCall(int start, int end) {
    for (var i = start; i < end; i++) {
      if (_call(i)) return true;
    }
    return false;
  }

  /// 在注册作用域内递归解析名称；测试回调体中的普通循环无需解析。
  void scan(int start, int end, List<String> groups,
      Map<String, List<String>> parameters, bool skip,
      {bool registrationScope = false}) {
    for (var i = start; i < end; i++) {
      final token = tokens[i].text;
      if (token == 'main' && i + 1 < end && tokens[i + 1].text == '(') {
        final body = _closing(tokens, i + 1) + 1;
        if (body < end && tokens[body].text == 'async') i = body;
        final open =
            body < end && tokens[body].text == 'async' ? body + 1 : body;
        if (open < end && tokens[open].text == '{') {
          final close = _closing(tokens, open);
          scan(open + 1, close, groups, parameters, skip,
              registrationScope: true);
          i = close;
          continue;
        }
      }
      if (_call(i)) {
        if (!registrationScope &&
            (_hasMain || i > 0 && tokens[i - 1].text == '>')) {
          throw FormatException(
              'Registration outside main/group / 注册不在 main 或 group 作用域: $path');
        }
        final close = _closing(tokens, i + 1);
        final literal = tokens[i + 2];
        if (!literal.isString || i + 3 >= close || tokens[i + 3].text != ',') {
          throw FormatException('Nonliteral test/group name / 非字面量名称: $path');
        }
        var skippedHere = skip;
        int? body;
        for (var j = i + 4; j < close; j++) {
          if (const {'(', '[', '{'}.contains(tokens[j].text)) {
            if (tokens[j].text == '{') body ??= j;
            j = _closing(tokens, j);
          } else if (tokens[j].text == 'skip' &&
              j + 3 <= close &&
              tokens[j + 1].text == ':') {
            skippedHere |=
                !const {'false', 'null'}.contains(tokens[j + 2].text) ||
                    !const {',', ')'}.contains(tokens[j + 3].text);
          }
        }
        if (token == _groupFunction) {
          if (body == null) {
            throw FormatException('Unsupported group callback: $path');
          }
          scan(body + 1, _closing(tokens, body), [...groups, literal.value],
              parameters, skippedHere,
              registrationScope: true);
        } else {
          if (_containsCall(i + 4, close)) {
            throw FormatException(
                'Registration outside main/group / 注册不在 main 或 group 作用域: $path');
          }
          final name = [...groups, literal.value].join(' > ');
          for (final expanded in _expand(name, parameters)) {
            final full = '$path :: $expanded';
            if (active.contains(full) || skipped.contains(full)) {
              throw FormatException('Duplicate test / 测试名重复: $full');
            }
            (skippedHere ? skipped : active).add(full);
          }
        }
        i = close;
        continue;
      }
      if (token == 'for' && i + 1 < end && tokens[i + 1].text == '(') {
        final conditionEnd = _closing(tokens, i + 1);
        final body = conditionEnd + 1;
        if (body >= end || tokens[body].text != '{') {
          if (_containsCall(body, end)) {
            throw FormatException('Unsupported registration loop: $path');
          }
          continue;
        }
        final close = _closing(tokens, body);
        if (!_containsCall(body + 1, close)) {
          i = close;
          continue;
        }
        if (i + 5 >= conditionEnd ||
            tokens[i + 2].text != 'final' ||
            tokens[i + 4].text != 'in' ||
            tokens[i + 5].text != '[') {
          throw FormatException('Nonliteral parameter / 非字面量参数: $path');
        }
        final key = tokens[i + 3].text;
        if (!loopVariables.add(key)) {
          throw FormatException('Duplicate loop variable: $path :: $key');
        }
        final listEnd = _closing(tokens, i + 5);
        if (listEnd != conditionEnd - 1) {
          throw FormatException('Nonliteral parameter: $path');
        }
        final values = <String>[];
        var expectValue = true;
        for (var j = i + 6; j < listEnd; j++) {
          final value = tokens[j];
          if (!expectValue && value.text == ',') {
            expectValue = true;
          } else if (expectValue &&
              (value.isString ||
                  RegExp(r'^(true|false|null|\d+(\.\d+)?)$')
                      .hasMatch(value.text))) {
            values.add(value.isString ? value.value : value.text);
            expectValue = false;
          } else {
            throw FormatException('Nonliteral parameter / 非字面量参数: $path');
          }
        }
        scan(body + 1, close, groups, {...parameters, key: values}, skip,
            registrationScope: registrationScope);
        i = close;
        continue;
      }
      if (token == '{') {
        final close = _closing(tokens, i);
        if (_containsCall(i + 1, close)) {
          throw FormatException(
              'Registration outside main/group / 注册不在 main 或 group 作用域: $path');
        }
        i = close;
      }
    }
  }
}

/// 从完整且成功的 Flutter JSON 运行记录提取实际完成、跳过的测试名。
///
/// [sourcePaths] 提供允许的测试文件；缺少完成事件、运行失败或未知文件均报错。
TestRegistration testNamesFromJson(String run, Iterable<String> sourcePaths) {
  final paths = sourcePaths.map(normalizePath).toSet();
  final suites = <int, String>{};
  final groups = <int, String>{};
  final tests = <int, Map<String, dynamic>>{};
  final completed = <int>{};
  final active = <String>{};
  final skipped = <String>{};
  var finished = false;
  for (final line in run
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)) {
    final event = jsonDecode(line) as Map<String, dynamic>;
    if (finished) throw const FormatException('INVALID RUN / done 之后仍有事件');
    switch (event['type']) {
      case 'suite':
        final suite = event['suite'] as Map<String, dynamic>;
        final raw = suite['path'] as String;
        final path = normalizePath(
            raw.startsWith('file:') ? Uri.parse(raw).toFilePath() : raw);
        final matches = paths
            .where((candidate) =>
                path == candidate || path.endsWith('/$candidate'))
            .toList();
        if (matches.length != 1) {
          throw FormatException('UNKNOWN SUITE / 未知测试文件: $path');
        }
        suites[suite['id'] as int] = matches.single;
      case 'group':
        final group = event['group'] as Map<String, dynamic>;
        groups[group['id'] as int] = group['name'] as String;
      case 'testStart':
        final test = event['test'] as Map<String, dynamic>;
        final id = test['id'] as int;
        if (tests.containsKey(id)) {
          throw FormatException('DUPLICATE TEST ID: $id');
        }
        tests[id] = test;
      case 'testDone':
        final id = event['testID'] as int;
        final test = tests[id];
        if (test == null || !completed.add(id)) {
          throw FormatException('UNKNOWN OR DUPLICATE TEST: $id');
        }
        if (event['hidden'] == true) continue;
        if (event['result'] != 'success' && event['skipped'] != true) {
          throw FormatException('FAILED TEST: ${test['name']}');
        }
        final path = suites[test['suiteID']];
        if (path == null) {
          throw const FormatException('UNKNOWN SUITE / 测试未关联文件');
        }
        final names = <String>[];
        var prefix = '';
        for (final id in (test['groupIDs'] as List<dynamic>? ?? const [])) {
          final full = groups[id];
          if (full == null) {
            throw const FormatException('UNKNOWN GROUP / 测试未关联分组');
          }
          if (full.isEmpty) continue;
          names.add(prefix.isNotEmpty && full.startsWith('$prefix ')
              ? full.substring(prefix.length + 1)
              : full);
          prefix = full;
        }
        final fullName = test['name'] as String;
        if (prefix.isNotEmpty && !fullName.startsWith('$prefix ')) {
          throw FormatException('INVALID GROUP NAME: $fullName');
        }
        names.add(
            prefix.isEmpty ? fullName : fullName.substring(prefix.length + 1));
        final reference = '$path :: ${names.join(' > ')}';
        if (active.contains(reference) || skipped.contains(reference)) {
          throw FormatException('Duplicate test / 测试名重复: $reference');
        }
        final metadata = test['metadata'] as Map<String, dynamic>?;
        (event['skipped'] == true || metadata?['skip'] == true
                ? skipped
                : active)
            .add(reference);
      case 'done':
        if (event['success'] != true) {
          throw const FormatException('FAILED RUN / 测试运行未成功');
        }
        finished = true;
    }
  }
  if (!finished || tests.length != completed.length) {
    throw const FormatException('INCOMPLETE RUN / 测试运行记录不完整');
  }
  final missingSuites = paths
      .where((path) => path.startsWith('test/'))
      .toSet()
      .difference(suites.values.toSet());
  if (missingSuites.isNotEmpty) {
    throw FormatException('UNRUN SUITE / 未运行测试文件: ${missingSuites.join(', ')}');
  }
  return TestRegistration(active, skipped);
}

/// 双向校验 [matrix] 与 [testSources]；命令脚本由 [fileExists] 判断是否存在。
///
/// 返回全部可诊断错误；缺失的测试目录无需提供任何条目。
AcceptanceCheck checkAcceptance({
  required String matrix,
  required Map<String, String> testSources,
  required bool Function(String path) fileExists,
  String? testRunJson,
}) {
  final errors = <String>[];
  final registrations = <String>{};
  final skipped = <String>{};
  if (testRunJson != null) {
    try {
      final runtime = testNamesFromJson(
          testRunJson,
          testSources.keys
              .where((path) => normalizePath(path).startsWith('test/')));
      registrations.addAll(runtime.active);
      skipped.addAll(runtime.skipped);
    } on FormatException catch (error) {
      errors.add('INVALID RUN / 测试运行无效: $error');
    }
  }
  for (final entry in testSources.entries) {
    final path = normalizePath(entry.key);
    if (!path.endsWith(_testSuffix) || !kTestRoots.any(path.startsWith)) {
      continue;
    }
    // 包内测试以实际运行结果为准；独立集成/基准工程仍由各自作业验收。
    if (testRunJson != null && path.startsWith('test/')) continue;
    try {
      final result = testNames(path, entry.value);
      registrations.addAll(result.active);
      skipped.addAll(result.skipped);
    } on FormatException catch (error) {
      errors.add('INVALID TEST / 测试注册无效: $error');
    }
  }
  final references = <String>{};
  final ids = <String>{};
  var referenceCount = 0;
  var inMatrix = false;
  for (final line in matrix.split('\n')) {
    if (line.startsWith('## ')) inMatrix = line.trim() == '## 需求和不变量';
    if (!inMatrix || !line.trimLeft().startsWith('|')) continue;
    final cells = line.split('|').map((s) => s.trim()).toList();
    if (cells.length < 8 ||
        cells[1] == 'ID' ||
        RegExp(r'^[-: ]+$').hasMatch(cells[1])) {
      continue;
    }
    final id = cells[1];
    if (!ids.add(id)) errors.add('DUPLICATE ID / 编号重复: $id');
    var count = 0;
    for (final match in RegExp(r'`([^`\n]+)`').allMatches(cells[4])) {
      final ref = match[1]!;
      if (ref.startsWith('cmd: ')) {
        count++;
        for (final script in RegExp(r'tool/[\w./-]+\.dart').allMatches(ref)) {
          if (!fileExists(script[0]!)) {
            errors.add('BAD CMD / 命令脚本不存在: ${script[0]}');
          }
        }
      } else if (ref.contains(' :: ')) {
        count++;
        references.add(ref);
        if (skipped.contains(ref)) {
          errors.add('SKIPPED / 不得引用跳过测试: $ref');
        } else if (!registrations.contains(ref)) {
          errors.add('MISSING / 不存在: $ref');
        }
      }
    }
    referenceCount += count;
    if (count == 0 && cells[5] != '人工') errors.add('EMPTY ROW / 无引用: $id');
  }
  if (ids.isEmpty) errors.add('EMPTY MATRIX / 验收矩阵为空');
  for (final ref in registrations.difference(references)) {
    errors.add('UNMAPPED / 矩阵未引用: $ref');
  }
  return AcceptanceCheck(errors, registrations, referenceCount);
}

/// 扫描实际测试目录并执行矩阵门禁。
void main(List<String> args) {
  try {
    final sources = <String, String>{};
    for (final root in kTestRoots) {
      if (!Directory(root).existsSync()) continue;
      for (final file in Directory(root)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith(_testSuffix))) {
        sources[normalizePath(file.path)] = file.readAsStringSync();
      }
    }
    final matrixPath = args
            .where((a) => a.startsWith('--matrix='))
            .firstOrNull
            ?.substring(9) ??
        kAcceptanceMatrixPath;
    final jsonOption = args.indexOf('--from-json');
    if (jsonOption >= 0 && jsonOption + 1 == args.length) {
      throw const FormatException('--from-json 需要文件路径');
    }
    final jsonPath = jsonOption >= 0
        ? args[jsonOption + 1]
        : args
            .where((arg) => arg.startsWith('--from-json='))
            .firstOrNull
            ?.substring('--from-json='.length);
    final result = checkAcceptance(
        matrix: File(matrixPath).readAsStringSync(),
        testSources: sources,
        fileExists: (path) => File(path).existsSync(),
        testRunJson:
            jsonPath == null ? null : File(jsonPath).readAsStringSync());
    for (final error in result.errors) {
      stderr.writeln(error);
    }
    if (result.errors.isNotEmpty) {
      stderr.writeln('FAIL: acceptance references / 验收引用校验失败');
      exitCode = 1;
    } else {
      stdout.writeln(
          'PASS: ${result.referenceCount} references resolve; ${result.registrations.length} registered tests all mapped. / 全部测试引用有效且无遗漏');
    }
  } on Object catch (error) {
    stderr.writeln('FAIL: $error');
    exitCode = 1;
  }
}
