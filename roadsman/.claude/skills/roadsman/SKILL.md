---
name: roadsman
description: Work on roadsman — a Flutter port of the casino monorepo's `apps/baccarat-roadmap` (TypeScript). Use when adding features, fixing bugs, or keeping the two implementations in sync.
---

# roadsman

Flutter port of `casino/apps/baccarat-roadmap`'s **`main` branch** (not `hilo` — see decision history). Same three-layer shape: `core` (pure Dart, zero Flutter dependency) → `render` (`RoadPainter`/`renderToSvg`) → `panel` (`RoadPanel` widget + UX add-ons). Full diagrams in [ARCHITECTURE.md](../../../ARCHITECTURE.md).

## Decision history (why it's built this way)

- **0.0.1 initial port (2026-07-16)**: translated from `casino/apps/baccarat-roadmap` at `main` HEAD. Before porting, checked whether `hilo` branch (which replaces the TS renderer with `HiloRenderer`) had anything worth merging into `main` first — confirmed the skeleton-screen feature was already fully synced (`skeleton.ts`/`ux/index.ts` byte-identical across branches) and the rest of the `main..hilo` diff is the renderer swap itself, which the user explicitly wanted kept out of `main`. So the port source is `main`'s three-renderer world (`renderer-canvas`/`renderer-shapes`/`renderer-svg`), not hilo's `HiloRenderer`.
- **`core/` is a near-literal translation**, function for function — it's pure computation with no platform dependency, so there was no reason to redesign it. `DrawCommand` (TS discriminated union) → Dart `sealed class` with one `final class` per variant; colors are ARGB 32-bit ints everywhere in `core`/`render` (not CSS strings) so the same code path serves `RoadPainter` (Flutter) and `renderToSvg` (pure Dart, no Flutter needed).
- **Render/panel layers are NOT literal translations** — three deliberate simplifications vs. the TS `renderer-canvas`/`gesture-adapter`/`frame-driver` trio:
  1. `CustomPainter` already does "full command-list repaint per frame" natively — no diff/scene-graph bookkeeping needed at the renderer level (that's what TS's Canvas renderer does too; Hilo's node-diffing approach was NOT ported, by design, since `main` doesn't have it).
  2. `GestureDetector`'s `onScaleStart/Update/End` replaces `gesture-adapter.ts` (AlloyFinger + Pointer Events) — Flutter's gesture system is already cross-platform. **Important**: `GestureDetector` throws an assertion if you register both pan and scale recognizers ("scale is a superset of pan") — `RoadPanel` uses only the scale family and branches on `details.pointerCount` to get pan-equivalent single-finger drag behavior. Caught by `test/road_panel_test.dart`.
  3. No `frame-driver.ts`/Hilo `StageDriver` equivalent — Flutter's `SchedulerBinding` already coalesces all widgets' per-frame work; each `RoadPanel` just uses `SingleTickerProviderStateMixin` directly.
- **`viewport.dart`'s physics (drag damping/inertia/rebound/zoom) is a literal port** — that's the actual product feel, not renderer plumbing, so it's translated function-for-function and covered by `test/viewport_test.dart` (including the zoom invariant: focal point's screen position must not move).
- **UX add-ons (`pulse`/`celebration`/etc.) are simplified to enable/disable controllers**, not full animation re-implementations — the TS versions hand-roll animation frame loops that splice temporary `DrawCommand`s into the draw list; in Flutter that's better done as a composable overlay (`AnimatedContainer`/`CustomPaint`) the consumer builds themselves, not baked into the library. `EmptyStateOverlay` is the one exception that's a real widget (it's just a centered `Text`, no reason to make it a controller).
- **`gridCommands`/`translateCommand`/etc. that exist in TS but never got re-exported from `main.ts`** (see the TS README's "已知的库入口收录空缺" section) were ported anyway when present in `core/` — the Dart barrel (`lib/roadsman.dart`) exports everything from `core`/`render`/`panel` without the TS barrel's historical gaps.

## Gotchas found during the port (fix once, don't reintroduce)

- `resolveTheme`'s `base` parameter can't have a `= defaultTheme` default value — `defaultTheme` is a `final` top-level variable (not `const`), and Dart requires default parameter values to be compile-time constants. Made `base` nullable and defaulted inside the function body instead.
- `math.pow(x, 3)` returns `num`, not `double` — every `Easing` function needs an explicit `.toDouble()` or the return type declaration fails.
- Don't import both `package:flutter/material.dart` and this package's `core/theme.dart` (or `types.dart`, which re-exports `Theme`) without `hide Theme` on one side — `Theme` collides with `material.dart`'s `Theme` class. Same issue with `Easing` if you ever import `material.dart`'s motion utilities alongside `core/animation.dart`.

## Verification

`flutter analyze && flutter test` at the package root (35+ core algorithm tests using hand-derived expected values cross-checked against the TS algorithm description — not copied from the TS fixture JSON's color-string format, since colors are represented differently, ints not CSS strings). `example/` has its own `flutter test` (widget smoke test) and `flutter analyze`.
