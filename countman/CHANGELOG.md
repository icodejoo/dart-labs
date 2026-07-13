# Changelog

## 0.2.2

Docs only — no code changes.

### Fixed
- README (EN/ZH) demo link/badge now points to the package-specific demo
  path (`/countman/`) instead of the shared monorepo landing page.

## 0.2.1

Docs only — no code changes.

### Fixed
- README screenshots and cross-links (EN/ZH) now use absolute URLs so they
  render on pub.dev. Relative paths broke because the package lives in a
  monorepo subdirectory (`countman/`), which pub.dev resolves against the repo
  root.

## 0.2.0

Counter transition redesign + internal consolidation.

### Changed (breaking)
- `AnimatedCounter` / `AnimatedCounterBuilder`: `transitionType`
  (`CounterTransitionType`) → `transition` (`CounterTransition`) — a composable
  look built from a `CounterMotion` (`none`/`slide`/`rotate`/`flip`) plus
  `scale` / `fade` / `blur` modifiers, with presets `.slide` (default),
  `.slideScale`, `.slideBlur`, `.rotate`, `.flip`, `.flipFade`.
- Removed the `AnimatedCounter.usd` / `.cny` / `.inr` currency factory
  constructors — compose `prefix` + `groupingPattern` (`[3]` / `[4]` / `[3, 2]`)
  directly instead.
- `OdometerCounter` is now a thin `AnimatedCounter` delegate (a `StatelessWidget`
  reusing the shared painter). `bounceElasticity` is retained for source
  compatibility but no longer has an effect — bounce is driven by
  `bounceOvershoot`.

### Added
- Leading-zero-at-rest fade-in: hidden leading zeros fade in/out by the live
  cumulative place value instead of popping (e.g. `1000 → 7` collapses to `7`).
- Per-column bounce wave that follows a staggered roll.

### Internal
- Odometer trajectory + end-of-roll ghost-prevention math extracted into one
  shared `resolveDigitPhase` used by both the painter and widget-tree paths;
  the paint/build hot paths stay allocation-free via a reused `DigitPhase`.
- The default (`slide`/`none`) paint path skips a redundant canvas
  save/restore pair.
- Default-plugin registration unified on first task (`LazyDefault` +
  `enqueue` self-register), with a central reset on `Countman.destroy()`.
- `CountmanTask.reanchor()` replaces ad-hoc `started` toggling for
  retarget / resume / reset.

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
