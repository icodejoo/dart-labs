## 0.1.0

### Changed

- `LuckyPhaseX.acceptsStart` is deprecated in favour of `canPlay`; new
  `canStop` and `canCancel` getters replace repeated phase checks.
- `LuckyMotion.passedReel` / `passedIndex` now have defaults and a new
  `drainPassed` hook; `LuckyController.reportsIdleCancellation` replaces the
  per-game cancel-reporting overrides.

### Added

- Experimental opt-in physics collision mode for capsule machines and lotto
  draws (`CapsuleOptions.physics` / `LottoOptions.physics` with `LuckyPhysics`):
  balls drop in from the top and collide with the globe wall, each other and
  rotating stirring arms. Built-in circle solver with no third-party dependency;
  results, phases and events are identical to the default parametric motion,
  and the mode follows system reduced-motion settings by default.
- Experimental shared raster byte budgeting (32 MiB by default), including slot
  atlas pages, with Picture fallback and paired reservation/release accounting.
- Experimental grid step-rate caps and system-aware reduced motion, limited to
  three steps per second when reduced motion is enabled.
- Debug-only warnings identify repeated config-driven cache invalidation across
  all Canvas renderers, with an injectable clock and warning hook for tests.
- Typed, immutable models and widgets for wheels, nine-grids, slots, lever slots,
  capsule machines, number wheels, drawing lots and super-lotto draws.
- Controllers with asynchronous prize selection, weighted and guaranteed picking,
  pause/resume, lifecycle handling, result callbacks and phase notifications.
- Canvas rendering with Picture and raster caches, asynchronous image resolution,
  text scaling, custom drawing layers, paylines and optional Widget overlays.
- Separate entry points for each game, extension interfaces, deterministic testing
  helpers and lucky-canvas JSON migration with an opt-in strict upstream preset.
- Drawing lots can customize rise/reveal easing, shake waveform, layout and the
  background, cylinder and stick drawing.
- A slot machine without prizes still paints its block frame, as upstream does.
- Experimental LuckyConformance reports easing and headless result, landing and
  hit consistency for wheel, grid, slot and lots configurations.

### Changed

- Default to bounded bitmap caching while moving and vector replay while idle
  (`LuckyCacheMode.auto`); document example screenshots and outstanding device performance limits.
- Use elapsed time and a monotonic stop solver by default for consistent final
  positions across refresh rates; retain frame-based upstream behavior in strict mode.
- Keep core APIs and game implementations separate so unused games can be removed
  by tree shaking, with no third-party runtime dependencies.

### Fixed

- Correct gradient edge cases, whitespace layout, fallback-font baselines and
  image sizing, ownership and resource refresh.
- Handle reentrant results and phase callbacks, delayed stop errors, queued
  structural configuration updates and background controller replacement.
- Align wheel, grid and slot motion and rendering with pinned upstream fixtures,
  including early stops, seams and slot text rasterization tolerances.

### Notes

- Requires Dart 3.5 and Flutter 3.24 or later. This is an unofficial Apache-2.0
  port; see NOTICE for attribution.
- The 0.1.0 candidate has not been published to pub.dev.
- Added games use deterministic animation by default; physics collision is an
  opt-in mode with a built-in solver, not a third-party engine. There is no built-in
  device shake detection. Widget overlays add rendering cost; 3D is an extension path.
- Device performance, Android integration and Skia/Impeller device shadows still
  require validation. Minimum-SDK and APK tree-shaking results are tracked separately
  in the release checklist; local checks do not imply remote CI success.

## 0.0.1

- Initial development snapshot.

## PERF 补充（2026-11-10，关联未发布的0.1.0）

- 新增默认 `LuckyCacheMode.auto`：支持的运动段使用受限物理像素位图，静止与结算后回放矢量；严格上游 frame 配置保守保留 Picture。
- 转盘遵守配置采样质量；数字盘、扭蛋球体、大乐透号码球及九宫格阴影背景按需缓存，补齐 DPR、原点和性能选项失效与释放验证。
- 保存 vivo V2417 的消融、三轮 profile 和 37° 截图证据；GLES 编码长延迟仍可能造成超标，未放宽预算，详见 docs/PERF_REPORT.md。
