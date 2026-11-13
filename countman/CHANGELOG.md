## 0.3.3

- Docs: pubspec `homepage` and `repository` now point to the package directory on the `main` branch.

## 0.3.2

- Docs only: rewrote README wording in plain language; Chinese README renamed to README.zh-CN.md; the online demo now uses the shared demo kit with English/Chinese switching.

## 0.3.1

- Docs only: new MIGRATION section for hidden-widget sleeping and `Countman.muteWhenHidden`; README performance tips document `DialCountdown.clearTickImageCache()` and `FlipCardPainter.clearFaceImageCache()`; 0.3.0 changelog entries translated to English and re-grouped (fps, `muteWhenHidden` and the cache-clearing APIs under Added); real example README.

# Changelog

## 0.3.0

Migration guide: [MIGRATION.md](MIGRATION.md).

### Breaking
- `CountmanPlugin.tick` returns an `int` (microseconds until the plugin needs
  the next frame) instead of a `bool`: `CountmanPlugin.idle` (`-1`, nothing to
  do), `CountmanPlugin.nextFrame` (`0`) or a positive wake-up delay.
  `CountmanPlugin` also gained a required `onDetach()`. *Migrate:* change the
  return type, return one of those values and add an `onDetach()` (an empty
  body is fine).
- `TaskQueuePlugin.beginFrame` and `step` return `void`, and `step` lost its
  `shouldProcess` parameter. The wake-up time comes from the new overridable
  `nextWake(task)` (default `nextFrame`). *Migrate:* drop the return values and
  the extra parameter.
- `ClockPlugin` subclass hooks work in integer microseconds: `valueOf` became
  `valueMicrosOf`, `thresholdCrossed` became `thresholdWake(value,
  thresholdMicros)`, and two hooks are new and required:
  `boundaryWake(task, value, intervalMicros)` and `completionWake(task, value)`
  (`displayMicrosOf` is optional). The constructor accepts a `clock`.
  *Migrate:* see the table in MIGRATION.md.
- `CountdownOptions.duration` is optional and `CountdownOptions.deadline` is
  new; provide exactly one. *Migrate:* keep `duration:` for relative
  countdowns, use `deadline: DateTime(...)` for absolute ones.
- Clock semantics: a `Duration` countdown (`duration`, or a widget's
  `to: Duration(...)`) and every stopwatch run on the monotonic clock, so
  changing the system time no longer affects them; a `deadline` (or a widget's
  `to` as `DateTime` / `int` / `String`) runs on the wall clock. After
  pause/resume or `reset()` a task continues on the monotonic clock.
  `remainingUntil` / `resolveDeadline` take an optional `clock`. *Migrate:* if
  you relied on a `Duration` countdown following system-time changes, pass an
  absolute `deadline` instead.
- The plugin registry is keyed by instance, not by name. Registering a
  *different* instance with an existing name asserts in debug builds (release
  builds still register it); it used to be ignored silently.
  `Countman.unuse(plugin, {bool dispose = true})`. *Migrate:* reuse one
  instance per group, or give every instance a unique `name`.
- Changing the resolved plugin (or `precise`) no longer restarts running tasks;
  they migrate to the new plugin keeping remaining / elapsed time, laps, pause
  state and the displayed value. *Migrate:* call `controller.restart()` if you
  relied on the restart.
- `CounterBuilder.builder` is nullable (the constructor parameter is still
  required) because of the new `CounterBuilder.listenable`. *Migrate:* only code
  that reads the `builder` field of a `CounterBuilder` is affected.
- Default styles are resolved as widget `style` > provider `*Style`
  (deprecated) > `CountmanTheme` > built-in default. *Migrate:* move
  provider-level `*Style` arguments into `CountmanTheme`.

### Added
- Clock abstraction: `CountmanClock` (`wallMicros`, `monotonicMicros`),
  `SystemClock` (default; once the app returns to the foreground it adds back
  the time the monotonic clock stood still during device deep sleep),
  `OffsetClock` for server-time correction and `ManualCountmanClock`
  (`advance`, `jumpWall`, `suspend`) for tests. `CountmanClock.system` can be
  replaced globally; `Countdown` / `Elapsed` take a `clock` argument.
