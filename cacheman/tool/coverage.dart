import 'dart:io';

/// Zero-dependency lib line coverage reporter and threshold gate.
/// 零依赖的 lib 行覆盖率报告与阈值门禁。
void main(List<String> args) {
  final minimum = args
          .where((a) => a.startsWith('--min='))
          .map((a) => double.parse(a.substring('--min='.length)))
          .firstOrNull ??
      0;
  final input = File('coverage/lcov.info');
  if (!input.existsSync()) {
    stderr.writeln(
        'Missing coverage/lcov.info; run flutter test --coverage first. / 请先生成覆盖率。');
    exitCode = 1;
    return;
  }
  final records = <String, Map<int, int>>{};
  Map<int, int>? current;
  for (final line in input.readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      var path = line.substring(3).replaceAll('\\', '/');
      final root = '${Directory.current.path.replaceAll('\\', '/')}/';
      if (path.startsWith(root)) {
        path = path.substring(root.length);
      }
      current =
          path.startsWith('lib/') ? records.putIfAbsent(path, () => {}) : null;
    } else if (line.startsWith('DA:') && current != null) {
      final parts = line.substring(3).split(',');
      final number = int.parse(parts[0]);
      current[number] = (current[number] ?? 0) + int.parse(parts[1]);
    }
  }
  var total = 0;
  var hit = 0;
  var missingRecords = false;
  for (final file in Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path))) {
    final path = file.path.replaceAll('\\', '/');
    final lines = file.readAsLinesSync();
    // Never count an uninstrumented implementation as a vacuous 0/0 success.
    // 未被采集的实现不可作为0/0误报成功；仅导出等指令文件允许无记录。
    final declarations = lines
        .join('\n')
        .replaceAll(RegExp(r'//[^\n]*|/\*[\s\S]*?\*/'), '')
        .replaceAll(
            RegExp(r'^\s*(library|import|export|part)\b[^;]*;',
                multiLine: true),
            '')
        .trim();
    if (!records.containsKey(path) && declarations.isNotEmpty) {
      stderr.writeln('MISSING coverage record / 缺少采集记录: $path');
      missingRecords = true;
    }
    var ignoring = false;
    final ignored = <int>{};
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].contains('// coverage:ignore-start')) ignoring = true;
      if (ignoring || lines[i].contains('// coverage:ignore-line')) {
        ignored.add(i + 1);
      }
      if (lines[i].contains('// coverage:ignore-end')) ignoring = false;
    }
    final counted =
        (records[path] ?? {}).entries.where((e) => !ignored.contains(e.key));
    final count = counted.length;
    final covered = counted.where((e) => e.value > 0).length;
    final missing =
        counted.where((e) => e.value == 0).map((e) => e.key).toList()..sort();
    total += count;
    hit += covered;
    final percent = count == 0 ? 100.0 : 100 * covered / count;
    stdout.writeln('$path: $covered/$count (${percent.toStringAsFixed(2)}%)');
    stdout.writeln(
        '  Uncovered / 未覆盖: ${missing.isEmpty ? "none" : missing.join(", ")}');
  }
  final percent = total == 0 ? 0.0 : hit * 100 / total;
  stdout.writeln('TOTAL: $hit/$total (${percent.toStringAsFixed(2)}%)');
  if (missingRecords || total == 0 || percent < minimum) {
    stderr.writeln('FAIL: coverage < $minimum% / 覆盖率未达标');
    exitCode = 1;
  } else {
    stdout.writeln('PASS: coverage >= $minimum%');
  }
}
