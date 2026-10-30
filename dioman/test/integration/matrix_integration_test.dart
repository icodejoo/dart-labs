// ignore_for_file: avoid_relative_lib_imports
import 'dart:io';
import 'package:test/test.dart';
import '../accept/lib/matrix.dart';

/// 默认测试直接拦截静态缺口，基线不允许掩盖新 API 或遗留旧引用。
void main() {
  test('[matrix.repositoryGaps] 总账 G0/G2/G3/G5 单测侧无缺口', () {
    final rows = (readMatrixJson('$matrixDirectory/matrix.json', []) as List)
        .map((row) => MatrixRow.fromJson((row as Map).cast<String, dynamic>()))
        .toList();
    final gaps = repositoryGaps(Directory.current, rows)
        .where((gap) => staticGates.any(gap.startsWith))
        .toList()
      ..sort();
    expect(gaps, isEmpty, reason: gaps.join('\n'));
    final baseline =
        (readMatrixJson('$matrixDirectory/matrix-baseline.json', []) as List)
            .cast<String>();
    expect(baseline.where((gap) => staticGates.any(gap.startsWith)), isEmpty);
  });
}