- `CountdownOptions.total` (progress denominator, e.g. a whole auction window)
  and `rounding` with `CountdownRounding { floor, ceil }` (`ceil` shows 10 for
  9.3 s). Completion and thresholds still use the real remaining time.
  `total` / `rounding` are forwarded by `CountdownBuilder`, `TextCountdown`,
  `RingCountdown`, `BarCountdown`, `DialCountdown` and `CardCountdown`.
- `CountdownFormat.template(pattern)`: tokens `{d} {H} {HH} {TH} {m} {mm} {TM}
  {s} {ss} {S} {SSS}`, parsed once, e.g. `'{d}天 {HH}:{mm}:{ss}'`.
- Elapsed: `ElapsedOptions.since` (wall-clock start) / `initial` (monotonic
  offset; mutually exclusive), `limit` + `onComplete`,
  `ElapsedHandle.updateLimit`, laps through `ElapsedHandle.lap()` / `laps` and
  `ElapsedController.lap()` / `laps`. `ElapsedBuilder` / `TextElapsed` take
  `since`, `initial`, `limit` and `onComplete`.
- Controllers expose `runState` (`CountmanRunState`: idle / running / paused /
  completed) and `runStateListenable`, plus `restart()` and `dispose()`
  (`CounterValueController`, `CountdownController`, `ElapsedController`;
  `AnimatedCounterController` gets `runState` / `runStateListenable`).
  `CountmanRunStateNotifier` is the mixin behind it.
- `CountmanTheme` (a `ThemeExtension`) carries the default style of every
  display widget; every `*Style` has a static `lerp`;
  `CountmanTheme.maybeOf` / `of`.
- `AnimatedCounter` / `AnimatedCounterBuilder`: `plugin` (explicit > nearest
  `CounterProvider` > `defaultCounter`, so the provider's `onGroupReady` /
  `onAllComplete` apply) and `animateOnce`.
- `CounterFormat.format(value, {minValue, maxValue})` returns the string an
  `AnimatedCounter` shows at rest.
- `CounterBuilder.listenable` / `CountdownBuilder.listenable` constructors push
  values through a `ValueListenable` instead of rebuilding every tick;
  `RingPainter` / `BarPainter` take an optional `progressListenable`.
- `CardCountdown.semanticsLabel` (default `'Countdown'`).
- `RingStyle` and `BarStyle` are exported themselves, not only their aliases.
- `Countman.fps` (global display cap) with overrides on plugins, options and
  widgets (instance > plugin > global; `null` follows vsync, the default).
  Completion and thresholds are not affected. `CardCountdown` is driven by a
  private shared Counter progress task, so fps really lowers its frame rate.
  Muting wins over fps.
- Widgets sleep while `TickerMode` is disabled: no `onUpdate` / `onTick`
  delivery, completion and thresholds still fire on real time, and the current
  value shows immediately on resume. `Countman.muteWhenHidden = false` restores
  the previous behaviour; `CardCountdown` settles its flip when hidden or shown.
- `DialCountdown.clearTickImageCache()` and
  `FlipCardPainter.clearFaceImageCache()` release the shared bitmaps; they are
  rebuilt on demand and neither repaints nor clears glyph caches.

### Changed
- The scheduler sleeps between updates: when no plugin needs a frame within
  about 20 ms it arms one global timer and requests a frame when it fires. A
  once-per-second countdown no longer produces a frame per vsync.
- Clock tasks update when their own value crosses a multiple of `interval`
  (per-task buckets, not a plugin-wide phase); `onComplete` fires on the frame
  containing the deadline.
- `CountdownBuilder` and `CardCountdown` read `CountdownProvider.plugin`, so
  `onAllComplete` also fires for cards. `CounterBuilder`, `CountdownBuilder`,
  `ElapsedBuilder` and `CardCountdown` resolve the plugin and the reduced-motion
  setting the same way.
- `AnimatedCounter` is split by responsibility (`DigitRollEngine`, one
  `resolveDigitMotion` shared by the painter and widget-tree paths, part files
  for config / timeline / scope / measure / tint / controller binding / state).
  Behaviour is unchanged.
