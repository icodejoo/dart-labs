# countman example

The [live demo](https://icodejoo.github.io/dart-labs/countman/) showcases countman
0.3.1 with a responsive grid, English/Chinese controls and light/dark themes.
Open `?lang=zh` for Chinese or `?lang=en` for English. Otherwise the browser
language selects Chinese for Chinese locales and English for other locales.
Navigation is restored from `#/pages/<id>` after a refresh.

## Run and build

```powershell
flutter pub get
flutter run -d chrome
flutter build web --release --base-href /dart-labs/countman/
```

No new third-party dependency is required. The reusable SDK-only
[demo_kit](lib/demo_kit/README.md) is copied per project. Web external links use
native `window.open`; native applications copy links to the clipboard.

## Public pages and audit

| Page | Current examples | Replaced content |
| --- | --- | --- |
| Counter | AnimatedCounter, TextCounter, OdometerCounter, ring/bar | Repeated color/transition variants; obsolete odometer slot/fade knobs |
| Countdown | Pause/resume, ceil, total, absolute deadline, template | Duplicate countdown overview and formatter variants |
| Elapsed | Tenths, pause/resume, lap, since, limit | Repeated formatting and callback tiles |
| Card & dial | Calendar/slide/flip, dial, bitmap cache release | Large effect matrix; dial import workaround |
| Advanced | Passive frame/wake counters, fps, hidden muting, pomodoro | Old scheduler assumptions and performance claims |
| Providers & theme | Aggregate provider, CountmanTheme | Deprecated provider-level style arguments |
| Benchmarks / 压测: Stress (`stress`) | 30 counters, per-instance replay, start/restart and stop | Available on Web and native |
| Benchmarks / 压测: Performance (`perf`) | Six effects × five counters, 10 s, start/reset/stop | Available on Web and native |
| Benchmarks / 压测: Digit debug (`digit-test`) | 0 → 99 and reverse, original nine-digit normalized logs | Available on Web and native |
| Benchmarks / 压测: Native benchmark (`benchmark`) | Cross-library 50-countdown frame/FPS/RSS comparison | Web shows “该页需桌面原生运行 / This page requires a native desktop app.” |

Styles now use style objects; AnimatedCounter formatting and timing use
CounterFormat and CounterTimeline. No old 0.2.x performance figures appear in
the public demo. Frame counts are app-wide observations, not benchmark scores.
Reading counts and other UI interactions also produce frames. Disable precise
comparison and other animations when observing second-level sleeping.

## Native development benchmarks

The public shell retains the **Benchmarks / 压测** group at
`#/pages/stress`, `#/pages/perf`, `#/pages/digit-test` and `#/pages/benchmark`.
Each page uses DemoPage, translated controls and a profile-mode reminder.
Heavy workloads start only after an explicit button click; Stop immediately
unmounts active instances. Stress retains individual replay after starting;
Performance and Digit debug also retain reverse-to-zero Reset.

浏览器里的数字仅供参考，真实基准请用桌面 / 真机 profile 模式。
Browser numbers are for reference only; use desktop or a real device in profile
mode for real benchmarks. Only the native benchmark panel, frame driver and
presentation statistics are conditionally imported: its process environment,
RSS sampling and isolated-run exit require `dart:io`. Web displays a translated
native-desktop requirement without loading that implementation.

```powershell
flutter run --profile -d windows --dart-define=COUNTMAN_BENCH=true
flutter run --profile -d windows --dart-define=COUNTMAN_BENCH=true --dart-define=INITIAL_ROUTE=/perf
flutter run --profile -d windows --dart-define=COUNTMAN_BENCH=true --dart-define=INITIAL_ROUTE=/digit-test
```

The existing `tool/bench_desktop.ps1` still uses
`--dart-define=INITIAL_ROUTE=/benchmark`, which alone explicitly enables the
native benchmark entry, including automatic collection and BENCH_LIB isolated-run
exit for script compatibility. COUNTMAN_BENCH continues to enable the same named
routes (`/benchmark`, `/perf`, `/digit-test`, `/stress`). This explicit script
entry is the exception to the public shell's manual-start behavior.
`tool/bench.ps1` runs tagged engine/painter tests and
does not depend on example routes. Neither script needs editing. Benchmarks must run in a real
native window; their results are not reproduced by browser timing figures.

## Validation and snippets

```powershell
flutter analyze
flutter test
python tool/sync_samples.py
```

Displayed snippets are generated from compiled functions in `demo_samples.dart`
and the actual pomodoro source. Tests verify synchronization. After editing a
sample, format its Dart source, regenerate snippets and rerun tests.
The parent package must also pass `flutter analyze` and `flutter test`.