/// Formats a duration as mm:ss (or h:mm:ss when an hour or longer).
///
/// 将时长格式化为 mm:ss（满一小时用 h:mm:ss）。
///
/// - [d]: the duration to format / 待格式化的时长
/// - returns the formatted string / 返回格式化后的字符串
///
/// Example / 示例:
/// ```dart
/// formatDuration(const Duration(seconds: 75)); // '01:15'
/// ```
String formatDuration(Duration d) {
  final neg = d.isNegative;
  final a = d.abs();
  final h = a.inHours;
  final m = _twoDigits(a.inMinutes.remainder(Duration.minutesPerHour));
  final s = _twoDigits(a.inSeconds.remainder(Duration.secondsPerMinute));
  final body = h > 0 ? '$h:$m:$s' : '$m:$s';
  return neg ? '-$body' : body;
}

/// Pads a time field to two digits.
///
/// 将时间字段补足两位数字。
String _twoDigits(int value) => value.toString().padLeft(2, '0');