- `AnimatedCounter` honours `MediaQuery.disableAnimations`; the direction tint
  is driven by the shared ticker and no longer rebuilds during the fade.
- `RingCounter` / `RingCountdown` / `BarCounter` / `BarCountdown` keep one
  painter alive and repaint through a `Listenable`; semantics update only when
  the integer percentage changes.
- The three controllers moved to `lib/src/controllers/` (imports through
  `package:countman/countman.dart` are unchanged).
- A runState written during build is published at the end of the frame, so
  listeners may call `setState` safely.
- `animateOnce` without a stable id or without a provider no longer asserts: it
  logs one debug warning and plays the animation every time.
- `FlipCardPainter.controller` is relaxed to `Animation<double>` (an
  `AnimationController` is still accepted). The cards own no Flutter Ticker and
  keep the calendar round trip, one-way transitions, reduced-motion behaviour
  and pixel output.
- `DialCountdown` tick rings and `CardCountdown` card faces reuse global LRU
  bitmap caches (about 32 MiB / 8 MiB by RGBA bytes). On a failed or over-budget
  bitmap they fall back to vector drawing; fade and custom flip painters stay on
  the vector path.
- `CardCountdown` shares glyph caches across equal styles and reuses painter
  glyph references and rotation matrices, reducing memory and paint overhead
  without API or visual changes. Clarified calendar's two-segment duration.

### Fixed
- `slideScale` on the painter path no longer scales the slide offset with the
  canvas, matching the widget-tree path.
- `CountmanTheme` card styles apply when there is no `CardCountdownProvider`.
- Flip fade keeps the separately composited background and digit opacity; tick
  glow and the large glyphs / text shadows of a rotated card survive through the
  bitmap margin, and calendar half-cards are still clipped to the card face.
- fps vsync alignment drift (a precise Countdown at 30 fps dropping to 20 fps on
  60 Hz) and empty Counter polling frames: the display grid is fixed and wake-ups
  align to the screen refresh rate with a half-vsync tolerance; there is no
  throttling at the refresh rate, and display buckets, completion and thresholds
  never fire early.

### Deprecated
- The 38 flat `AnimatedCounter` / `AnimatedCounterBuilder` parameters that
  duplicate `format` / `timeline` / `style` (for example `fractionDigits`,
  `duration`, `textStyle`). Behaviour and precedence are unchanged; move them
  into `CounterFormat` / `CounterTimeline` / `AnimatedCounterStyle`.
- Provider `*Style` parameters on `CounterProvider`, `CountdownProvider`,
  `ElapsedProvider` and `CountmanProvider`: use `CountmanTheme`.
- `CountdownProvider.animateOnce`: countdowns have no entrance animation, so the
  flag has no effect.

## 0.2.5

### Fixed
- Controllers (`CounterValueController`, `CountdownController`,
  `ElapsedController`, `AnimatedCounterController`) stay bound when a widget is
  re-keyed or a controller is handed from one widget to another in the same
  frame; the old widget's dispose no longer detaches the new binding.
- Swapping only the `controller` no longer restarts the task: countdowns keep
  their remaining time and pause state, stopwatches keep their elapsed time,
  counters don't replay, and no lifecycle callbacks fire.
- `CounterValueController.update()` after the animation finished,
  `CountdownController.reset()` after completion and `ElapsedController.reset()`
  after `cancel()` now relaunch the task instead of doing nothing.
- `CounterBuilder` calls the current `onComplete` / `onReady` / `onStart` /
  `onCancel` instead of the ones captured at mount.
- A throwing task callback no longer starves the other tasks of the same group
  or stops the shared ticker; a task whose `onComplete` throws is still removed
  and the group still drains. `Countman.destroy()`, plugin disposal and
  `StartScheduler` batches isolate callback exceptions too (reported through
  `FlutterError.reportError`), and cancelling an owner inside a running batch
  skips its pending start.
- Countdown completion and thresholds are checked every frame (display updates
  are still throttled by `interval`): `onComplete` fires on the deadline frame
  instead of up to one interval late, and `Duration.zero` / past deadlines
  complete on the first frame. Each clock group reads the clock once per frame.
