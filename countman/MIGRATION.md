# Migrating from countman 0.2.x to 0.3.0

0.3.0 changes how the shared ticker schedules plugins (it now sleeps between
updates), adds a clock abstraction and a theme extension, and tightens a few
APIs. Most apps only touch the last four sections; the first two matter only if
you wrote your own plugin.

| # | Change | Who is affected |
|---|---|---|
| 1 | `CountmanPlugin.tick` returns `int`, new `onDetach()` | custom plugins |
| 2 | `ClockPlugin` hooks use integer microseconds | custom clock plugins |
| 3 | `CountdownOptions`: `duration` or `deadline` | direct engine users |
| 4 | Relative vs absolute clock semantics | anyone relying on system-time changes |
| 5 | Plugins are registered per instance | anyone creating same-named plugins |
| 6 | Provider `*Style` replaced by `CountmanTheme` | provider users (deprecation) |
| 7 | `AnimatedCounter` flat parameters replaced by `format` / `timeline` / `style` | `AnimatedCounter` users (deprecation) |
| 8 | `CounterBuilder.builder` is nullable | code reading that field |
| 9 | Changing the plugin no longer restarts tasks | widgets that swapped plugins |

Everything marked "deprecation" still compiles and behaves as before; you get
analyzer warnings and can migrate at your own pace.

---

## 1. Custom plugins: `tick` returns microseconds, `onDetach` is required

`CountmanPlugin.tick` no longer returns a `bool` ("still busy"). It returns the
number of **microseconds until the plugin needs to run again**, so the scheduler
can sleep instead of rendering a frame per vsync:

- `CountmanPlugin.idle` (`-1`): nothing to do; the scheduler may stop.
- `CountmanPlugin.nextFrame` (`0`): run again on the next frame.
- a positive number: run again after that many microseconds (waits up to
  20 ms are still served by the next frame; longer waits arm one global timer).

`CountmanPlugin` also has a new required method `onDetach()`, called by
`Countman.unuse` and `Countman.destroy` before `dispose()`. A detached plugin
may be registered again, so do not release resources there.

**Before (0.2.x)**

```dart
class Blinker implements CountmanPlugin {
  @override
  String get name => 'blinker';

  late CountmanContext _ctx;

  @override
  void onAttach(CountmanContext ctx) => _ctx = ctx;

  @override
  bool tick(Duration elapsed, Duration dt) {
    // ... advance state ...
    return _active; // true = keep the ticker running
  }

  @override
  void dispose() {}
}
```

**After (0.3.0)**

```dart
class Blinker implements CountmanPlugin {
  @override
  String get name => 'blinker';

  late CountmanContext _ctx;

  @override
  void onAttach(CountmanContext ctx) => _ctx = ctx;

  @override
  int tick(Duration elapsed, Duration dt) {
    // ... advance state ...
    if (!_active) return CountmanPlugin.idle;
    return _nextToggleMicros; // e.g. 500000 sleeps half a second
  }

  @override
  void onDetach() {} // nothing to undo; may be attached again

  @override
  void dispose() {}
}
```

Subclasses of `TaskQueuePlugin` also changed: `beginFrame` and `step` return
`void` (and `step` no longer receives `shouldProcess`). Override
`nextWake(task)` to say when a task needs the next call; the default is
`CountmanPlugin.nextFrame`, which keeps the old "every frame while active"
behaviour.

```dart
// 0.2.x
@override
bool step(MyTask task, double dtMs, bool shouldProcess) {
  // ...
  return !task.done; // busy?
}

// 0.3.0
@override
void step(MyTask task, double dtMs) {
  // ...
}

@override
int nextWake(MyTask task) => CountmanPlugin.nextFrame; // or a positive delay
```

## 2. `ClockPlugin` subclasses: integer-microsecond hooks

`ClockPlugin` (the base of `Countdown` and `Elapsed`) reads the clock once per
frame and works in integer microseconds. Every task updates when **its own**
value crosses a multiple of `interval`, and the plugin returns the earliest wake
time of all tasks.

| 0.2.x | 0.3.0 |
|---|---|
| `Duration valueOf(task)` | `int valueMicrosOf(task)` (use `frameWallMicros` / `frameMonotonicMicros`) |
| `bool thresholdCrossed(task)` | `int thresholdWake(int value, int thresholdMicros)`; `<= 0` means crossed |
| (none) | `int boundaryWake(task, value, intervalMicros)`: microseconds until the display bucket changes, must be positive |
| (none) | `int completionWake(task, value)`: microseconds until completion, default `CountmanPlugin.idle` |
| (none) | `int displayMicrosOf(task, value)`: optional, maps the value to the displayed one (rounding) |
| `ClockPlugin(name, {interval})` | `ClockPlugin(name, {interval, clock})` |

