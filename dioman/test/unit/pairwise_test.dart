// ignore_for_file: avoid_relative_lib_imports
// 单元层：pairwise
import 'package:test/test.dart';
import '../accept/lib/pairwise.dart';

/// 注册本文件的单元层用例。
void main() {
  test('[binaryPairs] 17 列的每一对均覆盖 00、01、10、11', () {
    const count = 17;
    final rows = binaryPairs(count);
    expect(rows.length, 32);
    expect(rows.map((row) => row.join()).toSet().length, rows.length);
    for (var left = 0; left < count; left++) {
      for (var right = left + 1; right < count; right++) {
        final states = {
          for (final row in rows) (row[left] ? 2 : 0) + (row[right] ? 1 : 0),
        };
        expect(states, {0, 1, 2, 3}, reason: '$left/$right');
      }
    }
  });

  test('[binaryPairs] 最小列数与最大列数也满足强度二，越界显式报错', () {
    for (final count in [2, 31]) {
      final rows = binaryPairs(count);
      for (var left = 0; left < count; left++) {
        for (var right = left + 1; right < count; right++) {
          expect({for (final row in rows) (row[left], row[right])}.length, 4);
        }
      }
    }
    for (final count in [0, 1, 32]) {
      expect(() => binaryPairs(count), throwsArgumentError);
    }
  });
}
