/// 独立规范参考：关键帧的切换时刻，缺少匹配 keyTimes 时按 n 等分。
int referenceDiscreteIndex(double progress, int count, List<double>? keyTimes) {
  final switches = keyTimes?.length == count
      ? keyTimes!
      : [for (var i = 0; i < count; i++) i / count];
  var frame = 0;
  for (var i = 1; i < count; i++) {
    if (progress >= switches[i]) frame = i;
  }
  return frame;
}

/// 独立参考的 normal 活动进度，含零时长、小数重复和 freeze 末态。
double? referenceNormalProgress({
  required Duration time,
  required Duration begin,
  required Duration duration,
  required bool indefinite,
  required double repeatCount,
  required bool freeze,
}) {
  final elapsed = (time - begin).inMicroseconds;
  if (elapsed < 0) return null;
  final period = duration.inMicroseconds;
  if (period == 0) return 1;
  if (!indefinite && elapsed >= (period * repeatCount).round()) {
    if (!freeze) return null;
    final remainder = repeatCount - repeatCount.floor();
    return remainder == 0 ? 1 : remainder;
  }
  return (elapsed % period) / period;
}
