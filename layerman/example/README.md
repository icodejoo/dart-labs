# layerman_example

Interactive demo for [layerman](../README.md) 1.0.0 (depends on the package by `path: ../`).
Live build: https://icodejoo.github.io/dart-labs/layerman/

Pages (left rail): v0.3 Features (blockedBy, suppress, tags, cooldown status), Queue Basics,
Replace & Affix, Overlap (`mode: OverlayMode.overlap`, `delay`), Timing, Conditions
(`RouteMatcher`, `auth:` predicate, `when`, `gate:` / `OverlayVerdict`), Cooldown, Lifecycle
(`ctx.close`, `beforeClose`), Pause & Resume (`pauseOnRoutes`), External Presenters
(native dialog, GetX, bot_toast), Mixed UI Libraries, Setup & Restart.
Every backend confirms first-frame visibility with `OverlayVisibility` or `presentRoute`.

```bash
flutter pub get
flutter run -d windows        # or an Android device / chrome
flutter test                  # widget + README recipe tests
flutter test integration_test # needs a device
```
