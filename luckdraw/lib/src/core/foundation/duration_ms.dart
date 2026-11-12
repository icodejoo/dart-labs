/// 把时长 [value] 换算为毫秒（含小数）。
///
/// 例如 `luckyMs(const Duration(microseconds: 1500))` 返回 1.5。
double luckyMs(Duration value) =>
    value.inMicroseconds / Duration.microsecondsPerMillisecond;
