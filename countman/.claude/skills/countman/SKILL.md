---
name: countman
description: Work on countman — a high-performance Flutter counter/countdown/elapsed animation library with a shared scheduleFrameCallback ticker. Use when adding features, widgets, fixing bugs, or optimizing this package.
---

# countman

One shared `scheduleFrameCallback` (`Countman`) drives all animations; engines
are pluggable `CountmanPlugin` instances. No `AnimationController`, no
`Timer.periodic` (except `CardCountdown`, which uses one `AnimationController`
per card for its flip painter).

## Architecture

```
Countman (static singleton — 1 scheduleFrameCallback)
  └── CountmanPlugin interface (each instance = independent task queue / "group")
       ├── Counter    — number interpolation every frame; auto-registered via counter()
       ├── Countdown  — wall-clock deadline timers; interval-gated (default 1 s; 0 = every frame)
       └── Elapsed    — wall-clock elapsed timers; same interval API
```

`Countman.use(plugin)` registers by name — **duplicate names are silently
ignored**. Create plugins at module level or in long-lived state; never inside
`initState` of a widget that can be recreated (e.g. after a reset key), or the
second instance never receives `onAttach` and throws `LateInitializationError`
on first `add()`.

`Countman` API: `use(plugin)`, `start()`, `stop()`, `destroy()`.

---

## Public names (current)

**Display widgets**
- Counter family: `TextCounter`, `RingCounter`, `BarCounter`, `OdometerCounter`,
  `AnimatedCounter`, `AnimatedCounterBuilder`, `CounterBuilder`
- Countdown family: `TextCountdown`, `RingCountdown`, `BarCountdown`,
  `DialCountdown`, `CardCountdown`, `CountdownBuilder`
- Elapsed family: `TextElapsed`, `ElapsedBuilder`

**Controllers**
- `CounterValueController` — counter family: `update({to,duration,curve})`,
  `pause`/`resume`/`cancel`, `value`, `isAnimating`/`isPaused`/`isDone`
- `AnimatedCounterController` — AnimatedCounter(Builder): `animateTo`/`jumpTo`/
  `pause`/`resume`/`stop`/`restart`/`repeat({reverse})`/`reverse`, `status`,
  `addStatusListener`
- `CountdownController` — `pause`/`resume`/`reset({duration})`/`cancel`,
  `remaining`/`isPaused`/`isDone`
- `ElapsedController` — `pause`/`resume`/`reset`/`cancel`, `elapsed`/`isPaused`

**Engines / helpers** — `Counter`/`Countdown`/`Elapsed` (`name`, `interval`);
top-level `counter()`/`countdown()`/`elapsed()`; defaults `defaultCounter`,
`defaultCountdown`, `defaultElapsed`, `defaultCountdownMs`, `defaultElapsedMs`
(interval 0); handles `CounterHandle`/`CountdownHandle`/`ElapsedHandle`; options
`CounterOptions`/`CountdownOptions`/`ElapsedOptions`.

**Providers** — `CounterProvider`, `CountdownProvider`, `ElapsedProvider`,
`CountmanProvider` (all three), `CardCountdownProvider` (+ glyph cache).

**Styles** — `CountmanTextStyle` (aliases `TextCounterStyle`/`TextCountdownStyle`/
`TextElapsedStyle`); `RingStyle` (aliases `RingCounterStyle`/`RingCountdownStyle`);
`BarStyle` (aliases `BarCounterStyle`/`BarCountdownStyle`); `OdometerCounterStyle`;
`DialCountdownStyle` (+ `DialColors`/`DialTicksConfig`/`DialArcConfig`/`DialInnerConfig`);
`CardCountdownStyle`; `AnimatedCounterStyle`. Every style has `decoration` +
`padding`; all immutable with `copyWith`/`merge`. **No loose visual params** —
use `style:`.

**Formatters** — `CountdownFormat.{hms, ms, msTenths, msMillis, dhms, dhm, auto}`.

**Enums** — `CounterTransitionType` (roll/fade/scale/fadeScale/rotate/flip/blur),
`StaggerDirection`, `NumeralSystem`, `CountdownType` (calendar/slide/flip),
`SlideEffect` (none/enter/exit/both).

**Other** — `TimeParts`, `StartScheduler`, `countdownClock` (injectable
`() → DateTime`), `painter/painter.dart` painters (`CounterPainter`,
`RingPainter`, `BarPainter`, `FlipCardPainter`, subclassable).

