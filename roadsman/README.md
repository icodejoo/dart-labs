**English** | [简体中文](README.zh-CN.md)

# roadsman

Road map (bead road) charts for Baccarat, Dragon Tiger and Sic Bo, for Flutter.

## What it does

Takes a shoe's round-by-round results (banker/player/tie, plus pair and natural marks) and builds the standard roads used at real tables:

- **Bead Plate**: one bead per round, in play order, nothing merged.
- **Big Road**: runs of the same winner are merged into columns. Most other roads are built from it.
- **Big Eye Boy / Small Road / Cockroach Pig**: three derived roads that share one algorithm. They differ only in the column offset `k` and the marker shape.
- **Pair Road / Natural Road**: roads for banker/player pairs and for natural (8/9) hands.
- **Derived Trio / Compact Road Sheet**: the three derived roads (optionally with Big Road) on one scoreboard-style grid.
- **Stats Panel**: banker/player/tie counts and percentages, longest streaks, current streak.

Baccarat, Dragon Tiger and Sic Bo are supported through a `GameSpec`. The engine, plugins and renderer don't hardcode any baccarat rules.

## Architecture

There are three layers:

- `core`: pure Dart with no Flutter dependency. It computes data and layout.
- `render`: `RoadPainter`, a `CustomPainter` that draws a list of `DrawCommand`s, and `renderToSvg`, a pure function for rendering on a server.
- `panel`: the `RoadPanel` widget. It handles gestures, viewport physics, per-cell animation, replay and some UX extras.

Diagrams are in [ARCHITECTURE.md](ARCHITECTURE.md).

## Quick start

