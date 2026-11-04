---
name: countman
description: Work on countman — a high-performance Flutter counter/countdown/elapsed animation library with a shared scheduleFrameCallback ticker. Use when adding features, widgets, fixing bugs, or optimizing this package.
---

# countman

One shared `scheduleFrameCallback` (`Countman`) drives all animations; engines
are pluggable `CountmanPlugin` instances. No per-widget `Timer.periodic`. Since
0.3.0 the ticker **sleeps between updates** (one global `Timer`) instead of
rendering a frame per vsync. `CardCountdown` is the one widget that keeps an
`AnimationController` per card (kept on purpose, see DECISIONS.md).

Design history and overturned decisions: `DECISIONS.md`. Architecture:
`ARCHITECTURE.md`. Upgrade notes: `MIGRATION.md`.

## Architecture

```
Countman (static singleton — 1 scheduleFrameCallback + 1 sleep Timer)
  └── CountmanPlugin (each instance = independent task queue / "group")
       ├── Counter    — TaskQueuePlugin; number interpolation, every frame while animating
       ├── Countdown  — ClockPlugin; relative (monotonic) or absolute (wall) deadlines
       └── Elapsed    — ClockPlugin; stopwatch, since/initial/limit, laps
```

`Countman` API: `use(plugin)`, `start()`, `stop()`, `unuse(plugin, {dispose})`,
`destroy()`. Registry is **by instance**: same instance twice is a no-op, a
*different* instance with an existing `name` asserts in debug (release
registers it). Create plugins at module / long-lived-state level and reuse the
instance; a page-owned group is removed in `dispose` with `Countman.unuse`.

---

## Engines and the tick contract

`CountmanPlugin.tick(elapsed, dt)` returns **microseconds until the next call**:
`CountmanPlugin.idle` (-1, nothing to do), `nextFrame` (0) or a positive delay.
`Countman` takes the minimum: anything ≤ 20 ms (or a pending request) → next
frame; larger → arm the global sleep `Timer`; all idle → stop. `dt` is **0 on
the first frame after a sleep**, so sleeping plugins read a clock, never sum
`dt`. `onDetach()` is required (called by `unuse`/`destroy`; may re-attach);
`dispose()` is final.

- `TaskQueuePlugin<T extends CountmanTask>` — task map, ids, lazy self-register
  on first `enqueue`, deferred structural changes during tick, group events
  (`onFirstEnqueued` / `onQueueDrained` / `addGroupListener`). Subclasses
  implement `renderInitial`, `step` (both `void`), optionally `nextWake(task)`
  (default `nextFrame`), `afterInitial`, `onDispose`.
- `ClockPlugin<T extends ClockTask>` (`interval` ms, `clock`) — reads the clock
  once per frame (`frameWallMicros` / `frameMonotonicMicros`, integer µs). Each
  task updates when **its own** value crosses a multiple of `interval`
  (display bucket); completion and threshold are checked every frame. Hooks:
  `valueMicrosOf`, `displayMicrosOf` (rounding), `totalOf`, `isComplete`,
  `boundaryWake`, `completionWake`, `thresholdWake`, `onComplete`.
- `CountmanClock` — `wallMicros()` + `monotonicMicros()`. `SystemClock`
  (default `CountmanClock.system`, replaceable; adds back deep-sleep time on
  foreground resume), `OffsetClock(base, offset)` (server time, wall only),
  `ManualCountmanClock` (`advance` / `jumpWall` / `suspend`). `countdownClock` /
  `elapsedClock` are `SystemClock`'s raw sources.
- Clock semantics: `Duration` countdowns and stopwatches → monotonic;
  `deadline` / widget `to` as DateTime/int/String / `ElapsedOptions.since` →
  wall. Pause/resume/`reset()` re-anchor on monotonic. `CountdownOptions`:
  exactly one of `duration` / `deadline`; also `total`, `rounding`
  (`CountdownRounding.floor/ceil`, display only).
- `ElapsedOptions`: `since` XOR `initial`, `limit` + `onComplete`;
  `ElapsedHandle.lap()` / `laps` / `updateLimit`.