---

## File map

| File | Role |
|---|---|
| `lib/src/core/ticker.dart` | `Countman` static class — `use`/`start`/`stop`/`destroy`/`_loop` |
| `lib/src/core/types.dart` | `CountmanPlugin` + `CountmanContext` |
| `lib/src/core/plugin_base.dart` | `ClockPlugin<T>`, `TaskQueuePlugin<T>`, `ClockTask`, `CountmanTask` |
| `lib/src/core/time_parts.dart` | `TimeParts` — reused per-task, mutated in place |
| `lib/src/core/clock.dart` | `countdownClock` |
| `lib/src/core/start_scheduler.dart` | `StartScheduler` batch startup |
| `lib/src/counter/{plugin,types}.dart` | `Counter`, `CounterHandle`, `CounterValueController`, `counter()`, `CounterOptions` |
| `lib/src/count_down/{plugin,types}.dart` | `Countdown`, `CountdownController`, `CountdownFormat`, `resolveDeadline`, `remainingUntil` |
| `lib/src/elapsed/{plugin,types}.dart` | `Elapsed`, `ElapsedController`, `elapsed()` |
| `lib/src/widgets/counter_builder.dart` | `CounterBuilder` (`ValueNotifier<double>` + animate-once) |
| `lib/src/widgets/text_counter.dart` | `TextCounter` |
| `lib/src/widgets/odometer_counter.dart` | `OdometerCounter` + `OdometerCounterStyle` (self-drawn painter) |
| `lib/src/widgets/{ring,bar}_{counter,countdown}.dart` | ring/bar widgets |
| `lib/src/widgets/{ring,bar}_style.dart` | `RingStyle`/`BarStyle` + `*From` painter builders |
| `lib/src/widgets/dial_countdown.dart` | `DialCountdown` + style/configs + `_DialPainter` |
| `lib/src/widgets/card_countdown{,_types,_provider}.dart` | `CardCountdown`, `CountdownType`/`SlideEffect`, provider |
| `lib/src/widgets/countdown_builder.dart` | `CountdownBuilder` |
| `lib/src/widgets/{text_countdown,text_elapsed,elapsed_builder}.dart` | countdown/elapsed widgets |
| `lib/src/widgets/animated_counter/animated_counter.dart` | `AnimatedCounter` (+ `.usd/.cny/.inr`), painter fast path |
| `lib/src/widgets/animated_counter/{_base_counter,custom_digit_counter}.dart` | shared base; `AnimatedCounterBuilder` (widget path) |
| `lib/src/widgets/animated_counter/{counter_controller,types}.dart` | `AnimatedCounterController`, enums |
| `lib/src/widgets/providers.dart` | `CountmanScope`, `CounterProvider`/`CountdownProvider`/`ElapsedProvider`/`CountmanProvider` |
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

// AnimatedCounter — value/controller(AnimatedCounterController)/duration(300ms)/
//   curve(linear)/transitionType(roll)/fast(single-step per digit, old->new one
//     slot; all transitions; painter+widget paths)/fractionDigits/wholeDigits/thousandSeparator/
//   groupingPattern([3])/staggerDelay/staggerDirection/compactNotation/numeralSystem/
//   showPositiveSign/flipDirection/autoEaseThreshold(100000)/repaintBoundary/
//   style(AnimatedCounterStyle: text/affix/separator styles, increasingColor/
//   decreasingColor/colorFadeDuration, padding, decoration)/painterBuilder
AnimatedCounter(value: 1000000, transitionType: CounterTransitionType.roll,
  staggerDelay: Duration(milliseconds: 30), thousandSeparator: ',')
AnimatedCounter.usd(value: 1234.56)   // .cny grouping[4], .inr grouping[3,2]
AnimatedCounterBuilder(value: 1234, digitBuilder: (ctx, d, s) => Text('$d', style: s))

// Countdown — to: DateTime|Duration|int(ms epoch)|ISO String; plugin/precise/
//   controller(CountdownController)/onComplete/onTick(TimeParts)/threshold+
//   onThreshold/onReady/onStart/onCancel/onPause/onResume
TextCountdown(to: Duration(minutes: 5), formatter: CountdownFormat.ms)
TextCountdown(to: Duration(seconds: 10), precise: true, formatter: CountdownFormat.msMillis)
RingCountdown(to: Duration(minutes: 2), style: RingCountdownStyle(size: 100),
  center: TextCountdown(to: Duration(minutes: 2)))          // showThumb default ON
