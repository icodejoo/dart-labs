/// Roadsman: A pure Dart engine for baccarat/dragon-tiger/sicbo road maps (beads plate) + Flutter rendering panel.
///
/// Ported from the casino monorepo's `apps/baccarat-roadmap` (TypeScript).
library;

// ---- Core types ----
export 'src/core/types.dart';

// ---- Theme system ----
export 'src/core/theme.dart';

// ---- Grid layout ----
export 'src/core/grid_layout.dart';

// ---- Engine ----
export 'src/core/engine.dart';

// ---- Animation system ----
export 'src/core/animation.dart';

// ---- Viewport state machine ----
export 'src/core/viewport.dart';

// ---- Store ----
export 'src/core/store.dart';

// ---- Type-safe event emitter ----
export 'src/core/emitter.dart';

// ---- Instruction pipeline ----
export 'src/core/pipeline.dart';

// ---- Prediction ----
export 'src/core/predict.dart';

// ---- GameSpec: pluggable game rules ----
export 'src/core/game_spec.dart';
export 'src/core/stream.dart';
export 'src/core/game_specs/baccarat.dart';
export 'src/core/game_specs/dragon_tiger.dart';
export 'src/core/game_specs/sicbo.dart';
export 'src/core/game_specs/roulette.dart';

// ---- Built-in road plugins ----
export 'src/core/roads/band_merge.dart';
export 'src/core/roads/derived_road.dart';
export 'src/core/roads/bead_plate.dart';
export 'src/core/roads/big_road.dart';
export 'src/core/roads/big_eye_boy.dart';
export 'src/core/roads/small_road.dart';
export 'src/core/roads/cockroach_road.dart';
export 'src/core/roads/pair_road.dart';
export 'src/core/roads/natural_road.dart';
export 'src/core/roads/derived_trio.dart';
export 'src/core/roads/compact_road_sheet.dart';
export 'src/core/roads/big_road_merged_dots.dart';
export 'src/core/roads/streak_highlight.dart';
export 'src/core/roads/stats_panel.dart';
export 'src/core/roads/index.dart';

// ---- Render: CustomPainter rendering layer + SVG pure function rendering ----
export 'src/render/road_painter.dart';
export 'src/render/svg_renderer.dart';

// ---- Panel: Widget, playback, UX enhancement package ----
export 'src/panel/road_panel.dart';
export 'src/panel/replayer.dart';
export 'src/panel/ux/index.dart';
