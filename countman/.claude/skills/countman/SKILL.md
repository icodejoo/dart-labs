---
name: countman
description: Work on countman — a high-performance Flutter counter/countdown/elapsed animation library with a shared scheduleFrameCallback ticker. Use when adding features, widgets, fixing bugs, or optimizing this package.
---

# countman

`C:\workspace\dart-labs\countman`: one shared `scheduleFrameCallback` drives all
animations; engines are pluggable `CountmanPlugin` instances.

## Architecture

```
Countman (static singleton — 1 scheduleFrameCallback)
  └── CountmanPlugin interface (each instance = independent task queue / "group")
       ├── CountupPlugin  — number interpolation; auto-registered via countup()
       ├── Countdown      — wall-clock deadline timers; interval-gated (default 1 s; 0 = every frame)
       └── Elapsed        — wall-clock elapsed timers; same interval API
```

No `AnimationController`, no `Timer.periodic`.

`Countman.use(plugin)` registers by name — **duplicate names are silently ignored**.
Create plugins at module level or in long-lived state; never inside `initState` of a
widget that can be recreated (e.g. after a reset key), or the second instance will
never receive `onAttach` and throw `LateInitializationError` on first `add()`.

---

## File map

### Core engine

| File | Role |
|---|---|
| `lib/src/core/ticker.dart` | `Countman` static class — `use(plugin)`, `start()`, `stop()`, `destroy()`, `_loop()` frame callback |
| `lib/src/core/types.dart` | `CountmanPlugin` interface + `CountmanContext` (carries `requestFrame` callback) |
| `lib/src/core/start_scheduler.dart` | `StartScheduler` singleton — batch-drains startup closures across frames (`batch: N`) |

### Count-up engine

| File | Role |
|---|---|
| `lib/src/count_up/plugin.dart` | `CountupPlugin`, `CountupHandle`, top-level `countup()` |
| `lib/src/count_up/types.dart` | `CountupOptions`, `CountupTask` (internal mutable state per task) |

### Countdown engine

| File | Role |
|---|---|
| `lib/src/count_down/plugin.dart` | `Countdown` (extends `ClockPlugin`), `CountdownHandle`, `CountdownController`, `defaultCountdown`, top-level `countdown()` |
| `lib/src/count_down/types.dart` | `CountdownOptions`, `CountdownTask`, `CountdownFormat` (hms/ms/msTenths/msMillis/auto), `DurationFormatter`, `resolveDeadline`, `remainingUntil` |

### Elapsed engine

| File | Role |
|---|---|
| `lib/src/elapsed/plugin.dart` | `Elapsed` (extends `ClockPlugin`), `ElapsedHandle`, `defaultElapsed`, top-level `elapsed()` |
| `lib/src/elapsed/types.dart` | `ElapsedOptions`, `ElapsedTask` |

### Shared engine base

| File | Role |
|---|---|
| `lib/src/core/plugin_base.dart` | `ClockPlugin<T>` (interval accumulation + `beginFrame`), `TaskQueuePlugin<T>` (task map, concurrency-safe add/remove), `ClockTask`, `CountmanTask` |
| `lib/src/core/time_parts.dart` | `TimeParts` — reused per-task value object decomposed each tick: `days/hours/minutes/seconds/millis`, `totalSeconds`, `progress`, `value` |
| `lib/src/core/clock.dart` | `countdownClock` — replaceable `() → DateTime` used by countdown/elapsed; injectable in tests |

### Widgets

