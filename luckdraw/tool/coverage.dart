import 'dart:io';

import 'src/source.dart';

/// 百分比的比例因子。
const double _percentScale = 100;

/// lcov 源文件记录的前缀。
const String _sourcePrefix = 'SF:';

/// lcov 行命中记录的前缀。
const String _dataPrefix = 'DA:';

/// 包源码目录。
const String _libDirectory = 'lib';

/// 判断 [source] 是否仅含指令、顶层常量、类型别名或普通枚举。
///
/// 使用去注释的词元逐个检查完整声明；普通变量、类与函数均返回 false。
bool hasNoExecutableLines(String source) {
  final List<SourceToken> tokens;
  try {
    tokens = sourceTokens(source, includeInterpolations: true);
  } on FormatException {
    // 无法可靠理解源码时必须要求真实采集，不能当作空实现。
    return false;
  }
  var i = 0;
  while (i < tokens.length) {
    final first = tokens[i].text;
    if (first == 'enum') {
      // 仅接受枚举值；可选分号之后必须立即结束，任何成员均保守拒绝。
      if (i + 3 >= tokens.length ||
          !_isIdentifier(tokens[i + 1].text) ||
          tokens[i + 2].text != '{') {
        return false;
      }
      i += 3;
      if (!_isIdentifier(tokens[i].text)) return false;
      i++;
      while (i < tokens.length && tokens[i].text == ',') {
        i++;
        if (i < tokens.length && _isIdentifier(tokens[i].text)) {
          i++;
        } else {
          break;
        }
      }
      if (i < tokens.length && tokens[i].text == ';') i++;
      if (i >= tokens.length || tokens[i].text != '}') return false;
      i++;
      continue;
    }
    if (!const {'import', 'export', 'library', 'part', 'const', 'typedef'}
        .contains(first)) {
      return false;
    }
    if (first == 'part' &&
        (i + 1 == tokens.length || tokens[i + 1].text != 'of')) {
      return false;
    }
    var parentheses = 0;
    var brackets = 0;
    var braces = 0;
    var ended = false;
    for (i++; i < tokens.length; i++) {
      final text = tokens[i].text;
      if (first == 'const' && text == '{' && tokens[i - 1].text == ')') {
        return false;
      }
      if (first == 'const' &&
          (const {'class', 'void', 'return', 'final', 'var'}.contains(text) ||
              text == '=' &&
                  i + 1 < tokens.length &&
                  tokens[i + 1].text == '>')) {
        return false;
      }
      switch (text) {
        case '(':
          parentheses++;
        case ')':
          parentheses--;
        case '[':
          brackets++;
        case ']':
          brackets--;
        case '{':
          braces++;
        case '}':
          braces--;
      }
      if (parentheses < 0 || brackets < 0 || braces < 0) return false;
      if (text == ';') {
        if (parentheses != 0 || brackets != 0 || braces != 0) return false;
        ended = true;
        i++;
        break;
      }
    }
    if (!ended) return false;
  }
  return true;
}

/// 检查普通枚举名称或值是否为独立标识符。
bool _isIdentifier(String text) => RegExp(r'^[a-zA-Z_$][\w$]*$').hasMatch(text);

/// 覆盖率豁免标记；开始和单行标记必须携带编号。
final RegExp kIgnoreMarker = RegExp(
  r'//\s*coverage:ignore-(line|start|end)\b(?:\s+(COV-\d{2})\b)?',
);

/// 单个文件的覆盖结果。
class FileCoverage {
  /// 使用路径、命中数、总行数与未覆盖行号构造结果。
  const FileCoverage(this.path, this.hit, this.total, this.missing);

  /// 相对包根的路径。
  final String path;

  /// 命中的行数。
  final int hit;

  /// 计入统计的行数。
  final int total;

  /// 未覆盖的一基行号。
  final List<int> missing;
}

/// 覆盖率门禁的完整结论。
class CoverageReport {
  /// 使用各文件结果和错误列表构造报告。
  const CoverageReport(this.files, this.errors);

