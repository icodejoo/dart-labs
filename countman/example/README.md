# countman example

Demo app for [countman](https://pub.dev/packages/countman) 0.3.0. Live version:
https://icodejoo.github.io/dart-labs/countman/

Pages: Counter, Countdown, Elapsed, Advanced (custom plugin, clocks, batch startup),
Provider, plus performance and benchmark pages.
`lib/pomodoro_plugin.dart` is a complete custom `TaskQueuePlugin` that sleeps
between updates (the 0.3.0 `tick` / `nextWake` API).

```sh
flutter pub get
flutter run -d windows        # or any device / chrome
flutter test
```

Benchmark (profile mode, see the main README):

```sh
flutter run --profile -d windows --dart-define=BENCH_LIB=countmanCard
```
