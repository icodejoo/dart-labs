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

Styles now use style objects; AnimatedCounter formatting and timing use
CounterFormat and CounterTimeline. No old 0.2.x performance figures appear in
the public demo. Frame counts are app-wide observations, not benchmark scores.
Reading counts and other UI interactions also produce frames. Disable precise
comparison and other animations when observing second-level sleeping.

## Native development benchmarks

`benchmark_page.dart`, `perf_page.dart`, `digit_test_page.dart`, the frame driver
and presentation statistics remain available outside the public shell.
They are conditionally imported only on native platforms. Web never exposes them.

```powershell
flutter run --profile -d windows --dart-define=COUNTMAN_BENCH=true
flutter run --profile -d windows --dart-define=COUNTMAN_BENCH=true --dart-define=INITIAL_ROUTE=/perf
flutter run --profile -d windows --dart-define=COUNTMAN_BENCH=true --dart-define=INITIAL_ROUTE=/digit-test
```

The existing `tool/bench_desktop.ps1` and `tool/bench.ps1` commands still work:
`--dart-define=INITIAL_ROUTE=/benchmark` alone explicitly enables the native
benchmark entry. Neither script needs editing. Benchmarks must run in a real
native window; their results are not reproduced on the public site.

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