// ignore_for_file: avoid_relative_lib_imports
import 'dart:convert';
import 'dart:io';
import '../lib/matrix.dart';

/// 本文件共用的字面量 'G0:'。
const _g0 = 'G0:';

/// 本文件共用的字面量 'G1:'。
const _g1 = 'G1:';

/// 本文件共用的字面量 'G2:'。
const _g2 = 'G2:';

/// 本文件共用的字面量 'G3:'。
const _g3 = 'G3:';

/// 本文件共用的字面量 'sync'。
const _sync = 'sync';

/// 全部闸门，G0 表示未定档。
const _gates = {_g0, _g1, _g2, _g3, 'G4:', 'G5:'};

/// 写入格式化 JSON。
void _writeJson(String path, Object value) => File(path).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(value)}\n');

/// 输出中文缺口报告。
void _report(
    String path, Set<String> gaps, List<MatrixRow> rows, bool hasLcov) {
  final counts = <String, Map<String, int>>{};
  for (final gap in gaps) {
    final gate = gap.substring(0, 3);
    if (!const {_g0, _g2, _g3}.contains(gate)) continue;
    final id = gap.substring(3);
    final plugin = rows.where((r) => r.id == id).firstOrNull?.plugin ?? '未归行';
    final count = counts[plugin] ??= {};
    count[gate] = (count[gate] ?? 0) + 1;
  }
  final date = DateTime.now().toIso8601String().split('T').first;
  final output = StringBuffer(
      '---\ntitle: 测试总账矩阵缺口报告\nstatus: active\nupdated: $date\nsummary: 总账五道闸门的当前缺口清单与按插件分布，是补测的基线。\n---\n\n');
  output.writeln(hasLcov ? 'G1 已检查 lcov。\n' : 'G1 未检查：未提供 lcov。\n');
  output.writeln('| 闸门 | 缺口数 |\n|---|---:|');
  for (final gate in _gates) {
    output.writeln(
        '| ${gate.substring(0, 2)} | ${gate == _g1 && !hasLcov ? '未检查' : gaps.where((g) => g.startsWith(gate)).length} |');
  }
  output.writeln('\n## 按插件汇总\n\n| 插件 | G2 | G3 | G0 |\n|---|---:|---:|---:|');
  for (final plugin in counts.keys.toList()..sort()) {
    final count = counts[plugin]!;
    output.writeln(
        '| $plugin | ${count[_g2] ?? 0} | ${count[_g3] ?? 0} | ${count[_g0] ?? 0} |');
  }
  output.writeln('\n## 完整缺口\n');
  for (final gate in _gates) {
    final items = gaps.where((g) => g.startsWith(gate)).toList()..sort();
    output.writeln(
        '<details>\n<summary>${gate.substring(0, 2)}（${items.length}）</summary>\n');
    for (final gap in items) {
      output.writeln('- `$gap`');
    }
    output.writeln('\n</details>\n');
  }
  File(path).writeAsStringSync(output.toString());
}

/// 本文件共用的字面量 'evidence'。
const _evidence = 'evidence';

/// 本文件共用的字面量 'results'。
const _results = 'results';

/// 把原始验收报告压成入库汇总；[paths] 为报告 JSON，后者覆盖前者。
void _writeEvidence(List<String> paths, String? out) {
  final date = DateTime.now().toIso8601String().split('T').first;
  final target = out ?? '$evidenceDirectory/$date-summary.json';
  final hits =
      readMatrixJson('coverage/accept/api-evidence.json', {}) as Map? ?? {};
  final summary = {
    'date': date,
    'sources': paths,
    ...summarizeEvidence([
      for (final p in paths)
        (readMatrixJson(p, {}) as Map).cast<String, dynamic>()
    ], apiHits: (hits['hits'] as Map? ?? {}).keys.cast<String>()),
  };
  Directory(evidenceDirectory).createSync(recursive: true);
  _writeJson(target, summary);
  stdout.writeln(
      '汇总 ${(summary['cases'] as Map).length} 个真实用例、${(summary['apiHits'] as List).length} 个 API 触达 → $target');
}