Kept as they were: `totalOf`, `isComplete`, `onComplete`.

```dart
class Uptime extends ClockPlugin<UptimeTask> {
  Uptime({super.interval, super.clock}) : super('uptime');

  @override
  int valueMicrosOf(UptimeTask t) => frameMonotonicMicros - t.startMicros;

  @override
  Duration? totalOf(UptimeTask t) => null;

  @override
  bool isComplete(UptimeTask t) => false;

  @override
  int boundaryWake(UptimeTask t, int value, int intervalMicros) =>
      (value ~/ intervalMicros + 1) * intervalMicros - value;

  @override
  int thresholdWake(int value, int thresholdMicros) => thresholdMicros - value;

  @override
  void onComplete(UptimeTask t) {}
}
```

See [Writing a custom plugin](README.md#writing-a-custom-plugin) in the README
for a complete walkthrough.

## 3. `CountdownOptions`: `duration` or `deadline`

`duration` is now optional and a new `deadline` was added. Provide **exactly
one** (asserted in debug builds).

```dart
// 0.2.x
countdown(CountdownOptions(duration: const Duration(minutes: 5)));
countdown(CountdownOptions(duration: DateTime(2026, 12, 31).difference(DateTime.now())));

// 0.3.0
countdown(CountdownOptions(duration: const Duration(minutes: 5)));      // relative
countdown(CountdownOptions(deadline: DateTime(2026, 12, 31)));          // absolute
```

New optional fields: `total` (progress denominator) and `rounding`
(`CountdownRounding.floor` / `ceil`). `remainingUntil` and `resolveDeadline`
accept an optional `clock`.

## 4. Relative vs absolute: which clock a countdown follows

| Input | Clock | Changing the system time |
|---|---|---|
| `CountdownOptions(duration: ...)`, widget `to: Duration(...)` | monotonic | no effect |
| `CountdownOptions(deadline: ...)`, widget `to: DateTime` / `int` / `String` | wall | shifts the countdown |
| Stopwatches (`Elapsed`, `TextElapsed`, `ElapsedBuilder`) | monotonic | no effect |
| `ElapsedOptions(since: ...)` | wall | shifts the stopwatch |

After pause/resume or `reset()` every task continues on the monotonic clock.
`SystemClock` (the default `CountmanClock.system`) adds back the time the
monotonic clock stood still while the device was in deep sleep, once the app
returns to the foreground.

In 0.2.x every countdown was anchored to the wall clock. If you used a
`Duration` and *wanted* it to follow clock changes, switch to an absolute
deadline:

```dart
// 0.2.x: followed system-time changes
TextCountdown(to: const Duration(minutes: 5));

// 0.3.0: same behaviour
TextCountdown(to: DateTime.now().add(const Duration(minutes: 5)));
```

To correct for a server clock, or to test, inject a clock:

```dart
final server = OffsetClock(CountmanClock.system, const Duration(seconds: 2));
final auction = Countdown(name: 'auction', clock: server);

final fake = ManualCountmanClock(wallTime: DateTime(2026));
final test = Countdown(name: 'test', clock: fake);
fake.advance(const Duration(seconds: 3));
```

`countdownClock` / `elapsedClock` still exist and feed `SystemClock`; new tests
should prefer `ManualCountmanClock`.

## 5. Plugins are registered per instance

0.2.x registered plugins by name and silently ignored a second plugin with the
same name. 0.3.0 registers by instance: registering the same instance twice
does nothing, but a **different** instance with an existing name fails an
`assert` in debug builds (release builds register it).

```dart
// 0.2.x: the second line was silently ignored, the second group never attached
Countman.use(Countdown(name: 'auction'));
Countman.use(Countdown(name: 'auction'));

// 0.3.0: reuse one instance, or use unique names
final auction = Countdown(name: 'auction');
Countman.use(auction);
Countman.use(auction); // fine, no-op
```

Create groups at module or long-lived-state level. A widget that creates its own
group should unregister it on dispose:

```dart
@override
void dispose() {
  Countman.unuse(_group); // detaches and disposes (dispose: false keeps its tasks)
  super.dispose();
}
```

## 6. Provider styles become `CountmanTheme`

The `*Style` parameters of `CounterProvider`, `CountdownProvider`,
`ElapsedProvider` and `CountmanProvider` are deprecated. Register a
`CountmanTheme` in `ThemeData.extensions` instead; it works for the whole
subtree without a provider widget.

```dart
// 0.2.x
CountmanProvider(
  ringCounterStyle: const RingCounterStyle(size: 96, strokeWidth: 10),
  child: const MyPage(),
)

// 0.3.0
MaterialApp(
  theme: ThemeData(extensions: const [
    CountmanTheme(ringCounterStyle: RingCounterStyle(size: 96, strokeWidth: 10)),
  ]),
  home: const MyPage(),
)
```

Resolution order, field by field: widget `style` > provider `*Style`
(deprecated) > `CountmanTheme` > built-in default. Providers keep their other
jobs: scalar defaults (`textStyle`, `color`, `duration`, ...), a shared `plugin`
and the `onGroupReady` / `onAllComplete` callbacks. `CountdownProvider.animateOnce`
is deprecated too: countdowns have no entrance animation.

## 7. `AnimatedCounter`: `format`, `timeline`, `style`

Flat parameters that duplicate a configuration object are deprecated on
`AnimatedCounter` and `AnimatedCounterBuilder`. Precedence is unchanged: a
non-null field of the object wins over the flat parameter, null fields fall back.

| Group | Object | Fields |
|---|---|---|
| Number format | `CounterFormat` | `fractionDigits`, `wholeDigits`, `hideLeadingZeroes`, `thousandSeparator`, `groupingPattern`, `decimalSeparator`, `compactNotation`, `compactFractionDigits`, `compactAbbreviations`, `showPositiveSign`, `numeralSystem`, `numeralMapper` |
| Timing | `CounterTimeline` | `duration`, `curve`, `reverseDuration`, `reverseCurve`, `startDelay`, `speedMultiplier`, `staggerDelay`, `staggerDirection`, `autoEaseThreshold`, `curveForDigit`, `interpolation`, `bounceOvershoot`, `fast` |
| Look | `AnimatedCounterStyle` | `textStyle`, `prefixStyle`, `infixStyle`, `suffixStyle`, `separatorStyle`, `numberAlignment`, `mainAxisAlignment`, `crossAxisAlignment`, `padding`, `useTabularFigures`, `increasingColor`, `decreasingColor`, `colorFadeDuration`, `decoration` |

```dart
// 0.2.x
AnimatedCounter(
  value: 1234.56,
  fractionDigits: 2,
  thousandSeparator: ',',
  duration: const Duration(seconds: 2),
  staggerDelay: const Duration(milliseconds: 30),
  textStyle: const TextStyle(fontSize: 40),
  increasingColor: Colors.green,
)

// 0.3.0
AnimatedCounter(
  value: 1234.56,
  format: const CounterFormat(fractionDigits: 2, thousandSeparator: ','),
  timeline: const CounterTimeline(
    duration: Duration(seconds: 2),
    staggerDelay: Duration(milliseconds: 30),
  ),
  style: const AnimatedCounterStyle(
    textStyle: TextStyle(fontSize: 40),
    increasingColor: Colors.green,
  ),
)
```

Still plain parameters: `value`, `controller`, `plugin`, `animateOnce`,
`transition`, `prefix` / `infix` / `suffix` (and their widgets), `flipDirection`,
`minValue`, `maxValue`, `semanticsLabel`, `triggerHaptics`, `initialValue`,
`repaintBoundary` and the callbacks. `thousandSeparatorWidget` and
`decimalSeparatorWidget` are deprecated on `AnimatedCounter` (the painter path
cannot draw widgets); use `AnimatedCounterBuilder` for those.

New: `plugin` and `animateOnce` (see the README), and
`CounterFormat.format(value)` to get the string shown at rest.

## 8. `CounterBuilder.builder` is nullable

`CounterBuilder.listenable` shares the class, so the `builder` field became
`Widget Function(...)?`. The constructor parameter is still required. Only code
that reads `widget.builder` (for example a subclass or a wrapper that forwards
it) needs a null check or `!`. `CountdownBuilder.builder` is nullable for the
same reason.

## 9. Changing the plugin no longer restarts tasks

In 0.2.x, when the resolved plugin changed (a different `plugin:` argument, a
provider appearing or disappearing, `precise` toggled) the widget cancelled its
task and started a new one. In 0.3.0 the task migrates: remaining or elapsed
time, laps, pause state and the displayed value are kept, and no user
`onCancel` fires for the swap.

If you relied on the restart, ask for it explicitly:

```dart
controller.restart(); // re-reads the widget's current configuration
```

---

## New in 0.3.0 you may want to adopt

- `CountdownOptions.total` / `rounding`, `CountdownFormat.template`
- `ElapsedOptions.since` / `initial` / `limit`, `lap()` / `laps`
- `controller.runState` / `runStateListenable` / `restart()`
- `CountmanTheme`, `CountmanClock` and friends

See [CHANGELOG.md](CHANGELOG.md) for the complete list.