---

## Public names (current)

**Display widgets**
- Counter family: `TextCounter`, `RingCounter`, `BarCounter`, `OdometerCounter`,
  `AnimatedCounter`, `AnimatedCounterBuilder`, `CounterBuilder`
- Countdown family: `TextCountdown`, `RingCountdown`, `BarCountdown`,
  `DialCountdown`, `CardCountdown`, `CountdownBuilder`
- Elapsed family: `TextElapsed`, `ElapsedBuilder`
- `CounterBuilder.listenable` / `CountdownBuilder.listenable`: values via
  `ValueListenable`, no per-tick rebuild. `builder` field is nullable.

**Controllers** (`lib/src/controllers/`; imports unchanged)
- `CounterValueController` — `update({to,duration,curve})`, `pause`/`resume`/
  `cancel`/`restart`, `value`, `isAnimating`/`isPaused`/`isDone`
- `CountdownController` — `pause`/`resume`/`reset({duration})`/`restart`/
  `cancel`, `remaining`/`isPaused`/`isDone`
- `ElapsedController` — `pause`/`resume`/`reset`/`restart`/`cancel`/`lap`,
  `elapsed`/`laps`/`isPaused`
- `AnimatedCounterController` — `animateTo`/`jumpTo`/`pause`/`resume`/`stop`/
  `restart`/`repeat({reverse})`/`reverse`, `status`, `addStatusListener`
- All four mix in `CountmanRunStateNotifier`: `runState` (`CountmanRunState`
  idle/running/paused/completed) + `runStateListenable` (listen with
  `ValueListenableBuilder`). The three plain controllers also have `dispose()`.
  `$` members are `@internal`.
- Binding is owner-checked and survives re-keying / hand-off; `update` (counter)
  and `reset` (countdown/elapsed) relaunch a finished task.

**Engines / helpers** — `Counter`/`Countdown`/`Elapsed` (`name`, `interval`,
`clock`); `counter()`/`countdown()`/`elapsed()`; defaults `defaultCounter`,
`defaultCountdown`, `defaultElapsed`, `defaultCountdownMs`, `defaultElapsedMs`
(interval 0); handles `CounterHandle`/`CountdownHandle`/`ElapsedHandle`;
options `CounterOptions`/`CountdownOptions`/`ElapsedOptions`; `CountmanTask`,
`ClockTask`, `TaskQueuePlugin`, `ClockPlugin`, `CountmanContext`.

**Providers** — `CounterProvider`, `CountdownProvider`, `ElapsedProvider`,
`CountmanProvider`, `CardCountdownProvider` (+ glyph cache). Provider `*Style`
params and `CountdownProvider.animateOnce` are **deprecated**.

**Styles / theme** — `CountmanTextStyle` (aliases `TextCounterStyle`/
`TextCountdownStyle`/`TextElapsedStyle`); `RingStyle` (aliases
`RingCounterStyle`/`RingCountdownStyle`); `BarStyle` (aliases `BarCounterStyle`/
`BarCountdownStyle`); `OdometerCounterStyle`; `DialCountdownStyle` (+ `Dial*Config`);
`CardCountdownStyle`; `AnimatedCounterStyle`. Every style: `decoration` +
`padding`, immutable, `copyWith`/`merge`/static `lerp`. **`CountmanTheme`**
(`ThemeExtension`, `maybeOf`/`of`) holds app-wide defaults. Style resolution:
widget `style` > Provider `*Style` (deprecated) > `CountmanTheme` > built-in.
**No loose visual params** — use `style:`.

**AnimatedCounter config objects** — `CounterFormat` (fractionDigits,
wholeDigits, hideLeadingZeroes, thousandSeparator, groupingPattern,
decimalSeparator, compact*, showPositiveSign, numeralSystem/Mapper;
`format(value, {minValue,maxValue})` returns the at-rest string),
`CounterTimeline` (duration, curve, reverse*, startDelay, speedMultiplier,
stagger*, autoEaseThreshold, curveForDigit, interpolation, bounceOvershoot,
`fast`), `AnimatedCounterStyle`. The 38 flat params duplicating them are
`@Deprecated`; object non-null fields win, nulls fall back.