/// 用最新（或 [path] 指定的）入库汇总回填每行 result，其余字段不动。
void _fillResults(List<MatrixRow> rows, String? path) {
  final source = path ?? latestEvidence(Directory.current);
  if (source == null) {
    stderr.writeln('没有证据汇总，先运行 matrix.dart evidence <报告…>。');
    exitCode = 1;
    return;
  }
  final cases = ((readMatrixJson(source, {}) as Map)['cases'] as Map? ?? {})
      .cast<String, dynamic>();
  var filled = 0;
  final updated = [
    for (final row in rows)
      () {
        final result = rowResult(row, cases, source);
        if (result != null) filled++;
        return {...row.toJson(), 'result': result};
      }()
  ];
  _writeJson('$matrixDirectory/matrix.json', updated);
  stdout.writeln('回填 $filled 行结论（来源 $source）。');
}

/// 执行 sync / gates / evidence / results 命令；例如 `dart run test/accept/bin/matrix.dart sync`。
void main(List<String> args) {
  if (args.isEmpty ||
      !const {_sync, 'gates', _evidence, _results}.contains(args.first)) {
    stderr.writeln('用法: matrix.dart sync\n'
        '      matrix.dart gates [--lcov=路径] [--report=路径] [--update-baseline] [--allow-grow]\n'
        '      matrix.dart evidence <报告.json>… [--out=路径]\n'
        '      matrix.dart results [--evidence=路径]');
    exitCode = 64;
    return;
  }

  /// 获取带等号的命令选项。
  String? option(String prefix) => args
      .where((a) => a.startsWith(prefix))
      .firstOrNull
      ?.substring(prefix.length);
  if (args.first == _evidence) {
    _writeEvidence(args.skip(1).where((a) => !a.startsWith('--')).toList(),
        option('--out='));
    return;
  }
  final rows = (readMatrixJson('$matrixDirectory/matrix.json', []) as List)
      .map((r) => MatrixRow.fromJson((r as Map).cast<String, dynamic>()))
      .toList();
  if (args.first == _results) {
    _fillResults(rows, option('--evidence='));
    return;
  }
  if (args.first == _sync) {
    final inventory =
        (readMatrixJson('$matrixDirectory/api-inventory.json', []) as List)
            .cast<Map<String, dynamic>>();
    final updated = draftRows(inventory, rows);
    _writeJson('$matrixDirectory/matrix.json',
        updated.map((r) => r.toJson()).toList());
    stdout
        .writeln('新增 ${updated.length - rows.length} 行；共 ${updated.length} 行。');
    return;
  }
  final lcov = option('--lcov=');
  final gaps =
      repositoryGaps(Directory.current, rows, full: true, lcovPath: lcov);
  if (lcov == null) stdout.writeln('G1 未检查：未提供 lcov。');
  for (final gate in _gates) {
    final items = gaps.where((g) => g.startsWith(gate)).toList()..sort();
    stdout.writeln('$gate ${items.length}');
    for (final gap in items.take(5)) {
      stdout.writeln('  $gap');
    }
  }
  final report = option('--report=');
  if (report != null) _report(report, gaps, rows, lcov != null);
  final baseline =
      (readMatrixJson('$matrixDirectory/matrix-baseline.json', []) as List)
          .cast<String>()
          .toSet();
  // 未执行 G1 时保留其既有基线，不将未检查误报为已修复。
  final checked = {..._gates}..removeAll(lcov == null ? {_g1} : {});
  final delta = ratchet(gaps, baseline, required: checked);
  if (delta.added.isNotEmpty || delta.fixed.isNotEmpty) {
    for (final entry
        in {'新增 gap': delta.added, '已修复但仍在基线': delta.fixed}.entries) {
      stdout.writeln('${entry.key}（${entry.value.length}）:');
      for (final gap in entry.value.toList()..sort()) {
        stdout.writeln('  $gap');
      }
    }
  }
  if (args.contains('--update-baseline')) {
    if (delta.added.isNotEmpty && !args.contains('--allow-grow')) {
      stderr.writeln('拒绝扩大基线；首次初始化需显式 --allow-grow。');
      exitCode = 1;
    } else {
      final updated = {
        ...gaps,
        if (lcov == null) ...baseline.where((g) => g.startsWith(_g1))
      }.toList()
        ..sort();
      _writeJson('$matrixDirectory/matrix-baseline.json', updated);
      stdout.writeln('基线已更新：${updated.length} 个 gap。');
    }
  } else if (delta.added.isNotEmpty || delta.fixed.isNotEmpty) {
    stderr.writeln('请补测，或运行 gates --update-baseline 删除已修复缺口。');
    exitCode = 1;
  }
}