  /// 各文件结果。
  final List<FileCoverage> files;

  /// 缺采集、无效豁免等错误。
  final List<String> errors;

  /// 总命中行数。
  int get hit => files.fold(0, (sum, file) => sum + file.hit);

  /// 总计入行数。
  int get total => files.fold(0, (sum, file) => sum + file.total);

  /// 总命中百分比；没有可执行行时为 100，错误仍须独立校验。
  double get percent =>
      total == 0 ? _percentScale : hit * _percentScale / total;
}

/// 已登记的豁免文件、精确位置与批准原因。
class CoverageExemption {
  /// 创建登记；[location] 使用「第1-3行」或「函数名 的 语句名 一行」。
  const CoverageExemption(this.path, this.location, this.reason);

  /// 唯一允许使用此编号的文件。
  final String path;

  /// 逐行或逐段登记的位置，多个位置以中文分号分隔。
  final String location;

  /// 符合豁免类别的理由。
  final String reason;

  /// 根据真实源码解析允许的行号；无法确定位置时明确失败。
  Set<int> allowedLines(String source) {
    final allowed = <int>{};
    for (final position in location.replaceAll('`', '').split(RegExp('[；;]'))) {
      final numeric = RegExp(r'^第\s*(\d+)\s*(?:[-–至到]\s*(\d+)\s*)?行$')
          .firstMatch(position.trim());
      if (numeric != null) {
        final start = int.parse(numeric[1]!);
        final end = int.parse(numeric[2] ?? numeric[1]!);
        if (start < 1 || end < start || end > source.split('\n').length) {
          throw FormatException('豁免行号超出范围: $location');
        }
        allowed.addAll([for (var line = start; line <= end; line++) line]);
        continue;
      }
      final symbolic = RegExp(r'^(\w+)\s*(?:的|中)\s*([\w.]+)\s*一行$')
          .firstMatch(position.trim());
      if (symbolic == null) throw FormatException('无法解析豁免位置: $position');
      final tokens = sourceTokens(source);
      final statement = symbolic[2]!.split('.');
      final matches = <int>[];
      for (var i = 0; i + 1 < tokens.length; i++) {
        if (tokens[i].text != symbolic[1] || tokens[i + 1].text != '(') {
          continue;
        }
        var cursor = i + 1;
        var parentheses = 0;
        do {
          if (tokens[cursor].text == '(') parentheses++;
          if (tokens[cursor].text == ')') parentheses--;
          cursor++;
        } while (cursor < tokens.length && parentheses > 0);
        if (cursor >= tokens.length || tokens[cursor].text != '{') continue;
        var braces = 0;
        do {
          final token = tokens[cursor];
          if (token.text == '{') braces++;
          if (token.text == '}') braces--;
          var found = cursor + statement.length * 2 - 1 < tokens.length;
          for (var part = 0; found && part < statement.length; part++) {
            found = tokens[cursor + part * 2].text == statement[part] &&
                (part == 0 || tokens[cursor + part * 2 - 1].text == '.');
          }
          if (found && tokens[cursor + statement.length * 2 - 1].text == '(') {
            matches.add(sourceLine(source, token.offset));
          }
          cursor++;
        } while (cursor < tokens.length && braces > 0);
      }
      if (matches.length != 1) throw FormatException('豁免位置不唯一或不存在: $position');
      allowed.add(matches.single);
    }
    return allowed;
  }
}

/// 从矩阵 [matrix] 的覆盖率豁免表提取完整登记，保留文件、位置与原因。
///
/// 重复编号、缺少位置或原因时抛出 [FormatException]。
Map<String, CoverageExemption> parseExemptions(String matrix) {
  final result = <String, CoverageExemption>{};
  var inSection = false;
  for (final line in matrix.split('\n')) {
    if (line.startsWith('## ')) {
      inSection = line.trim() == '## 覆盖率豁免';
    }
    if (!inSection || !line.trimLeft().startsWith('| COV-')) continue;
    final cells = line.split('|').map((s) => s.trim()).toList();
    if (cells.length != 6 ||
        !RegExp(r'^COV-\d{2}$').hasMatch(cells[1]) ||
        !cells[2].startsWith('lib/') ||
        cells[3].isEmpty ||
        cells[4].isEmpty ||
        result.containsKey(cells[1])) {
      throw FormatException('INVALID exemption / 豁免登记无效: $line');
    }
    result[cells[1]] =
        CoverageExemption(cells[2].replaceAll('`', ''), cells[3], cells[4]);
  }
  return result;
}