- `ElapsedHandle.pause` / `resume` / `reset` are no-ops after `cancel()`.
- `RingCounter` / `BarCounter` forward their `ValueKey` to animate-once, so they
  no longer assert under `CounterProvider(animateOnce: true)`.
- Ring painter: progress scales the cap-adjusted sweep, so a full ring moves
  from the first tick instead of freezing for the first ~3.5 % (about two
  minutes of a one-hour countdown); the thumb no longer paints outside the
  widget bounds.
- Ring and bar painters resolve directional gradients (`AlignmentDirectional`)
  with the ambient `Directionality` instead of throwing every frame.
- `AnimatedCounter` / `AnimatedCounterBuilder`:
  - retargeting mid-roll continues from the on-screen value (including each
    column's fractional progress) instead of jumping to the previous target;
  - `fast` mode shows a static non-zero `initialValue`, collapses old leading
    digits after completion, and the builder path's group separators follow
    the same visibility rule;
  - `jumpTo` lands immediately even when it targets the running animation's
    value, skipping `startDelay`, stagger and bounce;
  - `resume()` only resumes a paused animation (no replay or duplicate
    `onAnimationEnd` after completion); `restart()` during `startDelay` keeps
    the new target; commands issued from `onAnimationStart` are no longer
    overwritten by the outer transition;
  - changing only `minValue` / `maxValue` re-renders the digits;
  - `increasingColor` / `decreasingColor` now tint the digits on both paths
    (quantized palette, no per-frame text re-layout);
  - horizontal `slide` (`flipDirection: left/right`) moves along the x-axis on
    the painter path as well;
  - compact-notation semantics read the displayed value (`1.2M`, not `12`);
  - status listeners receive `forward` / `reverse` / `completed` / `dismissed`.
- `CardCountdown`: hour cells expand as needed (100 h and more no longer
  squeeze `12` into one cell); toggling `showHours` uses the live remaining
  time; the screen-reader value updates every tick; identical consecutive
  ticks no longer restart the flip; flip and fade keep the card and text
  colors' own alpha; glyph caches drop stale styles and the shared cache is
  bounded.
- `DialCountdown`: the inner ring draws at most four arcs regardless of the
  total duration (a 30-day countdown used to draw tens of thousands per
  paint); repaired garbled characters in the API docs.
- `OdometerCounter`: non-finite `from` / `to` are treated as 0 instead of
  throwing; `onComplete` reports the clamped displayed value.
- `fractionDigits` / `compactFractionDigits` above 20 are rejected by an assert
  (they used to throw a `RangeError` while building semantics).

### Added
- `CardCountdown.showDays` / `dayLabel` for a leading days unit.
- `RingCounter.animateOnce` / `BarCounter.animateOnce`.
- `textDirection` on `RingPainter` / `BarPainter` (and `ringPainterFrom` /
  `barPainterFrom`) to resolve directional gradients.
- `ElapsedHandle.isDone`.

### Changed
- Minimum SDK is Flutter 3.35 / Dart 3.9. The package already needed it:
  `@internal` is imported from `package:flutter/foundation.dart`, which only
  exports it since Flutter 3.35.
- `BarStyle.width` / `height` are literal layout sizes; a vertical bar without
  explicit sizes now defaults to 8×200 (it used to be 200×8).
- The published package no longer ships the stray `flutter_01.log`; added a
  `.pubignore`.

### Deprecated
- `thousandSeparatorWidget` / `decimalSeparatorWidget` on `AnimatedCounter`:
  the painter path never rendered them. Use `AnimatedCounterBuilder`.

## 0.2.4

### Added
- Add `CounterTimeline` for immutable animation configuration on
  `AnimatedCounter` and `AnimatedCounterBuilder` via `timeline`; non-null
  fields override loose parameters, null fields fall back, and value-equal
  configurations preserve the running animation and painter.
- Add `CounterFormat` for shared immutable formatting configuration on
  `AnimatedCounter` and `AnimatedCounterBuilder`; non-null object fields
  override loose parameters, while null fields fall back to them.

## 0.2.3

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