| File | Role |
|---|---|
| `lib/src/widgets/countup_builder.dart` | `CountupBuilder` — `StatefulWidget`, `ValueNotifier<double>` + `ValueListenableBuilder` |
| `lib/src/widgets/countup_text.dart` | `CountupText` — `StatelessWidget` wrapping `CountupBuilder`; prefix/suffix support |
| `lib/src/widgets/countup_odometer.dart` | `CountupOdometer` — per-digit slide via `OdometerTransition` (odometer pkg); `_fromFloat()` builds `OdometerNumber` directly from raw float |
| `lib/src/widgets/animated_countup/animated_countup.dart` | `AnimatedCountup` — full-featured widget (adapted from flip_counter_plus); CustomPainter fast path + widget fallback |
| `lib/src/widgets/animated_countup/counter_painter.dart` | `CounterPainter` — persistent `CustomPainter`; updated in-place each frame via `update()`; `repaint: Listenable` drives `markNeedsPaint`, not build |
| `lib/src/widgets/animated_countup/counter_controller.dart` | `CounterController` — `ChangeNotifier`-based programmatic API (`animateTo`, `jumpTo`, `pause`, `resume`, `reverse`, …) |
| `lib/src/widgets/animated_countup/digit_column.dart` | `DigitColumn` — widget fallback for `blur`/`flip` transition types or when `digitBuilder`/`digitTransitionBuilder` is provided |
| `lib/src/widgets/animated_countup/types.dart` | `CounterTransitionType`, `StaggerDirection`, `NumeralSystem` enums |
| `lib/src/widgets/countdown_widget.dart` | `CountdownBuilder` — `StatefulWidget`; `ValueNotifier<int>` rev-bump drives rebuild; `_handle?.cancel()` on dispose |
| `lib/src/widgets/text_countdown.dart` | `TextCountdown` — const-constructible countdown text |
| `lib/src/widgets/ring_countdown.dart` | `RingCountdown` — arc ring using `progress` (dimensionless) |
| `lib/src/widgets/bar_countdown.dart` | `BarCountdown` — horizontal bar using `progress` |
| `lib/src/widgets/dial_countdown.dart` | `DialCountdown` — analog 60-second face; rounds to nearest second intentionally |
| `lib/src/widgets/card_countdown.dart` | `CardCountdown` — split-flap/slide/flip card; wraps `AnimatedCounter` |
| `lib/src/widgets/text_elapsed.dart` | `TextElapsed` — same API as `TextCountdown`, counts up |
| `lib/src/widgets/providers.dart` | `CountdownProvider` — `InheritedWidget` cascading defaults + group callbacks |

---

## Widget API (concise reference)

### Countdown

```dart
// Basic
CountdownBuilder(
  duration: const Duration(minutes: 5),
  builder: (ctx, parts) => Text(CountdownFormat.ms(parts)),
)

// Millisecond precision — plugin must be a module-level singleton
final _msPlugin = Countdown(name: 'ms', interval: 1000 ~/ 60); // ~16 ms

class _State extends State<_Widget> {
  @override
  void initState() {
    super.initState();
    Countman.use(_msPlugin); // idempotent
  }
  @override
  Widget build(BuildContext context) => CountdownBuilder(
    duration: const Duration(seconds: 10),
    plugin: _msPlugin,
    builder: (_, parts) => Text(CountdownFormat.msMillis(parts)),
  );
}
```

CountdownFormat formatters: `hms` · `ms` · `msTenths` · `msMillis` · `auto`

### `CountupBuilder`

```dart
CountupBuilder(
  from: 0,              // optional start value
  to: 9999,            // required
  duration: Duration(milliseconds: 1000),
  curve: Curves.easeOut,
  repaintBoundary: true,
  builder: (context, value) => Text(value.toInt().toString()),
  onDone: (value) { },
)
```

### `CountupText`

```dart
CountupText(
  to: 9999,
  prefix: '¥',           // or prefixWidget: Widget (widget wins)
  suffix: ' pts',        // or suffixWidget: Widget (widget wins)
  formatter: (v) => v.toStringAsFixed(2),
  style: TextStyle(fontSize: 32),
  onDone: (v) { },
)
```

### `CountupOdometer`

```dart
CountupOdometer(
  to: 9999,
  letterWidth: 20,         // fixed width per digit slot
  verticalOffset: 20,      // slide distance in logical pixels
  numberTextStyle: TextStyle(fontSize: 40),
  groupSeparator: Text(','),
  prefix: '¥',             // or prefixWidget (widget wins)
  suffix: ' pts',          // or suffixWidget (widget wins)
)
```

### `AnimatedCountup`

```dart
AnimatedCountup(
  value: 1000000,
  duration: Duration(seconds: 2),
  transitionType: CounterTransitionType.roll,   // roll/fade/scale/fadeScale/rotate/flip/blur
  thousandSeparator: ',',
  fractionDigits: 2,
  staggerDelay: Duration(milliseconds: 30),
  compactNotation: true,         // 1_200_000 → "1.2M"
  repaintBoundary: true,
  autoEaseThreshold: 100000,
  batch: 5,                      // at most 5 starts per frame in dense grids
)

// Programmatic control
final ctrl = CounterController(initialValue: 0);
AnimatedCountup(controller: ctrl, value: 0)
ctrl.animateTo(9999);
ctrl.pause();   ctrl.resume();   ctrl.reverse();
```

---

## Design invariants (do NOT break)

1. **Zero-allocation hot path** — `CountupPlugin.tick()` must not allocate.
   It reuses `_tasks`, iterates values, appends to a fixed `done` list.
   No per-frame `Map`/`List` construction inside the loop.

2. **Persistent painter** — `CounterPainter` is created once per widget
   lifetime (or on config change) and mutated in-place via `update()`.
   Never recreate it every frame. The `repaint: Listenable` triggers
   `markNeedsPaint()` — not a widget rebuild.

