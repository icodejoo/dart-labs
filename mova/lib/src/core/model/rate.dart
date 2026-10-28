/// Lowest accepted playback-rate multiplier; `MovaApi.setRate` clamps below it.
///
/// 可接受的最低倍速；`MovaApi.setRate` 低于它会被钳到此值。
const double kMovaMinRate = 0.25;

/// Highest accepted playback-rate multiplier; `MovaApi.setRate` clamps above it.
///
/// 可接受的最高倍速；`MovaApi.setRate` 高于它会被钳到此值。
const double kMovaMaxRate = 4.0;

/// Neutral playback rate, also what a NaN request resolves to.
///
/// 正常倍速；传入 NaN 时也归约为它。
const double kMovaNormalRate = 1.0;

/// Clamps [r] into [kMovaMinRate]..[kMovaMaxRate]; NaN becomes [kMovaNormalRate].
///
/// 把 [r] 钳到 [kMovaMinRate]..[kMovaMaxRate]；NaN 归为 [kMovaNormalRate]。
///
/// Example / 示例:
/// ```dart
/// movaClampRate(10);          // 4.0
/// movaClampRate(double.nan);  // 1.0
/// ```
double movaClampRate(double r) =>
    r.isNaN ? kMovaNormalRate : r.clamp(kMovaMinRate, kMovaMaxRate).toDouble();
