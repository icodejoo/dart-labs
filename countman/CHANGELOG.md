# Changelog

## Unreleased

### Added
- Add `CounterTimeline` for immutable animation configuration on
  `AnimatedCounter` and `AnimatedCounterBuilder` via `timeline`; non-null
  fields override loose parameters, null fields fall back, and value-equal
  configurations preserve the running animation and painter.
- Add `CounterFormat` for shared immutable formatting configuration on
  `AnimatedCounter` and `AnimatedCounterBuilder`; non-null object fields
  override loose parameters, while null fields fall back to them.

<!-- 本批仅整理 Simplify 1–6，保留公开参数及已有修复。 -->
### Fixed
- Counter painter: hide leading zeroes only in the integer part (keep the
  units digit, fraction digits and decimal point, e.g. `0.05`); share
  right-anchored grouping boundaries between painter and widget paths.
- Counter painter: rebuild on any config change (separators, numerals,
  padding, alignment, builder) and always repaint a replaced painter; draw
  digits with the full text style, system text scale and the original
  colour alpha; cache column layout and release Dial tick labels.
- `AnimatedCounterController.jumpTo` cancels the running roll and bounce;
  `pause`/`stop` also cover `startDelay`, batched starts and bounce.
- `speedMultiplier` scales stagger once; `repeat(reverse: true)` loops back
  and forth until stopped; `reverse()` swaps fast-mode endpoints too.
- Reduce-motion now applies to the `AnimatedCounter` roll and card updates.
- Replace always-true render assertions with captured-exception checks and
  guarantee shared fixture cleanup even when an assertion fails.
- Align `AnimatedCounterStyle` equality with the runtime-type contract used
  by the other styles.

### Changed
- Share number clamping, compact formatting, rounding and digit extraction
  across both animated counter renderers; share painter column spacing with
  full-width measurement.
- Reuse constant default abbreviations and sort custom thresholds once per
  configuration change, including in-place map changes on widget or controller
  updates.
- Update examples to omit inert odometer and bounce arguments.

### Deprecated
- Mark inert `OdometerCounter` parameters (`plugin`, `controller`, `slideCurve`,
  `onUpdate`, `onReady`, `onCancel`) and style fields (`letterWidth`,
  `verticalOffset`, `fadeEnabled`) deprecated without removing them.
- Mark `bounceElasticity` deprecated on both animated counters and the odometer;
  use `bounceOvershoot` instead. All existing parameters and defaults remain.

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
