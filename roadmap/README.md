# roadmap

Baccarat / Dragon Tiger / Sic Bo "road map" (bead-road) visualization for Flutter — a full port of the TypeScript `apps/baccarat-roadmap` package from the casino monorepo (`main` branch).

中文说明见 [README.zh-CN.md](README.zh-CN.md)。

## What it does

Turns a shoe's raw round-by-round results (banker/player/tie + pair/natural marks) into the industry-standard "roads" used at real tables:

- **Bead Plate** — one bead per round, in play order, no merging.
- **Big Road** — consecutive same-winner runs merged into columns; the base every derived road builds on.
- **Big Eye Boy / Small Road / Cockroach Pig** — three derived roads sharing one parametric algorithm, differing only in the column-offset `k` and marker shape.
- **Pair Road / Natural Road** — dedicated roads for banker/player-pair and natural (8/9) hands.
- **Derived Trio / Compact Road Sheet** — the three derived roads (optionally plus Big Road) combined onto one scoreboard-style grid.
- **Stats Panel** — banker/player/tie counts and percentages, longest streaks, current streak.

Baked-in support for Baccarat, Dragon Tiger, and Sic Bo via a pluggable `GameSpec` — the engine, plugins, and renderer don't hardcode baccarat semantics anywhere.

## Architecture

Three layers, same shape as the TS original: `core` (pure Dart, zero Flutter dependency — computes data and layout) → `render` (`RoadPainter`, a `CustomPainter` that draws a `DrawCommand` list; plus `renderToSvg`, a pure function for server-side rendering) → `panel` (`RoadPanel` widget: gestures, viewport physics, per-cell animation, replay, UX extras).

Full diagrams and a rundown of where this diverges from the TS version (and why) are in [ARCHITECTURE.md](ARCHITECTURE.md).

## Quick start

```dart
import 'package:flutter/material.dart' hide Theme;
import 'package:roadmap/roadmap.dart';

class BigRoadDemo extends StatefulWidget {
  const BigRoadDemo({super.key});
  @override
  State<BigRoadDemo> createState() => _BigRoadDemoState();
}

class _BigRoadDemoState extends State<BigRoadDemo> {
  final engine = createEngine(['bigRoad']);
  final store = createStore();
  ComputeOutput? output;

  @override
  void initState() {
    super.initState();
    store.subscribe((_) => setState(_recompute));
    store.append(const RawResult(no: 1, winner: 'B', bankerPair: false, playerPair: false));
  }

  void _recompute() {
    final cfg = LayoutConfig(cellSize: 18, rows: 6, theme: resolveTheme());
    output = engine.compute(store.getResults(), cfg);
  }

  @override
  Widget build(BuildContext context) {
    final layout = output?.layouts['bigRoad'];
    if (layout == null) return const SizedBox.shrink();
    return RoadPanel(
      cells: layout.cells,
      decorations: layout.decorations ?? const [],
      contentWidth: layout.contentWidth,
      contentHeight: layout.contentHeight,
      theme: resolveTheme(),
      panelWidth: 360,
      panelHeight: 108,
      eventType: RoadUpdateKind.append,
    );
  }
}
```

See `example/` for a complete demo app: game-type switching, road checkboxes, manual "add a round", replay, ask-the-road (predict), and UX toggles.

## Run the demo

```bash
cd example
flutter pub get
flutter run
```

## Theming

Three built-in themes — `defaultTheme` (dark), `darkTheme`, `lightTheme` — plus `resolveTheme()` for overriding any field without touching plugin code:

```dart
final theme = resolveTheme(palette: (p) => p.copyWith(banker: 0xFFFF0000));
```

Colors are ARGB 32-bit integers throughout `core` and `render` (not CSS strings) — `core` never imports `dart:ui`, so the same theme values work in `renderToSvg` on a server with no Flutter runtime at all.

## Engine robustness

If a plugin's `derive`/`layout`/`predict` throws, that road's error is recorded in `ComputeOutput.errors` and every other road keeps rendering — no blank screen from one bad plugin.

## API reference

Everything below is exported from the `roadmap` barrel (`import 'package:roadmap/roadmap.dart'`).

### Core types (`core/types.dart`)

| Export | What it is |
| --- | --- |
| `RawResult` | One round's raw result: number, winner, pair/natural marks, optional point totals. |
| `Shoe` | A full shoe: id, table id, start time, `List<RawResult>`. |
| `BigRoadCell` / `BigRoadData` | One Big Road cell / the full derived Big Road (cells + column heights + leading ties). |
| `DerivedColor` / `DerivedRoadData` | Red/blue entries for a derived road, with back-references to their source Big Road cells. |
| `LayoutConfig` | Input to every plugin's `layout()`: cell size, row count, theme. |
| `DrawCommand` | Sealed class with 6 variants (`CircleCommand`/`LineCommand`/`SlashCommand`/`DotCommand`/`BadgeCommand`/`RectCommand`) — the renderer-agnostic drawing instruction set. |
| `LayoutCell` | A positioned, animatable grid cell with a stable `key` for diffing. |
| `RoadLayout` | Full `layout()` output: cells + optional decorations + content size + grid spec. |
| `GridSpec` / `GridStyle` | Background grid presentation spec (line mesh or rounded tiles). |
| `RoadContext` | Compute context passed to `derive`/`layout`/`predict`: results, spec, `stream()`, `get<T>()`. |
| `toGenericResult` / `fromGenericResult` | Convert between `RawResult` and the game-agnostic `GenericResult`. |
| `RoadKind` | Plugin category: `grid` / `overlay` / `summary`. |
| `RoadPlugin<TData>` | The contract every road implements. |
| `PredictionForRoad` | "Ask the road" result: what color a road would fall if the next hand is banker/player. |
| `StatsData` / `CurrentStreak` | Stats-panel derived data. |
| `ViewportPhase` / `ViewportState` / `ViewportBounds` / `ViewportConfig` | Viewport state-machine types. |
| `ConfigField` / `ConfigFieldType` / `ConfigFieldOption` | Self-describing plugin config field, for auto-generated settings UIs. |

