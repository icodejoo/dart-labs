/// 把 [value] 限制到 0 到 1 之间，返回 double（`num.clamp` 返回 num）。
///
/// 例如 `luckyUnit(1.5)` 返回 1.0；非有限输入与 `clamp` 行为一致。
double luckyUnit(double value) => value.clamp(0.0, 1.0).toDouble();