/// 解析 [lcov]、源码 [sources] 和已登记的 [exemptions]，返回覆盖报告。
///
/// 路径可使用 Windows 分隔符或绝对路径；只统计已存在的 lib 源码。
CoverageReport computeCoverage({
  required String lcov,
  required Map<String, String> sources,
  required Map<String, CoverageExemption> exemptions,
}) {
  final normalized = {
    for (final entry in sources.entries) normalizePath(entry.key): entry.value,
  };
  final records = <String, Map<int, int>>{};
  final errors = <String>[];
  Map<int, int>? current;
  for (final line in lcov.split('\n').map((line) => line.trim())) {
    if (line.startsWith(_sourcePrefix)) {
      final path = normalizePath(line.substring(_sourcePrefix.length));
      final matches = normalized.keys.where(
        (key) => path == key || path.endsWith('/$key'),
      );
      current = matches.length == 1
          ? records.putIfAbsent(matches.single, () => <int, int>{})
          : null;
    } else if (line == 'end_of_record') {
      current = null;
    } else if (line.startsWith(_dataPrefix) && current != null) {
      final parts = line.substring(_dataPrefix.length).split(',');
      final number = int.tryParse(parts.first);
      final hits = parts.length > 1 ? int.tryParse(parts[1]) : null;
      if (number == null || number <= 0 || hits == null || hits < 0) {
        errors.add('INVALID coverage record / 无效采集记录: $line');
      } else {
        current[number] = (current[number] ?? 0) + hits;
      }
    }
  }
  final used = <String>{};
  final files = <FileCoverage>[];
  for (final path in normalized.keys.toList()..sort()) {
    final source = normalized[path]!;
    final data = records[path] ?? <int, int>{};
    if (data.isEmpty && !hasNoExecutableLines(source)) {
      errors.add('MISSING coverage record / 缺少采集记录: $path');
    }
    final ignored = <int>{};
    final lines = source.split('\n');
    final comments = <int, String>{
      for (final token in sourceTokens(source, includeComments: true))
        if (token.text.startsWith(kLineCommentPrefix))
          sourceLine(source, token.offset): token.text,
    };
    var ignoring = false;
    String? activeId;
    final approved = <String, Set<int>>{};
    for (final entry in exemptions.entries
        .where((entry) => normalizePath(entry.value.path) == path)) {
      try {
        approved[entry.key] = entry.value.allowedLines(source);
      } on FormatException catch (error) {
        errors.add('INVALID LOCATION / 豁免位置无效: ${entry.key}: $error');
      }
    }

    /// 只排除登记文件和范围内的行，越界行仍计入覆盖率。
    void ignoreLine(String? id, int number) {
      if (id == null || !approved.containsKey(id)) return;
      if (approved[id]!.contains(number)) {
        ignored.add(number);
      } else {
        errors.add('LOCATION MISMATCH / 豁免位置不符: $id at $path:$number');
      }
    }

    for (var i = 0; i < lines.length; i++) {
      final marker = kIgnoreMarker.firstMatch(comments[i + 1] ?? '');
      if (marker != null) {
        final kind = marker[1]!;
        final id = marker[2];
        if (kind == 'end') {
          if (!ignoring) errors.add('UNBALANCED ignore-end: $path:${i + 1}');
          ignoreLine(activeId, i + 1);
          ignoring = false;
          activeId = null;
        } else {
          if (id == null) {
            errors.add('MARKER WITHOUT ID / 豁免标记缺编号: $path:${i + 1}');
          } else {
            used.add(id);
            if (!exemptions.containsKey(id)) {
              errors.add(
                  'UNREGISTERED exemption / 未登记的豁免: $id at $path:${i + 1}');
            } else if (normalizePath(exemptions[id]!.path) != path) {
              errors.add('FILE MISMATCH / 豁免文件不符: $id at $path:${i + 1}');
            }
          }
          if (kind == 'start') {
            if (ignoring) errors.add('NESTED ignore-start: $path:${i + 1}');
            ignoring = true;
            activeId = id;
          }
          if (kind != 'start') ignoreLine(id, i + 1);
        }
      }
      if (ignoring) ignoreLine(activeId, i + 1);
    }
    if (ignoring) errors.add('UNCLOSED ignore-start: $path');
    for (final number in data.keys) {
      if (number > lines.length) {
        errors.add('INVALID coverage line: $path:$number');
      }
    }
    final counted = data.entries.where((e) => !ignored.contains(e.key));
    final missing =
        counted.where((e) => e.value == 0).map((e) => e.key).toList()..sort();
    files.add(FileCoverage(
        path, counted.length - missing.length, counted.length, missing));
  }
  for (final id in exemptions.keys.where((id) => !used.contains(id))) {
    errors.add('UNUSED exemption / 登记未使用: $id');
  }
  return CoverageReport(files, errors);
}

