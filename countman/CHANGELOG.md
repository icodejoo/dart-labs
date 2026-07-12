# Changelog

## 0.1.0

Initial release.

A high-performance counter / countdown / elapsed animation library for Flutter.
One shared `scheduleFrameCallback` ticker drives every instance — adding the
hundredth counter costs the same as the first.

### Engines
- `Counter` (value interpolation), `Countdown` (wall-clock deadline, interval-
  gated), `Elapsed` (open-ended stopwatch). Top-level `counter()` / `countdown()`
  / `elapsed()`, shared `defaultCounter` / `defaultCountdown` / `defaultElapsed`
  and precise (`interval: 0`) `defaultCountdownMs` / `defaultElapsedMs`.

### Widgets
- Counter: `TextCounter`, `RingCounter`, `BarCounter`, `OdometerCounter`,
  `AnimatedCounter` (+ `.usd`/`.cny`/`.inr`), `AnimatedCounterBuilder`,
  `CounterBuilder`.
- Countdown: `TextCountdown`, `RingCountdown`, `BarCountdown`, `DialCountdown`,
  `CardCountdown`, `CountdownBuilder`.
- Elapsed: `TextElapsed`, `ElapsedBuilder`.

### Features
- Per-widget `*Style` objects (colors, gradients, `decoration` + `padding`,
  ring `sweepAngle` gauge / `startAngle` / `showTrack` / leading thumb dot, bar
  `vertical` / `showTrack`); `painterBuilder` escape hatch on ring/bar/dial.
- Imperative controllers: `CounterValueController`, `AnimatedCounterController`,
  `CountdownController`, `ElapsedController` (pause / resume / reset / status).
- Providers: `CounterProvider`, `CountdownProvider`, `ElapsedProvider`,
  aggregate `CountmanProvider`, and `CardCountdownProvider` (shared glyph cache).
- `precise: true` sub-second updates; `onTick(TimeParts)`; `threshold` +
  `onThreshold`; full lifecycle callbacks; `animateOnce` (play once per key).
- Formatters `CountdownFormat.{hms, ms, msTenths, msMillis, dhms, dhm, auto}`.
- `StartScheduler` (batch grid startup across frames); injectable
  `countdownClock` for testing / server-time alignment.

Zero third-party runtime dependencies.
