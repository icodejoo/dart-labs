/// roadmap：百家乐/龙虎/骰宝路子图（露珠图）纯 Dart 引擎 + Flutter 渲染面板。
///
/// 移植自 casino monorepo 的 `apps/baccarat-roadmap`（TypeScript）。
library;

// ---- Core types: 全部公共类型 ----
export 'src/core/types.dart';

// ---- Theme: 主题体系 ----
export 'src/core/theme.dart';

// ---- Grid layout: 物理网格布局 ----
export 'src/core/grid_layout.dart';

// ---- Engine: 引擎 ----
export 'src/core/engine.dart';

// ---- Animation: 动画系统 ----
export 'src/core/animation.dart';

// ---- Viewport: 视口状态机 ----
export 'src/core/viewport.dart';

// ---- Store: 数据 Store ----
export 'src/core/store.dart';

// ---- Emitter: 类型安全事件发射器 ----
export 'src/core/emitter.dart';

// ---- Pipeline: 指令管道 ----
export 'src/core/pipeline.dart';

// ---- Predict: 问路 ----
export 'src/core/predict.dart';

// ---- GameSpec: 可插拔游戏规则 ----
export 'src/core/game_spec.dart';
export 'src/core/stream.dart';
export 'src/core/game_specs/baccarat.dart';
export 'src/core/game_specs/dragon_tiger.dart';
export 'src/core/game_specs/sicbo.dart';
export 'src/core/game_specs/roulette.dart';

// ---- Roads: 内置路插件 ----
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

// ---- Render: CustomPainter 渲染层 + SVG 纯函数渲染 ----
export 'src/render/road_painter.dart';
export 'src/render/svg_renderer.dart';

// ---- Panel: 面板 Widget、回放、UX 增强包 ----
export 'src/panel/road_panel.dart';
export 'src/panel/replayer.dart';
export 'src/panel/ux/index.dart';