BarCountdown(to: Duration(minutes: 1), style: BarCountdownStyle(width: 250,
  gradient: LinearGradient(colors: [Colors.green, Colors.red])))
DialCountdown(to: Duration(minutes: 5), style: DialCountdownStyle(size: 200, glow: true),
  builder: (ctx, parts) => Text('${parts.minutes}:${parts.seconds}'))
CardCountdown(to: Duration(hours: 1, minutes: 30), labels: ['H','M','S'],
  style: CardCountdownStyle(splitDigits: true, transitionType: CountdownType.slide,
    scaleEffect: SlideEffect.both))
CountdownBuilder(duration: Duration(minutes: 5),
  builder: (ctx, parts, child) => Text(CountdownFormat.ms(parts)))

// Elapsed — plugin/precise/controller(ElapsedController)/onTick/threshold+onThreshold/lifecycle
TextElapsed(formatter: CountdownFormat.hms)
ElapsedBuilder(builder: (ctx, parts, child) => Text(CountdownFormat.hms(parts)))
```

### Direct engine use

```dart
counter(CounterOptions(to: 100, onUpdate: (v) {}, onComplete: (v) {}));
countdown(CountdownOptions(duration: Duration(minutes: 1), onUpdate: (parts) {},
  threshold: Duration(seconds: 10), onThreshold: () {}));
elapsed(ElapsedOptions(onUpdate: (parts) {}));

final g = Countdown(name: 'auction', interval: 0);  // 0 = every frame
Countman.use(g);
CountdownBuilder(duration: ..., plugin: g, builder: ...);
```

### TimeParts

`days/hours(0-23)/minutes(0-59)/seconds(0-59)/millis(0-999)`;
`totalHours/totalMinutes/totalSeconds`; `inDays/inHours/…/inMicroseconds`;
`value` (Duration), `total` (countdown only), `progress` (0–1), `parts` (live
`[d,h,m,s,ms]`). Mutated in place per tick — read synchronously, don't retain.

---

## Design invariants (do NOT break)

1. **Zero-allocation hot path** — `Counter.step()` / clock plugin ticks must not
   allocate. Reuse task state and the per-task `TimeParts`.
2. **Persistent painter** — `CounterPainter` / `_OdometerPainter` /
   `FlipCardPainter` created once per widget lifetime (or config change) and
   mutated in-place via `update()` + a `repaint: Listenable` (`markNeedsPaint`,
   not rebuild). Never recreate per frame.
3. **`StartScheduler.instance.cancel(this)` in `dispose()`** for any widget that
   enqueues via `StartScheduler` — else the closure leaks the `State`.
4. **No `Opacity` widget for fades** — use `color.withValues(alpha:)`. `Opacity`
   forces `saveLayer` every fractional-alpha frame.
5. **dt accumulation, not absolute elapsed** — `Counter.step` uses
   `accumMs += dtMs`; Flutter's first-frame `elapsed` is unreliable in tests.
6. **`requestFrame()` on every `add()`** — `Countman.start()` is idempotent;
   omitting means tasks added while idle never start.
7. **`precise: true`** drives on `defaultCountdownMs`/`defaultElapsedMs`
   (interval 0). Ignored when an explicit `plugin` is set.

---

## Gotchas

- **all-nines targets** (9, 99, 999, …): `AnimatedCounter` animates to `n − ε`
  then snaps at completion (`isAllNinesTarget`); `OdometerCounter`/`TextCounter`
  unaffected.
- **`autoEaseThreshold: 100000`** — with the default `Curves.linear` and a range
  above this, `easeInOut` is auto-applied. Set `double.infinity` to disable.
- **`blur`/`flip` transition types** and `digitBuilder`/`digitTransitionBuilder`
  force the widget path (~0.85 ms/digit/frame) — avoid at scale.
- **`repaintBoundary` at scale** — for >~10 concurrent instances set `false` and
  let one ancestor layer composite the grid.
- **`animateOnce`** needs a stable `ValueKey` (or `onceId`) and a provider to
  register against; degrades to always-animate otherwise.

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

> `OdometerCounter` is **not** backed by the `odometer` package — it uses a
> self-contained `CustomPainter` (`_OdometerPainter`) bundled in countman.
