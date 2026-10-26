// 从右累计各组宽度，超出模式后重复最后一组；仅接收整数右侧位数。
bool isGroupingBoundary(int digitsToRight, List<int> pattern) {
  if (digitsToRight <= 0 || pattern.isEmpty) return false;
  var boundary = 0;
  for (final width in pattern) {
    if (width <= 0) return false;
    boundary += width;
    if (digitsToRight <= boundary) return digitsToRight == boundary;
  }
  return (digitsToRight - boundary) % pattern.last == 0;
}