**Formatters** — `CountdownFormat.{hms, ms, msTenths, msMillis, dhms, dhm, auto}`
and `CountdownFormat.template(pattern)` (tokens `{d} {H} {HH} {TH} {m} {mm}
{TM} {s} {ss} {S} {SSS}`, parsed once). `DurationFormatter = String Function(TimeParts)`.

**Counter transition** — `CounterTransition` (`CounterMotion` none/slide/rotate/
flip + `scale`/`fade`/`blur`; presets `.slide`(default)/`.slideScale`/
`.slideBlur`/`.rotate`/`.flip`/`.flipFade`).

**Enums** — `StaggerDirection`, `NumeralSystem`, `CountdownType`
(calendar/slide/flip), `SlideEffect` (none/enter/exit/both), `CountdownRounding`.

**Other** — `TimeParts`, `StartScheduler`, `painter/painter.dart` painters
(`CounterPainter`, `RingPainter`, `BarPainter` — optional `progressListenable`,
`FlipCardPainter`, subclassable).

---

## File map

| File | Role |
|---|---|
| `lib/src/core/ticker.dart` | `Countman` — `use`/`start`/`stop`/`unuse`/`destroy`, sleep-aware `_loop` |
| `lib/src/core/types.dart` | `CountmanPlugin` (int `tick`, `onDetach`) + `CountmanContext` |
| `lib/src/core/plugin_base.dart` | `TaskQueuePlugin<T>`, `ClockPlugin<T>`, `CountmanTask`, `ClockTask`, `LazyDefault` |
| `lib/src/core/clock.dart` | `CountmanClock`, `SystemClock`, `OffsetClock`, `ManualCountmanClock`, `countdownClock`/`elapsedClock` |
| `lib/src/core/run_state.dart` | `CountmanRunState`, `CountmanRunStateNotifier` (build-phase writes published at frame end) |
| `lib/src/core/time_parts.dart` | `TimeParts` — reused per task, mutated in place |
| `lib/src/core/start_scheduler.dart` | `StartScheduler` batch startup |
| `lib/src/counter/{plugin,types}.dart` | `Counter`, `CounterHandle`, `counter()`, `CounterOptions` |
| `lib/src/count_down/{plugin,types}.dart` | `Countdown`, `CountdownFormat`, `CountdownRounding`, `resolveDeadline`, `remainingUntil`, `countdownAnchorOf` |
| `lib/src/elapsed/{plugin,types}.dart` | `Elapsed`, `ElapsedHandle` (laps), `elapsed()` |
| `lib/src/controllers/*.dart` | the three plain controllers |
| `lib/src/widgets/{counter,countdown,elapsed}_builder.dart` | Builders — plugin resolution, migration, controller binding |
| `lib/src/widgets/scope_resolution.dart` | `resolvePlugin` / `resolvePluginDependent` / `reduceMotionOf` |
| `lib/src/widgets/countman_theme.dart` | `CountmanTheme` |
| `lib/src/widgets/{providers,animate_once,reduce_motion,style_support,progress_display}.dart` | providers, animate-once registry, shared style/color helpers |
| `lib/src/widgets/{text,ring,bar}_*.dart`, `dial_countdown.dart`, `odometer_counter.dart` | display widgets; `{ring,bar}_style.dart` = `RingStyle`/`BarStyle` |
| `lib/src/widgets/card_countdown{,_types,_provider}.dart` | `CardCountdown`, `CountdownType`/`SlideEffect`, provider |
| `lib/src/widgets/animated_counter/animated_counter.dart` | library root: `AnimatedCounter`, painter path; `part`s below |
| `…/animated_counter/_base_counter.dart` | shared widget params |
| `…/_counter_{config,timeline,scope,measure,tint,controller_binding,state}.dart` | flat/format/timeline merge · duration/curve resolve · provider plugin/animate-once/reduce-motion · formatting & semantics · direction tint · controller wiring · playback state machine |
| `…/animated_counter/custom_digit_counter.dart` | `AnimatedCounterBuilder` (widget-tree path) |
| `…/animated_counter/digit_roll_engine.dart` | pure-Dart `DigitRollEngine` (package-internal) |
| `…/animated_counter/digit_motion.dart` | `resolveDigitMotion` / `DigitMotion` — single source of motion maths |
| `…/animated_counter/{counter_format,counter_timeline,counter_controller,types,digit_column}.dart` | `CounterFormat`, `CounterTimeline`, `AnimatedCounterController`, enums, widget-path column |
| `lib/src/widgets/painter/painter.dart` | painter exports |

