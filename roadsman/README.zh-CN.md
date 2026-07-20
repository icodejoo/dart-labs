# roadsman

百家乐/龙虎斗/骰宝路子图（露珠图）的 Flutter 实现，完整移植自 casino monorepo 的 `apps/baccarat-roadmap`（TypeScript，`main` 分支）。

## 它做什么

把一靴百家乐（或龙虎斗/骰宝）的原始开牌结果（庄/闲/和 + 对子/例牌标记）画成行业标准的"路"：

- **珠盘路** — 按开牌顺序逐格填，每格一个彩色圆，最直白的历史记录。
- **大路** — 把连续同一赢家归并成列，是其余衍生路的算法基础。
- **大眼仔 / 小路 / 曱甴路** — 三种衍生路，算法同一套参数化逻辑，只有列偏移量 k 和标记样式不同。
- **对子路 / 例牌路** — 单独摘录有对子或天生 8/9 的局。
- **三合一 / 紧凑路纸** — 把三条衍生路（或再加上大路）合画在同一张网格上，模拟真实台面记分牌的紧凑呈现。
- **统计面板** — 庄/闲/和计数与占比、最长连状态。

引擎内置了百家乐、龙虎斗、骰宝三套游戏规格（`GameSpec`），插件/引擎/渲染层都不写死百家乐语义，切换游戏类型不需要改任何底层代码。

## 架构

沿用 TS 原版的三层结构：`core`（纯 Dart，零 Flutter 依赖，算数据和布局）→ `render`（`RoadPainter`——`CustomPainter` 消费 `DrawCommand` 列表；外加零 Flutter 依赖的纯函数 `renderToSvg`）→ `panel`（`RoadPanel` widget：手势、视口物理、逐格动画、回放、UX 增强）。

完整的分层图、数据流时序图，以及和 TS 版本几处刻意简化的差异说明，见 [ARCHITECTURE.md](ARCHITECTURE.md)。

## 快速上手

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

完整功能的 demo（切换游戏类型、勾选路、手工加一局、回放、问路、UX 开关）在 `example/` 下。

## 跑 demo

```bash
cd example
flutter pub get
flutter run
```

## 主题系统

内置 `defaultTheme`（深色）、`darkTheme`、`lightTheme` 三套预置，`resolveTheme()` 可以只覆盖需要改的字段：

```dart
final theme = resolveTheme(palette: (p) => p.copyWith(banker: 0xFFFF0000));
```

颜色在 `core` 和 `render` 里统一是 ARGB 32 位整数，不是 CSS 字符串——`core` 从不 import `dart:ui`，同一份主题在没有 Flutter 运行时的服务端跑 `renderToSvg` 也能直接用。

## 引擎健壮性

任一插件的 `derive`/`layout`/`predict` 抛错时，该路的错误记入 `ComputeOutput.errors`，其他路照常渲染，不会因为一个插件出错就白屏。

## API 参考

下面全部导出自 `roadsman` 库入口（`import 'package:roadsman/roadsman.dart'`）。

### 核心类型（`core/types.dart`）