### Theme (`core/theme.dart`)

`Theme`, `Palette`, `CanvasTheme`, `GridTheme`, `CellTheme`, `LabelsTheme`, `FontsTheme`, `RoadTheme` — structure types, each with a `copyWith`. `defaultTheme`, `darkTheme`, `lightTheme` — built-in instances. `resolveTheme({base, palette, canvas, grid, cell, labels, fonts, roads})` — layer overrides onto a base theme via per-field mapper callbacks.

### Engine (`core/engine.dart`)

`createEngine(enabledIds, {spec})` — resolves transitive plugin dependencies, topologically sorts them, returns an `Engine`. `Engine.compute(results, cfg)` returns a `ComputeOutput` (`layouts`, `data`, `predictions`, `errors`).

### Viewport (`core/viewport.dart`)

Pure state-machine functions: `createViewport()`, `dragBy()`, `endDrag()`, `stepViewport()`, `computeBounds()`, `zoomAt()`, `startAutoScroll()`, plus `defaultViewportConfig`.

### Animation (`core/animation.dart`)

`diffLayout(prev, next)` → `List<Transition>` (`EnterTransition`/`MoveTransition`/`ExitTransition`). `sampleEnter`/`sampleMove`/`sampleExit` sample interpolated commands at a given progress; `registerEnterAnimation`/`registerMoveAnimation`/`registerExitAnimation` add custom named animations. `Easing` (linear/easeOutCubic/easeOutBack/spring). `applyWindow` clips a layout to a scrolling column window. `translateCommands`/`translateCommand` for manual composition.

### Store (`core/store.dart`)

`createStore({onOutOfSync})` → `RoadmapStore` with `setResults`/`append`/`patch`/`getResults`/`subscribe`. `UpdateKind` (`full`/`append`/`patch`) tags each `ChangeEvent`.

### Pipeline (`core/pipeline.dart`)

`createPipeline()` / `globalPipeline` — an ordered, named `CommandTransform` chain between compute output and the renderer. Built-ins: `watermarkTransform(text, opts)`, `grayscaleTransform()`.

### Predict (`core/predict.dart`)

`predictNextOutcome(results)` — statistical next-round tendency (independent of the per-road "ask the road" mechanism above).

### Grid layout (`core/grid_layout.dart`)

`placeOnGrid`, `placeSequential`, `cellToPixel`, `gridCommands`, `contentSize`, `roundTo`.

### Game rules (`core/game_spec.dart`, `stream.dart`, `game_specs/*`)

`GameSpec`, `GenericResult`, `OutcomeDef`, `MarkerDef`, `StreamSelector` (sealed: `OutcomeSelector`/`RangeSelector`/`MarkSelector`), `StreamDef`, `validateGameSpecJson`. `resolveToken`, `colorForToken`, `labelForToken`, `getStreamDef`. Built-in specs: `baccaratSpec`, `dragonTigerSpec`, `sicboSpec`.

### Road plugins (`core/roads/*`)

12 built-in plugins registered in `roadRegistry` (`Map<String, RoadPlugin>`), auto-resolved by `createEngine` via `dependsOn`:

| id | kind | depends on | notes |
| --- | --- | --- | --- |
| `beadPlate` | grid | — | Bead plate, no merging. |
| `bigRoad` | grid | — | The algorithmic base for most other roads. `buildBigRoad(results)` is exported standalone. |
| `bigEyeBoy` | grid | `bigRoad` | k=1 offset. |
| `smallRoad` | grid | `bigRoad` | k=2 offset. |
| `cockroachRoad` | grid | `bigRoad` | k=3 offset. |
| `pairRoad` | grid | — | |
| `naturalRoad` | grid | — | |
| `derivedTrio` | grid | 3 derived roads | Combines them onto one grid. |
| `compactRoadSheet` | grid | Big Road + 3 derived | Adds Big Road on top of the trio, 12 macro-rows total. |
| `bigRoadMergedDots` | overlay | Big Road + 3 derived | Embeds the derived roads' colors as small dots/slashes on Big Road cells. |
| `streakHighlight` | overlay | `bigRoad` | Dragon/single-hop/double-hop background highlighting. |
| `statsPanel` | summary | `bigRoad` | Produces `StatsData`. |

`deriveRoad(bigRoad, k)` and `mergeBands(bands)` are the shared algorithms behind the derived roads and the combined-grid plugins, respectively.

### Renderer (`render/*`)

`RoadPainter` (`CustomPainter`) — the only built-in Flutter renderer. `renderToSvg(layout, theme, {width, height, grid})` — pure-function SVG export, no `dart:ui` import.

### Panel (`panel/*`)

`RoadPanel` — the widget. `FollowTail` (`none`/`hard`/`ease`) and `RoadUpdateKind` (`setResults`/`append`/`patch`) control tail-following and whether insert animations play. `createReplayer(fullResults, store, {opts})` → `Replayer` with `play`/`pause`/`seek`/`stop`.

### UX add-ons (`panel/ux/*`)

`createPulseEffect`, `createCelebrationEffect`, `EmptyStateOverlay` widget, `createHapticsEffect`, `createDoubleTapToTail`, `prefersReducedMotion(context)`, `createSkeletonRenderer`/`defaultSkeletonAdapter`. These are intentionally lighter than their TS counterparts — see [ARCHITECTURE.md](ARCHITECTURE.md) for why.

## Development

```bash
flutter pub get
flutter analyze
flutter test
```

## License

MIT