3. **`_currentDigitValues` pre-initialization** — must be sized to `_maxDigits`
   elements before `build()` runs. `_startAnimationTransition` does:
   ```dart
   _currentDigitValues = List<double>.from(_oldDigitValues);
   ```
   If this is skipped, `SizedBox` width is computed from a stale/short list.

4. **`StartScheduler.instance.cancel(this)`** — must be called in every
   widget's `dispose()` that uses `batch:`. Omitting it leaks the closure
   and keeps the `State` alive in memory.

5. **`CountupOdometer`: no `Opacity` widget** — use `color.withValues(alpha:)`
   for fade effects. `Opacity` forces `saveLayer` on every fractional-alpha
   frame, which is the dominant GPU cost for per-digit animations.

6. **dt accumulation, not absolute elapsed** — `CountupPlugin.tick` uses
   `task.accumMs += dtMs` (delta accumulation). Never switch to absolute
   `elapsed.inMilliseconds` — Flutter's epoch adjustment makes the first-frame
   `elapsed` unreliable in tests (jumps to `Duration.zero`).

7. **`requestFrame()` on every `add()`** — when a task is enqueued, the
   plugin must call `_ctx.requestFrame()` even if the ticker is already
   running, because `Countman.start()` is idempotent. Omitting this means
   tasks added while the ticker is idle never start.

---

## Referenced libraries

### odometer `^3.0.0`

- Pub: https://pub.dev/packages/odometer
- GitHub: https://github.com/KirsApps/odometer
- License: MIT
- Used by: `CountupOdometer`
- Role: `OdometerNumber.fromDigits`, `OdometerTransition` for per-digit
  sliding. `_LiveOdometerAnimation` bridges the countman ticker to the
  `Animation<OdometerNumber>` interface without an `AnimationController`.
- Key decision: `OdometerNumber` is constructed via `_fromFloat(v)` directly
  (not `OdometerNumber.lerp`) — the fractional part of the float becomes
  ones-digit slide progress; this avoids leading-zero artifacts during decrease.
  Fallback commit (lerp approach): `462fd0f`.

### flip_counter_plus (MIT)

- GitHub: https://github.com/Itsxhadi/flip_counter_plus
- License: MIT
- Used by: `AnimatedCountup`
- Role: `AnimatedFlipCounter` in that package is the origin of `AnimatedCountup`.
  Changes made:
  - `AnimationController` → `CountupPlugin` on shared `Countman` ticker.
  - `setState(){}` digit rebuild → persistent `CounterPainter` + `ValueNotifier`
    repaint trigger (no build cost per frame).
  - Roll transition `Positioned` → `Transform.translate + ClipRect` (no layout
    pass per frame).
  - `n % 9 == 0` target adjustment added.
  - `_effectiveFlipDirection` auto-reversal for decrease animations.

---

## Known limitations / gotchas

- **`n % 9 == 0` detection** — targets like 9, 99, 999, 999,999,999 produce
  degenerate digit patterns (the interpolation stalls at all-9). `AnimatedCountup`
  detects this and animates to `n - 1/(10^fractionDigits)`, then snaps to `n`
  at `onDone`. `CountupOdometer` and `CountupText` are not affected.

- **`autoEaseThreshold: 100000`** — when `curve == Curves.linear` (the default
  for `AnimatedCountup`) and the animated range exceeds this value, `Curves.easeInOut`
  is automatically applied internally to prevent large first/last-frame jumps.
  Set `autoEaseThreshold: double.infinity` to disable. Has no effect when an
  explicit non-linear curve is provided.

- **`repaintBoundary: true` at scale** — each boundary adds a GPU compositor
  layer. For dense grids (>~10 concurrent instances), switch to `false` and let
  a single ancestor layer cover the whole grid; otherwise compositing cost
  dominates raster time.

- **`blur` and `flip` transition types** always force the widget slow path
  in `AnimatedCountup` (no `CustomPainter` equivalent). Avoid them in large grids.

- **`digitBuilder` / `digitTransitionBuilder`** also force the widget slow
  path. Build cost is ~0.85 ms per digit per frame; acceptable for a handful
  of counters, problematic at scale.

- **`Countdown` plugin singleton pattern** — `Countman.use()` silently ignores
  duplicate plugin names. If a `Countdown` is created inside `initState` of a
  widget that gets rebuilt via a reset key, the second instance never receives
  `onAttach` and `ctx` remains `late`-uninitialized — `add()` throws
  `LateInitializationError`. Fix: declare the plugin at module or long-lived
  state level; `Countman.use()` is then safely idempotent.

