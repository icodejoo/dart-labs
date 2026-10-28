import 'literals.dart';

/// binaryPairs 的测试辅助入口。
/// 构造二元强度二正交数组；不同非零列向量的模二内积彼此独立。
/// 参考 NIST covering arrays；不依赖外部生成器，不追求最小行数。
List<List<bool>> binaryPairs(int columns) {
  if (columns < 2 || columns > 31) {
    throw RangeError.range(columns, 2, 31);
  }
  var size = 1;
  while (size <= columns) {
    size *= 2;
  }
  return [
    for (var row = 0; row < size; row++)
      [
        for (var column = 1; column <= columns; column++)
          (row & column)
              .toRadixString(2)
              .split(tkEmpty)
              .where((v) => v == tk1)
              .length
              .isOdd,
      ],
  ];
}
