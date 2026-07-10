# countman

**High-performance shared-ticker counter animations for Flutter.**

[![pub.dev](https://img.shields.io/pub/v/countman.svg)](https://pub.dev/packages/countman)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Demo](https://img.shields.io/badge/demo-live-brightgreen)](https://icodejoo.github.io/dart-labs/)

**[▶ Live Demo](https://icodejoo.github.io/dart-labs/)** — Counter · Countdown · Elapsed, all widgets, all APIs.

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
  ├── CountupPlugin  — interpolates numbers from → to
  ├── Countdown      — wall-clock deadline timers (interval-gated)
  └── Elapsed        — wall-clock elapsed timers (interval-gated)
```

---

## Performance

| Approach | Frame callbacks | Timer allocations |
|---|---|---|
| N `AnimationController`s | N | N vsync listeners |
| N `Timer.periodic` | — | N timers |
| **countman** | **1** | **0** |

Measured at 94 concurrent `AnimatedCountup` instances (0 → 999,999,999):

- **Raster: 8–11 ms** — RepaintBoundary keeps each counter in its own layer.
- **Build: ~2 ms** — CustomPainter path skips widget instantiation entirely.
- **Startup spike** is spread across frames with `batch:`.

### Head-to-head vs other packages

**50 concurrent countdowns**, Windows desktop **profile** mode, 15 s measurement
window per library, run back-to-back in one session (display at 120 Hz). FPS =
frames actually rendered ÷ elapsed; UI/raster = per-frame thread time;
CPU = share of **one** core, sampled externally from the OS process; RSS =
resident set size. Lower is better except FPS/jank.

*(50 个并发倒计时，Windows 桌面 profile 模式，每库测量 15 s，同一会话依次运行，
显示器 120 Hz。CPU 为单核占用率，从操作系统进程外部采样。除 FPS/jank 外均越低越好。)*

**Card / slide mode** — countman `CountdownCard(slide)` vs [`slide_countdown`](https://pub.dev/packages/slide_countdown) `^2.0.2`:

| metric | countman `CountdownCard` slide | `slide_countdown` |
|---|---|---|
| FPS (frames / 15 s) | **121.7** (1826) | 32.5 (488) |
| UI ms  avg / p99 | **0.80 / 2.12** | 1.32 / 4.39 |
| raster ms  avg / p99 | **0.83 / 1.47** | 1.05 / 1.76 |
| jank frames | 0 | 0 |
| RSS  avg / peak (MB) | 130.2 / 137.3 | 130.3 / 135.4 |
| CPU (1 core) | 26.1 % | **10.0 %** |

countman drives the slide+scale+opacity transition **every vsync** (fully
smooth, cheaper per frame), so it renders far more frames and costs more total
CPU; `slide_countdown` repaints only during its once-per-second slide bursts —
lower CPU, but burstier cadence and pricier frames. Both are jank-free and use
the same memory.

*(countman 每帧驱动滑动+缩放+透明动画，完全顺滑、单帧更便宜，因此帧数更多、总 CPU
更高；`slide_countdown` 仅在每秒滑动瞬间重绘——CPU 更低，但帧节奏更突发、单帧更贵。
两者均无卡顿，内存相同。)*

**Text mode** — countman `CountdownText` vs [`stop_watch_timer`](https://pub.dev/packages/stop_watch_timer) `^3.2.2` (driving a `Text` via `StreamBuilder`):

| metric | countman `CountdownText` | `stop_watch_timer` |
|---|---|---|
| FPS (frames / 15 s) | 120.9 (1813) | 120.1 (1801) |
| UI ms  avg / p99 | **0.10 / 0.16** | 0.16 / 0.66 |
| raster ms  avg / p99 | 0.37 / 0.59 | **0.31 / 0.58** |
| jank frames | 0 | 0 |
| RSS  avg / peak (MB) | 113.8 / 116.0 | 113.9 / 116.4 |
| CPU (1 core) | **12.1 %** | 18.8 % |

For plain-text countdowns the single shared ticker + `markNeedsPaint` costs
**~35 % less CPU** than 50 independent `stop_watch_timer` streams
(12.1 % vs 18.8 % of a core) with steadier per-frame UI time; memory is
identical.

*(纯文本倒计时下，单一共享 ticker + `markNeedsPaint` 比 50 个独立
`stop_watch_timer` 流省约 35% CPU（单核 12.1% vs 18.8%），单帧 UI 耗时更稳；
内存相同。)*

> Reproduce with `example/lib/benchmark_page.dart`:
> `flutter run --profile -d windows --dart-define=BENCH_LIB=countmanCard`
> (also `slide` / `countmanText` / `stopWatch`).

---

## Countdown

### `CountdownBuilder`

Low-level widget that exposes remaining time via a `builder` callback.

```dart
// Fixed duration — MM:SS
CountdownBuilder(
  duration: const Duration(minutes: 5),
  builder: (context, parts) => Text(
    CountdownFormat.ms(parts),
    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
  ),
)

// Target deadline — accepts DateTime, Duration, int (ms epoch), or ISO-8601 String
CountdownBuilder(
  to: DateTime.now().add(const Duration(hours: 2)),
  builder: (context, parts) => Text(CountdownFormat.hms(parts)),
)
```

Key parameters:

| Parameter | Description |
|---|---|
| `duration` | Fixed countdown length (mutually exclusive with `to`) |
| `to` | Deadline — `DateTime`, `Duration`, `int` (ms epoch), or ISO-8601 `String` |
| `plugin` | Custom `Countdown` instance (default: shared 1 s interval) |
| `controller` | `CountdownController` for pause / resume / reset |
| `onComplete` | Called once when remaining reaches zero |
| `threshold` + `onThreshold` | Fire once when remaining first crosses threshold |

### `CountdownText`

Drop-in text widget. `const`-constructible when `to` is a `Duration`.

```dart
CountdownText(
  to: const Duration(minutes: 5),
  formatter: CountdownFormat.ms,
  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
)
```

### `CountdownRing`

Arc progress ring that drains from full to empty.

```dart
CountdownRing(
  to: const Duration(minutes: 2),
  size: 100,
  strokeWidth: 10,
  color: Colors.blue,
  trackColor: Colors.blue.withValues(alpha: 0.2),
  center: const CountdownText(
    to: Duration(minutes: 2),
    formatter: CountdownFormat.ms,
  ),
)
```

### `CountdownBar`

Horizontal progress bar.

```dart
CountdownBar(
  to: const Duration(minutes: 1),
  width: 250,
  height: 10,
  gradient: const LinearGradient(colors: [Colors.green, Colors.yellow, Colors.red]),
  borderRadius: const Radius.circular(5),
)
```

### `CountdownDial`

Analog clock-face dial. Hand sweeps 60 seconds per revolution.

```dart
CountdownDial(
  to: const Duration(seconds: 60),
  size: 100,
  builder: (_, rem) => Text(
    rem.inSeconds.toString(),
    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
  ),
)
```

### `CountdownCard`

Split-flap / slide / flip card display.

```dart
CountdownCard(
  to: const Duration(hours: 1, minutes: 30),
  transitionType: CountdownType.calendar, // or .slide, .flip
  splitDigits: true,
)
```

### `CountdownFormat`

Built-in `String Function(TimeParts)` formatters:

| Formatter | Example output | Notes |
|---|---|---|
| `CountdownFormat.hms` | `01:23:45` | Always shows hours |
| `CountdownFormat.ms` | `03:07` | Minutes may exceed 59 |
| `CountdownFormat.msTenths` | `00:09.7` | Tenths of a second |
| `CountdownFormat.msMillis` | `00:09.327` | Full ms precision — use with `interval: 0` |
| `CountdownFormat.auto` | adaptive | `hms` ≥1h · `msTenths` <10s · else `ms` |

### Millisecond precision

Set `interval` to the desired update period in milliseconds (`0` = every vsync frame):

```dart
// Module-level singleton — do NOT create inside initState.
// Countman.use() silently ignores duplicate names; a second instance created
// on reset would never receive onAttach and throw LateInitializationError.
final _msPlugin = Countdown(name: 'ms', interval: 1000 ~/ 60); // ~16 ms = 60 fps

class _MyState extends State<_MyWidget> {
  @override
  void initState() {
    super.initState();
    Countman.use(_msPlugin); // idempotent — no-op if already registered
  }

  @override
  Widget build(BuildContext context) {
    return CountdownBuilder(
      duration: const Duration(seconds: 10),
      plugin: _msPlugin,
      builder: (_, parts) => Text(CountdownFormat.msMillis(parts)),
    );
  }
}
```

### Imperative control

```dart
final ctrl = CountdownController();

CountdownBuilder(
  duration: const Duration(minutes: 2),
  controller: ctrl,
  builder: (_, parts) => Text(CountdownFormat.ms(parts)),
)

ctrl.pause();
ctrl.resume();
ctrl.reset();                                    // back to original duration
ctrl.reset(duration: const Duration(seconds: 30)); // override duration
```

---

## Elapsed

### `ElapsedText`

Counts up from zero. Same `formatter` / `style` / `controller` API as `CountdownText`.

```dart
ElapsedText(
  formatter: CountdownFormat.ms,
  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
)
```

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

### `AnimatedCountup`

Full-featured counter widget with 7 transition types, stagger, compact
notation, decimal support, color tinting, and programmatic control.
Adapted from [`flip_counter_plus`](https://github.com/Itsxhadi/flip_counter_plus)
(MIT). Key architectural changes: shared ticker replaces
`AnimationController`; `CustomPainter` with a persistent painter replaces
per-frame widget rebuilds.

```dart
// Basic
AnimatedCountup(value: 9999)

// Roll transition with stagger
AnimatedCountup(
  value: 1000000,
  duration: const Duration(seconds: 2),
  transitionType: CounterTransitionType.roll,
  staggerDelay: const Duration(milliseconds: 30),
  thousandSeparator: ',',
)

// USD currency
AnimatedCountup.usd(value: 1234.56)

// Programmatic control
final controller = CounterController();

AnimatedCountup(controller: controller, value: 0)

// later:
controller.animateTo(9999);
controller.pause();
controller.resume();
controller.reverse();
```

---

## `AnimatedCountup` key parameters

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
  itemBuilder: (_, i) => AnimatedCountup(
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
- Role: `AnimatedCountup` is adapted from `AnimatedFlipCounter` in this package.
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

