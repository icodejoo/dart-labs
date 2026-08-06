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
  final m = a.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = a.inSeconds.remainder(60).toString().padLeft(2, '0');
  final body = h > 0 ? '$h:$m:$s' : '$m:$s';
  return neg ? '-$body' : body;
}