---

## Widget API (concise)

```dart
// Counter — from/to/duration(1000ms)/curve(easeOut)/allowNegative/plugin/
//   controller(CounterValueController)/onUpdate/onComplete/onReady/onStart/
//   onCancel/animateOnce
TextCounter(to: 9999, prefix: '¥', fractionDigits: 2,
  style: TextCounterStyle(textStyle: TextStyle(fontSize: 32)))
RingCounter(to: 100, style: RingCounterStyle(size: 80), center: TextCounter(to: 100))
BarCounter(to: 100, style: BarCounterStyle(width: 240, vertical: false))
OdometerCounter(to: 9999, groupSeparator: ',', bounceOvershoot: 0.3,
  style: OdometerCounterStyle(numberTextStyle: TextStyle(fontSize: 40)))
CounterBuilder(to: 9999, builder: (ctx, value, child) => Text('${value.toInt()}'))

// AnimatedCounter — value/controller/plugin/animateOnce/transition/prefix·infix·suffix/
//   flipDirection/minValue/maxValue/initialValue/triggerHaptics/repaintBoundary/
//   semanticsLabel/painterBuilder + format/timeline/style objects
AnimatedCounter(
  value: 1234.56, prefix: r'$',
  format: CounterFormat(fractionDigits: 2, thousandSeparator: ',', groupingPattern: [3]),
  timeline: CounterTimeline(duration: Duration(seconds: 2), staggerDelay: Duration(milliseconds: 30)),
  style: AnimatedCounterStyle(textStyle: TextStyle(fontSize: 40), increasingColor: Colors.green))
// Currency = prefix + groupingPattern (USD [3], CNY [4], INR [3,2]); no .usd/.cny/.inr ctors
AnimatedCounterBuilder(value: 1234, digitBuilder: (ctx, d, s) => Text('$d', style: s))

// Countdown — to: Duration(monotonic) | DateTime|int(ms epoch)|ISO String (wall);
//   plugin/precise/controller/total/rounding/onComplete/onTick(TimeParts)/
//   threshold+onThreshold/onReady/onStart/onCancel/onPause/onResume
TextCountdown(to: Duration(minutes: 5), formatter: CountdownFormat.ms)
TextCountdown(to: deadline, rounding: CountdownRounding.ceil,
  formatter: CountdownFormat.template('{d}天 {HH}:{mm}:{ss}'))
TextCountdown(to: Duration(seconds: 10), precise: true, formatter: CountdownFormat.msMillis)
RingCountdown(to: end, total: end.difference(start),
  style: RingCountdownStyle(size: 100))                         // showThumb default ON
BarCountdown(to: Duration(minutes: 1), style: BarCountdownStyle(width: 250))
DialCountdown(to: Duration(minutes: 5), style: DialCountdownStyle(size: 200, glow: true),
  builder: (ctx, parts) => Text('${parts.minutes}:${parts.seconds}'))
CardCountdown(to: Duration(hours: 1, minutes: 30), labels: ['H','M','S'],
  showDays: false, dayLabel: 'D', semanticsLabel: 'Countdown',   // hour/day cells grow (100 h+)
  style: CardCountdownStyle(splitDigits: true, transitionType: CountdownType.slide))
CountdownBuilder(duration: Duration(minutes: 5),
  builder: (ctx, parts, child) => Text(CountdownFormat.ms(parts)))

// Elapsed — plugin/precise/controller/since|initial/limit+onComplete/onTick/
//   threshold+onThreshold/lifecycle
TextElapsed(formatter: CountdownFormat.hms)
TextElapsed(since: orderTime, limit: Duration(minutes: 30), onComplete: () {})
ElapsedBuilder(builder: (ctx, parts, child) => Text(CountdownFormat.hms(parts)))

// App-wide default styles
MaterialApp(theme: ThemeData(extensions: [
  CountmanTheme(ringCounterStyle: RingCounterStyle(size: 96))]))
```

