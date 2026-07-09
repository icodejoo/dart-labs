---
name: countman
description: Work on countman — a high-performance Flutter counter animation library with a shared scheduleFrameCallback ticker. Use when adding features, widgets, fixing bugs, or optimizing this package.
---

# countman

`C:\workspace\dart-labs\countman`: one shared `scheduleFrameCallback` drives all
count-up animations; rendering is pluggable via `CountmanPlugin` instances.

## Architecture

```
Countman (static singleton — 1 scheduleFrameCallback)
  └── CountmanPlugin interface (each instance = independent task queue / "group")
       └── CountupPlugin (drives number interpolation; auto-registered on first countup() call)
            └── CountupHandle (returned by add(); use update()/cancel() for retarget/cancel)
```

Widgets talk to `CountupPlugin` via the top-level `countup()` function.
No `AnimationController`, no `Timer.periodic`.

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

### Widgets

| File | Role |
|---|---|
| `lib/src/widgets/countup_builder.dart` | `CountupBuilder` — `StatefulWidget`, `ValueNotifier<double>` + `ValueListenableBuilder` |
| `lib/src/widgets/countup_text.dart` | `CountupText` — `StatelessWidget` wrapping `CountupBuilder`; prefix/suffix support |
| `lib/src/widgets/countup_odometer.dart` | `CountupOdometer` — per-digit slide via `OdometerTransition` (odometer pkg); `_fromFloat()` builds `OdometerNumber` directly from raw float |
| `lib/src/widgets/countup_plus/countup_plus.dart` | `CountupPlus` — full-featured widget (adapted from flip_counter_plus); CustomPainter fast path + widget fallback |
| `lib/src/widgets/countup_plus/counter_painter.dart` | `CounterPainter` — persistent `CustomPainter`; updated in-place each frame via `update()`; `repaint: Listenable` drives `markNeedsPaint`, not build |
| `lib/src/widgets/countup_plus/counter_controller.dart` | `CounterController` — `ChangeNotifier`-based programmatic API (`animateTo`, `jumpTo`, `pause`, `resume`, `reverse`, …) |
| `lib/src/widgets/countup_plus/digit_column.dart` | `DigitColumn` — widget fallback for `blur`/`flip` transition types or when `digitBuilder`/`digitTransitionBuilder` is provided |
| `lib/src/widgets/countup_plus/types.dart` | `CounterTransitionType`, `StaggerDirection`, `NumeralSystem` enums |

---

## Widget API (concise reference)

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

### `CountupPlus`

```dart
CountupPlus(
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
CountupPlus(controller: ctrl, value: 0)
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
- Used by: `CountupPlus`
- Role: `AnimatedFlipCounter` in that package is the origin of `CountupPlus`.
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
  degenerate digit patterns (the interpolation stalls at all-9). `CountupPlus`
  detects this and animates to `n - 1/(10^fractionDigits)`, then snaps to `n`
  at `onDone`. `CountupOdometer` and `CountupText` are not affected.

- **`autoEaseThreshold: 100000`** — when `curve == Curves.linear` (the default
  for `CountupPlus`) and the animated range exceeds this value, `Curves.easeInOut`
  is automatically applied internally to prevent large first/last-frame jumps.
  Set `autoEaseThreshold: double.infinity` to disable. Has no effect when an
  explicit non-linear curve is provided.

- **`repaintBoundary: true` at scale** — each boundary adds a GPU compositor
  layer. For dense grids (>~10 concurrent instances), switch to `false` and let
  a single ancestor layer cover the whole grid; otherwise compositing cost
  dominates raster time.

- **`blur` and `flip` transition types** always force the widget slow path
  in `CountupPlus` (no `CustomPainter` equivalent). Avoid them in large grids.

- **`digitBuilder` / `digitTransitionBuilder`** also force the widget slow
  path. Build cost is ~0.85 ms per digit per frame; acceptable for a handful
  of counters, problematic at scale.

- **`CountdownPlugin`** is not yet implemented. The `StartScheduler` and
  `CountmanPlugin` interface are designed to accommodate it without changes.
