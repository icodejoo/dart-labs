# countman

**High-performance shared-ticker counter animations for Flutter.**

[![pub.dev](https://img.shields.io/pub/v/countman.svg)](https://pub.dev/packages/countman)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

---

## Why countman?

Most counter packages give every widget its own `AnimationController` (or a
`Timer.periodic`). With N counters on screen you pay N frame-callback
registrations, N timers, and N separate animation lifecycles — none of them
aware of each other.

**countman** reverses this: one `SchedulerBinding.scheduleFrameCallback` drives
every counter instance. The ticker is idle between animations (auto-stops when
all tasks finish) and wakes up on demand. Adding a hundredth counter costs the
same as adding the first.

```
Countman (1 scheduleFrameCallback)
  └── CountupPlugin (one task queue per group)
       └── CountupHandle (one per animation)
```

---

## Performance

| Approach | Frame callbacks | Timer allocations |
|---|---|---|
| N `AnimationController`s | N | N vsync listeners |
| N `Timer.periodic` | — | N timers |
| **countman** | **1** | **0** |

Measured at 94 concurrent `CountupPlus` instances (0 → 999,999,999):

- **Raster: 8–11 ms** — RepaintBoundary keeps each counter in its own layer.
- **Build: ~2 ms** — CustomPainter path skips widget instantiation entirely.
- **Startup spike** is spread across frames with `batch:`.

---

## Installation

```yaml
dependencies:
  countman: ^0.1.0
```

---

## Widgets

### `CountupBuilder`

Flexible low-level widget. Drives a `ValueNotifier<double>` and exposes the
current value via a `builder` callback — use this when you need full control
over the rendered output.

```dart
CountupBuilder(
  to: 9999,
  duration: const Duration(seconds: 2),
  curve: Curves.easeOut,
  builder: (context, value) => Text(
    value.toInt().toString(),
    style: const TextStyle(fontSize: 48),
  ),
)
```

Key parameters:

| Parameter | Default | Description |
|---|---|---|
| `from` | `0` | Start value |
| `to` | required | Target value |
| `duration` | `1000 ms` | Animation duration |
| `curve` | `Curves.easeOut` | Flutter `Curve` |
| `builder` | required | `(context, double) → Widget` |
| `onDone` | — | Called when animation completes |
| `repaintBoundary` | `true` | Isolates repaint layer |

---

### `CountupText`

Simple drop-in text counter with optional prefix/suffix. A `StatelessWidget`
wrapper around `CountupBuilder`.

```dart
// Plain number
CountupText(to: 9999)

// With currency prefix
CountupText(
  to: 9999,
  prefix: '¥',
  style: const TextStyle(fontSize: 32),
)

// With widget prefix and text suffix
CountupText(
  to: 9999,
  prefixWidget: const Icon(Icons.star),
  suffix: ' pts',
)

// Custom formatter (e.g. 2 decimal places)
CountupText(
  to: 1234.56,
  formatter: (v) => v.toStringAsFixed(2),
)
```

When both `prefix` and `prefixWidget` are provided, `prefixWidget` takes
precedence (same rule applies to suffix).

---

### `CountupOdometer`

Per-digit vertical slide animation, styled like a mechanical odometer. Each
digit slides independently: the ones digit scrolls continuously while higher
digits tick on integer carry. No leading zeros when the digit count shrinks
(e.g. 9999 → 100).

Uses `OdometerTransition` from the [`odometer`](https://pub.dev/packages/odometer)
package for per-digit rendering. The opacity fade is applied via
`color.withValues(alpha:)` — never an `Opacity` widget — to avoid `saveLayer`
overhead.

```dart
CountupOdometer(
  to: 9999,
  duration: const Duration(seconds: 2),
  curve: Curves.easeOut,
  letterWidth: 24,
  numberTextStyle: const TextStyle(fontSize: 40),
  groupSeparator: const Text(','),
)

// Decreasing — no leading zeros
CountupOdometer(from: 9999, to: 100)
```

Key parameters:

| Parameter | Default | Description |
|---|---|---|
| `letterWidth` | `20` | Fixed width per digit slot |
| `verticalOffset` | `20` | Slide distance in logical pixels |
| `groupSeparator` | — | Widget inserted every 3 digits |
| `numberTextStyle` | — | Text style for digits |

---

### `CountupPlus`

Full-featured counter widget with 7 transition types, stagger, compact
notation, decimal support, color tinting, and programmatic control.
Adapted from [`flip_counter_plus`](https://github.com/Itsxhadi/flip_counter_plus)
(MIT). Key architectural changes: shared ticker replaces
`AnimationController`; `CustomPainter` with a persistent painter replaces
per-frame widget rebuilds.

```dart
// Basic
CountupPlus(value: 9999)

// Roll transition with stagger
CountupPlus(
  value: 1000000,
  duration: const Duration(seconds: 2),
  transitionType: CounterTransitionType.roll,
  staggerDelay: const Duration(milliseconds: 30),
  thousandSeparator: ',',
)

// USD currency
CountupPlus.usd(value: 1234.56)

// Programmatic control
final controller = CounterController();

CountupPlus(controller: controller, value: 0)

// later:
controller.animateTo(9999);
controller.pause();
controller.resume();
controller.reverse();
```

---

## `CountupPlus` key parameters

| Parameter | Default | Description |
|---|---|---|
| `value` | — | Target value (or use `controller`) |
| `controller` | — | `CounterController` for programmatic control |
| `duration` | `300 ms` | Animation duration |
| `curve` | `Curves.linear` | Easing curve |
| `transitionType` | `roll` | `roll`, `fade`, `scale`, `fadeScale`, `rotate`, `flip`, `blur` |
| `fractionDigits` | `0` | Decimal places |
| `wholeDigits` | `1` | Minimum integer digit slots |
| `hideLeadingZeroes` | `true` | Hide leading zeros |
| `thousandSeparator` | — | e.g. `','` |
| `groupingPattern` | `[3]` | Digit grouping (e.g. `[3, 2]` for INR) |
| `decimalSeparator` | `'.'` | Decimal point character |
| `staggerDelay` | — | Per-digit stagger offset |
| `staggerDirection` | `rightToLeft` | `leftToRight` or `rightToLeft` |
| `compactNotation` | `false` | Display 1 200 000 as `1.2M` |
| `compactAbbreviations` | K/M/B/T | Custom compact labels |
| `increasingColor` | — | Tint color when value increases |
| `decreasingColor` | — | Tint color when value decreases |
| `colorFadeDuration` | `800 ms` | Duration of color tint fade |
| `flipDirection` | `up` | Digit scroll direction |
| `reverseDuration` | — | Duration when animating backwards |
| `reverseCurve` | — | Curve when animating backwards |
| `startDelay` | — | Delay before animation begins |
| `speedMultiplier` | `1.0` | Scale all durations |
| `numeralSystem` | `latin` | `easternArabic`, `persian`, `devanagari`, `bengali` |
| `repaintBoundary` | `true` | Isolates repaint layer |
| `autoEaseThreshold` | `100000` | Auto-applies `easeInOut` for large ranges |
| `batch` | `0` | Batch start limit (see below) |
| `digitBuilder` | — | Custom digit widget (falls back to widget path) |
| `digitTransitionBuilder` | — | Custom transition widget (falls back to widget path) |

### `CounterController` API

```dart
controller.animateTo(num value)     // animate to value
controller.jumpTo(num value)        // instant jump, no animation
controller.pause()
controller.resume()
controller.stop()
controller.restart()
controller.repeat()
controller.reverse()
controller.status                   // AnimationStatus
```

---

## Batch start

When a dense grid of counters all animate simultaneously (e.g. triggered by
a single `setState`), the cold-start cost of many widgets in one frame can
spike past the 16 ms frame budget.

`batch: N` spreads starts across frames — at most N widgets per frame:

```dart
GridView.builder(
  itemBuilder: (_, i) => CountupPlus(
    value: data[i],
    batch: 5,   // at most 5 start per frame (~15 ms/frame budget)
  ),
)
```

`batch: 0` (default) starts immediately.

---

## Performance tips

- **`repaintBoundary: true` (default)** — each counter gets its own
  compositor layer. Good for a handful of counters; reduces the dirty area
  that triggers rasterization.

- **`repaintBoundary: false` for dense grids** — more than ~10 concurrent
  `RepaintBoundary` widgets add significant GPU compositing cost. Switch to
  `false` and let a single parent layer cover the whole grid.

- **`batch:` for grid startup** — spreads the initial build spike across
  multiple frames (see above).

- **Avoid `digitBuilder`/`digitTransitionBuilder` at scale** — these force
  the widget build path (~0.85 ms per digit per frame) instead of the
  `CustomPainter` path (~0 ms). Use them only for a small number of counters
  where you need custom rendering.

- **`blur` and `flip` transition types** always use the widget path (no
  `CustomPainter` equivalent). Same advice applies.

---

## Credits / Attributions

### odometer

- Package: [`odometer ^3.0.0`](https://pub.dev/packages/odometer)
- Repository: [github.com/KirsApps/odometer](https://github.com/KirsApps/odometer)
- License: MIT
- Role: `CountupOdometer` uses `OdometerNumber`, `OdometerTransition`, and
  `OdometerNumber.fromDigits` for per-digit sliding. The `_LiveOdometerAnimation`
  adapter bridges the countman ticker to odometer's `Animation<OdometerNumber>`
  interface without an `AnimationController`.

### flip_counter_plus

- Repository: [github.com/Itsxhadi/flip_counter_plus](https://github.com/Itsxhadi/flip_counter_plus)
- License: MIT
- Role: `CountupPlus` is adapted from `AnimatedFlipCounter` in this package.
  Major changes from the original:
  - `AnimationController` (per-instance vsync) replaced by `CountupPlugin`
    on the shared `Countman` ticker.
  - Per-frame `setState` replaced by a persistent `CounterPainter` driven by
    a `ValueNotifier` repaint trigger — no widget build cost per frame.
  - Roll transition rendering changed from `Positioned` (layout pass) to
    `Transform.translate + ClipRect` (compositor only).
  - `n % 9 == 0` target adjustment added to avoid degenerate digit patterns.

---

## License

MIT — see [LICENSE](LICENSE).