### Direct engine use

```dart
counter(CounterOptions(to: 100, onUpdate: (v) {}, onComplete: (v) {}));
countdown(CountdownOptions(duration: Duration(minutes: 1), onUpdate: (parts) {},
  threshold: Duration(seconds: 10), onThreshold: () {}));
countdown(CountdownOptions(deadline: DateTime(2026, 12, 31), total: Duration(days: 30)));
final e = elapsed(ElapsedOptions(limit: Duration(minutes: 5), onComplete: () {}));
e.lap();

final g = Countdown(name: 'auction', interval: 0, clock: OffsetClock(CountmanClock.system, offset));
Countman.use(g);                       // by instance; unique name
CountdownBuilder(duration: ..., plugin: g, builder: ...);
```

### Custom plugin sketch

```dart
class Beat extends TaskQueuePlugin<BeatTask> {
  Beat() : super('beat');
  @override void renderInitial(BeatTask t) {}
  @override void step(BeatTask t, double dtMs) { /* read a clock, not dt, if you sleep */ }
  @override int nextWake(BeatTask t) => /* µs until due, or CountmanPlugin.nextFrame */ 1000000;
}
```

### TimeParts

`days/hours(0-23)/minutes(0-59)/seconds(0-59)/millis(0-999)`;
`totalHours/totalMinutes/totalSeconds`; `inDays/inHours/…/inMicroseconds`;
`value` (Duration), `total` (countdown only), `progress` (0–1), `parts` (live
`[d,h,m,s,ms]`). Mutated in place per tick — read synchronously, don't retain.

---

## Design invariants (do NOT break)

1. **Zero-allocation hot path** — `Counter.step()`, clock plugin ticks and
   `resolveDigitMotion` must not allocate. Reuse task state, the per-task
   `TimeParts`, the `DigitMotion` / `DigitPhase` holders.
2. **Sleep, don't poll** — clock tasks give an accurate `nextWake`; never rely
   on being ticked every frame. `interval: 0` / `precise` groups cannot sleep.
   Sleeping plugins read a clock; `dt` is 0 after a sleep.
3. **Per-task boundary** — task callbacks run inside `TaskQueuePlugin.tick`'s
   per-task try/catch/finally (errors → `FlutterError.reportError`; done tasks
   always evicted; `Countman` also isolates per plugin). Keep new callback
   paths inside it. `revision` invalidates a frame after a callback pauses /
   resets / retargets.
4. **Clock once per frame** — `beginFrame` drops the snapshot; read
   `frameWallMicros` / `frameMonotonicMicros` lazily. Completion/threshold every
   frame; only display updates are bucketed by `interval`.
5. **Persistent painter** — `CounterPainter` / `RingPainter` / `BarPainter` /
   `FlipCardPainter` created once per widget lifetime (or config change),
   updated in place via `update()` / `progressListenable` + `repaint:
   Listenable`. Never recreate per frame.
6. **runState written during build is published at frame end** — `runState`
   getter is always current, `runStateListenable` notifies post-frame (one
   notification per frame), so listeners may `setState`.
7. **Controller binding is owner-checked** — `controller.attach(handle,
   relaunch: …, restart: …)` / `controller.detach(handle)` (never bare
   `detach()`); `AnimatedCounterController` uses `$owner`. Swapping only the
   controller re-binds, never restarts. With no task (animate-once skip) bind
   `Counter.detachedHandle()` — never add+cancel a placeholder (fires group
   callbacks).
