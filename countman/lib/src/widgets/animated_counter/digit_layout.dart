import 'grouping.dart';

// 可见列布局和完整宽度预留共用间距计算，隐藏首列前不插入分组符。
({double width, bool hasSeparator}) digitSpacingBefore({
  required int index,
  required int firstVisible,
  required int digitCount,
  required int fractionDigits,
  required List<int> groupingPattern,
  required bool hasGrouping,
  required double separatorWidth,
  required double decimalSeparatorWidth,
}) {
  var spacing = 0.0;
  if (fractionDigits > 0 && index == digitCount - fractionDigits) {
    spacing += decimalSeparatorWidth;
  }
  final hasSeparator = hasGrouping &&
      index > firstVisible &&
      isGroupingBoundary(digitCount - fractionDigits - index, groupingPattern);
  if (hasSeparator) {
    spacing += separatorWidth;
  }
  return (width: spacing, hasSeparator: hasSeparator);
}