| 导出 | 说明 |
| --- | --- |
| `RawResult` | 一局的原始结果：局号、赢家、对子/例牌标记、可选点数。 |
| `Shoe` | 一靴完整数据：靴 id、台号、开始时间、`List<RawResult>`。 |
| `BigRoadCell` / `BigRoadData` | 大路一个格子 / 整条大路的推导结果（含列高、开局前和局数）。 |
| `DerivedColor` / `DerivedRoadData` | 衍生路的红蓝条目，带回指源大路格子的索引。 |
| `LayoutConfig` | 每个插件 `layout()` 的输入：格子尺寸、行数、主题。 |
| `DrawCommand` | sealed class，6 个子类型（`CircleCommand`/`LineCommand`/`SlashCommand`/`DotCommand`/`BadgeCommand`/`RectCommand`）——渲染无关的绘制指令集。 |
| `LayoutCell` | 带稳定 `key` 的定位格子，供跨帧 diff 用。 |
| `RoadLayout` | `layout()` 完整输出：格子 + 可选装饰 + 内容尺寸 + 网格规格。 |
| `GridSpec` / `GridStyle` | 背景网格呈现规格（细线网格或圆角瓷砖）。 |
| `RoadContext` | 传给 `derive`/`layout`/`predict` 的计算上下文：结果、规格、`stream()`、`get<T>()`。 |
| `toGenericResult` / `fromGenericResult` | `RawResult` 与游戏无关的 `GenericResult` 互相转换。 |
| `RoadKind` | 插件类别：`grid` / `overlay` / `summary`。 |
| `RoadPlugin<TData>` | 每条路必须实现的契约。 |
| `PredictionForRoad` | 问路结果：假设下一局开庄/开闲，路会落什么颜色。 |
| `StatsData` / `CurrentStreak` | 统计面板的推导数据。 |
| `ViewportPhase` / `ViewportState` / `ViewportBounds` / `ViewportConfig` | 视口状态机相关类型。 |
| `ConfigField` / `ConfigFieldType` / `ConfigFieldOption` | 插件自描述配置项，驱动自动生成的设置面板。 |

### 主题（`core/theme.dart`）

`Theme`、`Palette`、`CanvasTheme`、`GridTheme`、`CellTheme`、`LabelsTheme`、`FontsTheme`、`RoadTheme`——结构类型，各自带 `copyWith`。`defaultTheme`/`darkTheme`/`lightTheme`——内置实例。`resolveTheme({base, palette, canvas, grid, cell, labels, fonts, roads})`——通过按字段传入的映射回调把覆盖叠加到基础主题上。

### 引擎（`core/engine.dart`）

`createEngine(enabledIds, {spec})`——展开传递依赖、拓扑排序，返回 `Engine`。`Engine.compute(results, cfg)` 返回 `ComputeOutput`（`layouts`/`data`/`predictions`/`errors`）。

### 视口（`core/viewport.dart`）

纯状态机函数：`createViewport()`、`dragBy()`、`endDrag()`、`stepViewport()`、`computeBounds()`、`zoomAt()`、`startAutoScroll()`，以及 `defaultViewportConfig`。

### 动画（`core/animation.dart`）

`diffLayout(prev, next)` → `List<Transition>`（`EnterTransition`/`MoveTransition`/`ExitTransition`）。`sampleEnter`/`sampleMove`/`sampleExit` 按进度采样插值指令；`registerEnterAnimation`/`registerMoveAnimation`/`registerExitAnimation` 注册自定义命名动画。`Easing`（linear/easeOutCubic/easeOutBack/spring）。`applyWindow` 把布局裁剪成滚动列窗口。`translateCommands`/`translateCommand` 供手动拼接布局用。

### 数据 Store（`core/store.dart`）

`createStore({onOutOfSync})` → `RoadmapStore`，提供 `setResults`/`append`/`patch`/`getResults`/`subscribe`。`UpdateKind`（`full`/`append`/`patch`）标记每次 `ChangeEvent`。

### 指令管道（`core/pipeline.dart`）

`createPipeline()` / `globalPipeline`——compute 输出与渲染层之间的有序命名 `CommandTransform` 链。内置：`watermarkTransform(text, opts)`、`grayscaleTransform()`。

### 问路（`core/predict.dart`）

`predictNextOutcome(results)`——基于历史统计给出下一局的概率倾向（与上面"逐路问路"机制是两回事）。

### 物理网格布局（`core/grid_layout.dart`）

`placeOnGrid`、`placeSequential`、`cellToPixel`、`gridCommands`、`contentSize`、`roundTo`。

### 游戏规则（`core/game_spec.dart`、`stream.dart`、`game_specs/*`）

`GameSpec`、`GenericResult`、`OutcomeDef`、`MarkerDef`、`StreamSelector`（sealed：`OutcomeSelector`/`RangeSelector`/`MarkSelector`）、`StreamDef`、`validateGameSpecJson`。`resolveToken`、`colorForToken`、`labelForToken`、`getStreamDef`。内置规格：`baccaratSpec`、`dragonTigerSpec`、`sicboSpec`。

