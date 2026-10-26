/// Injectable wall clock used by absolute-deadline countdowns.
/// Lives in `core/` so no engine depends on another just to read
/// the clock.
///
/// Defaults to [DateTime.now] in production. Override in tests to advance time
/// without real delays:
/// ```dart
/// var fakeNow = DateTime(2024);
/// countdownClock = () => fakeNow;
/// fakeNow = fakeNow.add(const Duration(seconds: 3));
/// ```
// ignore: prefer_function_declarations_over_variables
DateTime Function() countdownClock = DateTime.now;

// 秒表使用单调时间，避免系统校时导致累计时间跳变。
final Stopwatch _elapsedWatch = Stopwatch()..start();

/// 可注入的单调时间源；测试结束后应恢复原函数。
// ignore: prefer_function_declarations_over_variables
Duration Function() elapsedClock = () => _elapsedWatch.elapsed;
