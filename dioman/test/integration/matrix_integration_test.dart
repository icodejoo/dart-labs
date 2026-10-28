// ignore_for_file: avoid_relative_lib_imports
import 'dart:io';
import 'package:test/test.dart';
import '../accept/lib/matrix.dart';

/// 默认运行静态闸门，基线同时禁止新增和遗留已修复缺口。
void main() {
  test('[matrix.repositoryGaps] 总账静态闸门棘轮', () {
    final rows = (readMatrixJson('$matrixDirectory/matrix.json', []) as List)
        .map((r) => MatrixRow.fromJson((r as Map).cast<String, dynamic>()))
        .toList();
    final baseline =
        (readMatrixJson('$matrixDirectory/matrix-baseline.json', []) as List)
            .cast<String>()
            .toSet();
    final gaps = repositoryGaps(Directory.current, rows);

    /// 真实侧只在 gates 命令中比较。
    Set<String> staticOnly(Set<String> values) =>
        values.where((g) => !g.startsWith('G5:real-')).toSet();
    final delta =
        ratchet(staticOnly(gaps), staticOnly(baseline), required: staticGates);
    expect(delta.added, isEmpty,
        reason: '新增缺口：${delta.added.toList()..sort()}；请补测。');
    expect(delta.fixed, isEmpty,
        reason:
            '已修复缺口：${delta.fixed.toList()..sort()}；运行 gates --update-baseline。');
  });
}