### 路插件（`core/roads/*`）

12 个内置插件注册在 `roadRegistry`（`Map<String, RoadPlugin>`），`createEngine` 按 `dependsOn` 自动展开依赖：

| id | 类别 | 依赖 | 说明 |
| --- | --- | --- | --- |
| `beadPlate` | grid | — | 珠盘路，不归并。 |
| `bigRoad` | grid | — | 其余大部分路的算法基础。`buildBigRoad(results)` 单独导出。 |
| `bigEyeBoy` | grid | `bigRoad` | k=1 偏移。 |
| `smallRoad` | grid | `bigRoad` | k=2 偏移。 |
| `cockroachRoad` | grid | `bigRoad` | k=3 偏移。 |
| `pairRoad` | grid | — | |
| `naturalRoad` | grid | — | |
| `derivedTrio` | grid | 三条衍生路 | 合画在一张网格上。 |
| `compactRoadSheet` | grid | 大路 + 三条衍生路 | 三合一之上再叠大路，共 12 大行。 |
| `bigRoadMergedDots` | overlay | 大路 + 三条衍生路 | 把衍生路颜色以圆点/斜线嵌入大路格子。 |
| `streakHighlight` | overlay | `bigRoad` | 长龙/单跳/双跳背景高亮。 |
| `statsPanel` | summary | `bigRoad` | 产出 `StatsData`。 |

`deriveRoad(bigRoad, k)`、`mergeBands(bands)` 分别是三条衍生路、合板类插件共用的算法本体。

### 渲染层（`render/*`）

`RoadPainter`（`CustomPainter`）——唯一内置渲染实现。`renderToSvg(layout, theme, {width, height, grid})`——纯函数 SVG 导出，不 import `dart:ui`。

**绘制回调** —— `RoadPainter`/`RoadFramePainter`（以及下面的 `RoadPanel`）都接受 4 个可选回调，用于在内置绘制前后插入自定义绘制，且不替换内置绘制本身：

- `onBeforePaintGridCell`/`onAfterPaintGridCell`（`GridCellPaintCallback`）——每个背景网格瓷砖触发一次，仅 `GridStyle.tile` 生效。携带 `GridCellPaintInfo`：当前画布、瓷砖的 `rect`/`color`，以及遍历序号 `row`/`col`（方便做棋盘配色之类的自定义底图）。
- `onBeforePaintCommand`/`onAfterPaintCommand`（`CommandPaintCallback`）——每条 `DrawCommand`（圆/线/斜线/点/文字标记/矩形，含叠加层）触发一次。携带 `CommandPaintInfo`：当前画布、以及原始 `command`——switch 其运行时类型即可拿到全部坐标/尺寸/颜色字段。

`before` 画在内置图形下面，`after` 画在上面——层级完全由这两个时机控制。四个都不传（默认）时零开销，网格层/内容层原有的 Picture 缓存快速路径不受影响；一旦设置了任意一个，对应那一层当帧会退回逐条直绘（Picture 重放没法触发 Dart 回调），用拖拽/惯性帧的部分性能换正确性。

### 面板（`panel/*`）

`RoadPanel`——面板 widget。`FollowTail`（`none`/`hard`/`ease`）和 `RoadUpdateKind`（`setResults`/`append`/`patch`）控制视口跟随和是否播放插入动画。`createReplayer(fullResults, store, {opts})` → `Replayer`，提供 `play`/`pause`/`seek`/`stop`。`RoadPanel` 同样暴露上面那 4 个绘制回调，设置后会原样透传给内部 painter。

### UX 增强包（`panel/ux/*`）

`createPulseEffect`、`createCelebrationEffect`、`EmptyStateOverlay` widget、`createHapticsEffect`、`createDoubleTapToTail`、`prefersReducedMotion(context)`、`createSkeletonRenderer`/`defaultSkeletonAdapter`。这些比 TS 版本对应实现更轻——具体为什么这样简化，见 [ARCHITECTURE.md](ARCHITECTURE.md)。

## 开发

```bash
flutter pub get
flutter analyze
flutter test
```

## 许可证

MIT