/// 执行覆盖率门禁，如 `dart run tool/coverage.dart --min=100 --lcov=coverage/B01.lcov`。
void main(List<String> args) {
  try {
    final minimum = args
            .where((a) => a.startsWith('--min='))
            .map((a) => double.parse(a.substring(6)))
            .firstOrNull ??
        _percentScale;
    if (!minimum.isFinite || minimum < 0 || minimum > _percentScale) {
      throw const FormatException('min 必须在 0 到 100 之间');
    }
    final input = File(
        args.where((a) => a.startsWith('--lcov=')).firstOrNull?.substring(7) ??
            'coverage/lcov.info');
    final sources = <String, String>{};
    if (Directory(_libDirectory).existsSync()) {
      for (final file in Directory(_libDirectory)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith(kDartFileExtension))) {
        sources[normalizePath(file.path)] = file.readAsStringSync();
      }
    }
    final needsRecords = sources.values.any((s) => !hasNoExecutableLines(s));
    if (!input.existsSync() && needsRecords) {
      throw FileSystemException(
          '缺少覆盖率文件；请先运行 flutter test --coverage', input.path);
    }
    final report = computeCoverage(
        lcov: input.existsSync() ? input.readAsStringSync() : '',
        sources: sources,
        exemptions:
            parseExemptions(File(kAcceptanceMatrixPath).readAsStringSync()));
    for (final file in report.files) {
      final percent = file.total == 0
          ? _percentScale
          : file.hit * _percentScale / file.total;
      stdout.writeln(
          '${file.path}: ${file.hit}/${file.total} (${percent.toStringAsFixed(2)}%)');
      if (file.total == 0 && hasNoExecutableLines(sources[file.path] ?? '')) {
        stdout.writeln('  NO EXECUTABLE LINES / 无可执行行');
      }
      stdout.writeln(
          '  Uncovered / 未覆盖: ${file.missing.isEmpty ? 'none' : file.missing.join(', ')}');
    }
    stdout.writeln(
        'TOTAL: ${report.hit}/${report.total} (${report.percent.toStringAsFixed(2)}%)');
    if (report.total == 0) {
      stdout.writeln('NO EXECUTABLE LINES / 无可执行行；真实实现缺采集仍失败。');
    }
    for (final error in report.errors) {
      stderr.writeln(error);
    }
    if (report.errors.isNotEmpty || report.percent < minimum) {
      stderr.writeln(
          'FAIL: coverage ${report.percent.toStringAsFixed(2)}% < $minimum% or invalid records / 覆盖率未达标或记录无效');
      exitCode = 1;
    } else {
      stdout.writeln('PASS: coverage >= $minimum%');
    }
  } on Object catch (error) {
    stderr.writeln('FAIL: $error');
    exitCode = 1;
  }
}