```dart
import 'package:flutter/material.dart' hide Theme;
import 'package:roadsman/roadsman.dart';

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

`example/` has a full demo app: switch game type, toggle roads with checkboxes, add a round by hand, replay, "ask the road" (predict), and the UX toggles.

## Run the demo

```bash
cd example
flutter pub get
flutter run
```

## Theming

There are three built-in themes: `defaultTheme` (dark), `darkTheme` and `lightTheme`. Use `resolveTheme()` to override any field without touching plugin code:

```dart
final theme = resolveTheme(palette: (p) => p.copyWith(banker: 0xFFFF0000));
```

Colors are 32-bit ARGB integers in `core` and `render`, not CSS strings. `core` never imports `dart:ui`, so the same theme works in `renderToSvg` on a server with no Flutter runtime.

## Engine robustness

If a plugin's `derive`, `layout` or `predict` throws, the error is recorded in `ComputeOutput.errors` and the other roads keep rendering. One bad plugin doesn't blank the screen.

## API reference

Everything below is exported from `package:roadsman/roadsman.dart`.

### Core types (`core/types.dart`)

| Export | What it is |
| --- | --- |
| `RawResult` | One round's raw result: number, winner, pair/natural marks, optional point totals. |
| `Shoe` | A full shoe: id, table id, start time, `List<RawResult>`. |
| `BigRoadCell` / `BigRoadData` | One Big Road cell / the full derived Big Road (cells, column heights, leading ties). |
| `DerivedColor` / `DerivedRoadData` | Red/blue entries of a derived road, with references back to their source Big Road cells. |
| `LayoutConfig` | Input to every plugin's `layout()`: cell size, row count, theme. |
| `DrawCommand` | Sealed class with 6 variants (`CircleCommand`/`LineCommand`/`SlashCommand`/`DotCommand`/`BadgeCommand`/`RectCommand`). The drawing instructions, independent of any renderer. |
| `LayoutCell` | A positioned, animatable grid cell with a stable `key` for diffing. |
| `RoadLayout` | Output of `layout()`: cells, optional decorations, content size, grid spec. |
| `GridSpec` / `GridStyle` | Background grid spec (line mesh or rounded tiles). |
| `RoadContext` | Context passed to `derive`/`layout`/`predict`: results, spec, `stream()`, `get<T>()`. |
| `toGenericResult` / `fromGenericResult` | Convert between `RawResult` and the game-agnostic `GenericResult`. |
| `RoadKind` | Plugin category: `grid` / `overlay` / `summary`. |
| `RoadPlugin<TData>` | The contract every road implements. |
| `PredictionForRoad` | Result of "ask the road": what color a road would get if the next hand is banker or player. |
| `StatsData` / `CurrentStreak` | Data for the stats panel. |
| `ViewportPhase` / `ViewportState` / `ViewportBounds` / `ViewportConfig` | Viewport state machine types. |
| `ConfigField` / `ConfigFieldType` / `ConfigFieldOption` | A plugin config field that describes itself, so a settings UI can be generated. |

### Theme (`core/theme.dart`)

- Structure types, each with a `copyWith`: `Theme`, `Palette`, `CanvasTheme`, `GridTheme`, `CellTheme`, `LabelsTheme`, `FontsTheme`, `RoadTheme`.
- Built-in instances: `defaultTheme`, `darkTheme`, `lightTheme`.
- `resolveTheme({base, palette, canvas, grid, cell, labels, fonts, roads})` applies overrides on top of a base theme. Each override is a callback that maps the old field to a new one.

### Engine (`core/engine.dart`)

`createEngine(enabledIds, {spec})` resolves plugin dependencies (including indirect ones), sorts them topologically and returns an `Engine`. `Engine.compute(results, cfg)` returns a `ComputeOutput` (`layouts`, `data`, `predictions`, `errors`).

### Viewport (`core/viewport.dart`)

Pure state-machine functions: `createViewport()`, `dragBy()`, `endDrag()`, `stepViewport()`, `computeBounds()`, `zoomAt()`, `startAutoScroll()`, and `defaultViewportConfig`.

### Animation (`core/animation.dart`)

- `diffLayout(prev, next)` returns a `List<Transition>` (`EnterTransition`/`MoveTransition`/`ExitTransition`).
- `sampleEnter`/`sampleMove`/`sampleExit` give the interpolated commands at a given progress.
- `registerEnterAnimation`/`registerMoveAnimation`/`registerExitAnimation` add custom named animations.
- `Easing` has linear, easeOutCubic, easeOutBack and spring.
- `applyWindow` clips a layout to a scrolling column window.
- `translateCommands`/`translateCommand` move commands by hand.

### Store (`core/store.dart`)

`createStore({onOutOfSync})` returns a `RoadmapStore` with `setResults`/`append`/`patch`/`getResults`/`subscribe`. `UpdateKind` (`full`/`append`/`patch`) tags each `ChangeEvent`.

### Pipeline (`core/pipeline.dart`)

`createPipeline()` / `globalPipeline` is an ordered, named chain of `CommandTransform`s that sits between compute output and the renderer. Built-ins: `watermarkTransform(text, opts)`, `grayscaleTransform()`.

### Predict (`core/predict.dart`)

`predictNextOutcome(results)` gives a statistical tendency for the next round. It is separate from the per-road "ask the road" mechanism above.

### Grid layout (`core/grid_layout.dart`)

`placeOnGrid`, `placeSequential`, `cellToPixel`, `gridCommands`, `contentSize`, `roundTo`.

### Game rules (`core/game_spec.dart`, `stream.dart`, `game_specs/*`)

- Types: `GameSpec`, `GenericResult`, `OutcomeDef`, `MarkerDef`, `StreamSelector` (sealed: `OutcomeSelector`/`RangeSelector`/`MarkSelector`), `StreamDef`.
- Functions: `validateGameSpecJson`, `resolveToken`, `colorForToken`, `labelForToken`, `getStreamDef`.
- Built-in specs: `baccaratSpec`, `dragonTigerSpec`, `sicboSpec`.

### Road plugins (`core/roads/*`)

There are 12 built-in plugins in `roadRegistry` (`Map<String, RoadPlugin>`). `createEngine` pulls in dependencies from `dependsOn` automatically.

| id | kind | depends on | notes |
| --- | --- | --- | --- |
| `beadPlate` | grid | none | Bead plate, no merging. |
| `bigRoad` | grid | none | Base of most other roads. `buildBigRoad(results)` is also exported on its own. |
| `bigEyeBoy` | grid | `bigRoad` | k=1 offset. |
| `smallRoad` | grid | `bigRoad` | k=2 offset. |
| `cockroachRoad` | grid | `bigRoad` | k=3 offset. |
| `pairRoad` | grid | none | |
| `naturalRoad` | grid | none | |
| `derivedTrio` | grid | 3 derived roads | Puts them on one grid. |
| `compactRoadSheet` | grid | Big Road + 3 derived | Adds Big Road on top of the trio, 12 macro-rows in total. |
| `bigRoadMergedDots` | overlay | Big Road + 3 derived | Draws the derived roads' colors as small dots/slashes on Big Road cells. |
| `streakHighlight` | overlay | `bigRoad` | Highlights dragons, single hops and double hops in the background. |
| `statsPanel` | summary | `bigRoad` | Produces `StatsData`. |

`deriveRoad(bigRoad, k)` is the algorithm behind the derived roads. `mergeBands(bands)` is the one behind the combined-grid plugins.

### Renderer (`render/*`)

`RoadPainter` (`CustomPainter`) is the only built-in Flutter renderer. `renderToSvg(layout, theme, {width, height, grid})` exports SVG as a pure function, with no `dart:ui` import.

**Paint hooks.** `RoadPainter`, `RoadFramePainter` and `RoadPanel` take four optional callbacks. They draw under or over the built-in paint and don't replace it:

- `onBeforePaintGridCell`/`onAfterPaintGridCell` (`GridCellPaintCallback`) fire once per background tile, and only with `GridStyle.tile`. They get a `GridCellPaintInfo`: the live `Canvas`, the tile's `rect` and `color`, and its `row`/`col` in loop order (useful for checkerboard fills).
- `onBeforePaintCommand`/`onAfterPaintCommand` (`CommandPaintCallback`) fire once per `DrawCommand` (circle/line/slash/dot/badge/rect, overlay commands included). They get a `CommandPaintInfo`: the live `Canvas` and the exact `command`. Switch on its runtime type to read the coordinates, size and color.

`before` draws under the built-in shape and `after` draws over it. That is all the z-order control there is.

If all four are `null` (the default), nothing changes: the Picture-cache fast paths for the grid layer and content layer stay in use. If you set any of them, that layer is drawn directly each frame, because Picture playback can't call a Dart callback. Dragging and inertia frames get slower as a result.

### Panel (`panel/*`)

- `RoadPanel` is the widget. It takes the same four paint hooks as `RoadPainter` and passes them to its internal painter.
- `FollowTail` (`none`/`hard`/`ease`) controls tail-following. `RoadUpdateKind` (`setResults`/`append`/`patch`) controls whether insert animations play.
- `createReplayer(fullResults, store, {opts})` returns a `Replayer` with `play`/`pause`/`seek`/`stop`.

### UX add-ons (`panel/ux/*`)

`createPulseEffect`, `createCelebrationEffect`, the `EmptyStateOverlay` widget, `createHapticsEffect`, `createDoubleTapToTail`, `prefersReducedMotion(context)`, `createSkeletonRenderer`/`defaultSkeletonAdapter`. They are deliberately simpler than their TS counterparts. [ARCHITECTURE.md](ARCHITECTURE.md) explains why.

## Development

```bash
flutter pub get
flutter analyze
flutter test
```

## License

MIT