8. **Plugin change migrates, never restarts** — Builders move the live task to
   the new plugin (remaining/elapsed, total, laps, pause state, displayed
   value; old task cancelled quietly: no user `onCancel`/`onPause`).
9. **`requestFrame()` on every `add()`** — `Countman.start()` is idempotent and
   interrupts a sleep; omitting means tasks added while idle never start.
10. **`StartScheduler.instance.cancel(this)` in `dispose()`** for widgets that
    enqueue via `StartScheduler`, else the closure leaks the `State`.
11. **No `Opacity` for fades** — use `color.withValues(alpha:)`; `Opacity` forces
    `saveLayer` every fractional-alpha frame.
12. **dt accumulation only for `Counter`** — it is frame-driven; Flutter's
    first-frame `elapsed` is unreliable in tests.

---

## Gotchas

- **Web compile** — never write integer literals above 2^53 (e.g.
  `0x7fffffffffffffff`, often used as a clamp max): dart2js can't represent
  them, `clamp` becomes `num`, and the web build (the example is deployed to
  GitHub Pages) fails while VM tests stay green.
- **SDK floor is Flutter 3.35 / Dart 3.9** — `@internal` is imported from
  `package:flutter/foundation.dart`, exported only since 3.35. Verify the
  floor with `E:/sdk/flutter-3.35.7` on a `git archive` copy.
- **Same-name plugins** — a different instance with an existing `name` asserts
  in debug; reuse the instance or pick a unique name; `Countman.unuse(g)` in
  `dispose` for page-owned groups.
- **Tests** — prefer `ManualCountmanClock` (`Countdown(name:…, clock:…)` or
  `CountmanClock.system = …`, restore afterwards) over replacing
  `countdownClock`. After a sleep the first frame has `dt == 0`.
- **`CountdownOptions`** needs exactly one of `duration` / `deadline` (assert).
  `to: Duration` is monotonic; DateTime/int/String is wall.
- **all-nines targets** (9, 99, 999, …): `AnimatedCounter` animates to `n − ε`
  then snaps at completion (`isAllNinesTarget`); `OdometerCounter`/`TextCounter`
  unaffected.
- **`autoEaseThreshold: 100000`** — with the default `Curves.linear` and a range
  above this, `easeInOut` is auto-applied. Set `double.infinity` to disable.
- **`blur`/`flip` transitions** and `digitBuilder`/`digitTransitionBuilder`
  force the widget path (~0.85 ms/digit/frame) — avoid at scale.
- **`repaintBoundary` at scale** — for >~10 concurrent instances set `false` and
  let one ancestor layer composite the grid.
- **`CardCountdown` cost** is its transition's cost (calendar ≈ 90 % of each
  second in motion, slide/flip ≈ 45 %); shorten `duration` to reduce it.
- **`animateOnce`** needs a stable `ValueKey` (or `onceId`) and a provider to
  register against; otherwise it degrades to always-animate with one debug
  warning (no assert).
- **Deprecated, don't use in new code** — flat `AnimatedCounter` params that
  `format`/`timeline`/`style` cover; Provider `*Style` params (use
  `CountmanTheme`); `CountdownProvider.animateOnce`.
- **Windows line endings** — repo files may be CRLF (`core.autocrlf`); keep each
  file's existing style, and `.sh` scripts must be LF.

---

## Referenced libraries

### flip_counter_plus (MIT)

- GitHub: https://github.com/Itsxhadi/flip_counter_plus
- Used by: `AnimatedCounter` (`DigitColumn` + structure adapted from
  `AnimatedFlipCounter`).
- Changes: `AnimationController` → `Counter` on shared ticker; per-frame
  `setState` → persistent `CounterPainter` + `ValueNotifier` repaint trigger;
  roll transition `Positioned` → `Transform.translate + ClipRect`; all-nines
  target adjustment; `_effectiveFlipDirection` auto-reversal on decrease.

> `OdometerCounter` is **not** backed by the `odometer` package — it is a thin
> wrapper over `AnimatedCounter` (painter path) with fixed-width leading zeros.
