/// Injectable wall clock shared by every time-based engine (countdown,
/// elapsed). Lives in `core/` so no engine depends on another just to read
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
