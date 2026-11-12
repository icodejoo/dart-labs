[English](README.md) | **简体中文**

# roadsman

Flutter 用的路单（珠盘路）图表库，支持百家乐、龙虎和骰宝。

## 能做什么

输入一靴牌每一局的结果（庄/闲/和，加上对子和例牌标记），生成真实牌桌上常见的各种路单：

- **珠盘路**：每局一颗珠，按开局顺序排，不合并。
- **大路**：连续同一方赢的局合并成一列。其他大多数路单都以它为基础。
- **大眼仔 / 小路 / 曱甴路**：三种衍生路，共用同一个算法，只有列偏移 `k` 和标记形状不同。
- **对子路 / 例牌路**：分别记录庄/闲对子和例牌（8/9 点）。
- **衍生三路 / 紧凑路单**：把三种衍生路（可再加大路）放在同一张记分牌式的格子里。
- **统计面板**：庄/闲/和的局数和占比、最长连赢、当前连赢。

三种游戏通过 `GameSpec` 支持。引擎、插件和渲染器里都没有写死百家乐的规则。

## 架构

分三层：

- `core`：纯 Dart，不依赖 Flutter，负责计算数据和布局。
- `render`：`RoadPainter` 是个 `CustomPainter`，按 `DrawCommand` 列表绘制；`renderToSvg` 是纯函数，可以在服务端渲染。
- `panel`：`RoadPanel` 组件，管手势、视口物理、单元格动画、回放和一些交互小功能。

架构图见 [ARCHITECTURE.md](ARCHITECTURE.md)。

## 快速开始

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

`example/` 里有完整的演示应用：切换游戏类型、勾选要显示的路单、手动加一局、回放、问路（预测）和各种交互开关。

## 运行演示

```bash
cd example
flutter pub get
flutter run
```

## 主题

内置三套主题：`defaultTheme`（深色）、`darkTheme` 和 `lightTheme`。用 `resolveTheme()` 可以改任意字段，不用动插件代码：

```dart
final theme = resolveTheme(palette: (p) => p.copyWith(banker: 0xFFFF0000));
```

`core` 和 `render` 里的颜色都是 32 位 ARGB 整数，不是 CSS 字符串。`core` 从不引入 `dart:ui`，所以同一套主题也能在没有 Flutter 运行时的服务端用 `renderToSvg`。

## 引擎的容错

插件的 `derive`、`layout` 或 `predict` 抛异常时，错误会记到 `ComputeOutput.errors`，其他路单照常渲染。一个插件出错不会让整个界面变空白。

## API 参考

下面的内容都从 `package:roadsman/roadsman.dart` 导出。

### 核心类型（`core/types.dart`）

| 导出 | 说明 |
| --- | --- |
| `RawResult` | 一局的原始结果：局号、赢家、对子/例牌标记、可选的点数。 |
| `Shoe` | 一整靴：id、桌号、开始时间、`List<RawResult>`。 |
| `BigRoadCell` / `BigRoadData` | 大路的一个单元格 / 完整的大路数据（单元格、各列高度、开头的和局）。 |
| `DerivedColor` / `DerivedRoadData` | 衍生路的红/蓝记录，并带有指回大路源单元格的引用。 |
| `LayoutConfig` | 传给每个插件 `layout()` 的参数：格子大小、行数、主题。 |
| `DrawCommand` | 密封类，有 6 种：`CircleCommand`/`LineCommand`/`SlashCommand`/`DotCommand`/`BadgeCommand`/`RectCommand`。是与具体渲染器无关的绘制指令。 |
| `LayoutCell` | 带位置、可做动画的网格单元，有稳定的 `key` 用来做 diff。 |
| `RoadLayout` | `layout()` 的输出：单元格、可选的装饰、内容尺寸、网格规格。 |
| `GridSpec` / `GridStyle` | 背景网格的规格（线条网格或圆角方块）。 |
| `RoadContext` | 传给 `derive`/`layout`/`predict` 的上下文：结果、spec、`stream()`、`get<T>()`。 |
| `toGenericResult` / `fromGenericResult` | 在 `RawResult` 和与游戏无关的 `GenericResult` 之间转换。 |
| `RoadKind` | 插件类别：`grid` / `overlay` / `summary`。 |
| `RoadPlugin<TData>` | 每种路单都要实现的接口。 |
| `PredictionForRoad` | “问路”的结果：下一手如果开庄或开闲，这条路会变成什么颜色。 |
| `StatsData` / `CurrentStreak` | 统计面板用的数据。 |
| `ViewportPhase` / `ViewportState` / `ViewportBounds` / `ViewportConfig` | 视口状态机相关类型。 |
| `ConfigField` / `ConfigFieldType` / `ConfigFieldOption` | 插件配置项的自描述，可据此生成设置界面。 |

### 主题（`core/theme.dart`）

- 结构类型，都有 `copyWith`：`Theme`、`Palette`、`CanvasTheme`、`GridTheme`、`CellTheme`、`LabelsTheme`、`FontsTheme`、`RoadTheme`。
- 内置实例：`defaultTheme`、`darkTheme`、`lightTheme`。
- `resolveTheme({base, palette, canvas, grid, cell, labels, fonts, roads})` 在基础主题上叠加覆盖。每项覆盖是一个回调，把旧字段映射成新字段。

### 引擎（`core/engine.dart`）

`createEngine(enabledIds, {spec})` 会解析插件依赖（包括间接依赖），做拓扑排序，返回一个 `Engine`。`Engine.compute(results, cfg)` 返回 `ComputeOutput`（`layouts`、`data`、`predictions`、`errors`）。

### 视口（`core/viewport.dart`）

纯状态机函数：`createViewport()`、`dragBy()`、`endDrag()`、`stepViewport()`、`computeBounds()`、`zoomAt()`、`startAutoScroll()`，还有 `defaultViewportConfig`。

### 动画（`core/animation.dart`）

- `diffLayout(prev, next)` 返回 `List<Transition>`（`EnterTransition`/`MoveTransition`/`ExitTransition`）。
- `sampleEnter`/`sampleMove`/`sampleExit` 取某个进度下插值后的指令。
- `registerEnterAnimation`/`registerMoveAnimation`/`registerExitAnimation` 注册自定义的命名动画。
- `Easing` 有 linear、easeOutCubic、easeOutBack 和 spring。
- `applyWindow` 把布局裁剪到滚动的列窗口里。
- `translateCommands`/`translateCommand` 用来手动平移指令。

### 存储（`core/store.dart`）

`createStore({onOutOfSync})` 返回 `RoadmapStore`，有 `setResults`/`append`/`patch`/`getResults`/`subscribe`。每个 `ChangeEvent` 用 `UpdateKind`（`full`/`append`/`patch`）标记类型。

### 管线（`core/pipeline.dart`）

`createPipeline()` / `globalPipeline` 是一条有序、有名字的 `CommandTransform` 链，位于计算输出和渲染器之间。内置：`watermarkTransform(text, opts)`、`grayscaleTransform()`。

### 预测（`core/predict.dart`）

`predictNextOutcome(results)` 给出下一局的统计倾向。它和上面各路单自带的“问路”是两套机制。

### 网格布局（`core/grid_layout.dart`）

`placeOnGrid`、`placeSequential`、`cellToPixel`、`gridCommands`、`contentSize`、`roundTo`。

### 游戏规则（`core/game_spec.dart`、`stream.dart`、`game_specs/*`）

- 类型：`GameSpec`、`GenericResult`、`OutcomeDef`、`MarkerDef`、`StreamSelector`（密封类：`OutcomeSelector`/`RangeSelector`/`MarkSelector`）、`StreamDef`。
- 函数：`validateGameSpecJson`、`resolveToken`、`colorForToken`、`labelForToken`、`getStreamDef`。
- 内置 spec：`baccaratSpec`、`dragonTigerSpec`、`sicboSpec`。

### 路单插件（`core/roads/*`）

`roadRegistry`（`Map<String, RoadPlugin>`）里有 12 个内置插件。`createEngine` 会按 `dependsOn` 自动带上依赖。

| id | 类别 | 依赖 | 说明 |
| --- | --- | --- | --- |
| `beadPlate` | grid | 无 | 珠盘路，不合并。 |
| `bigRoad` | grid | 无 | 大多数其他路单的基础。`buildBigRoad(results)` 也单独导出。 |
| `bigEyeBoy` | grid | `bigRoad` | 偏移 k=1。 |
| `smallRoad` | grid | `bigRoad` | 偏移 k=2。 |
| `cockroachRoad` | grid | `bigRoad` | 偏移 k=3。 |
| `pairRoad` | grid | 无 | |
| `naturalRoad` | grid | 无 | |
| `derivedTrio` | grid | 3 个衍生路 | 把它们放在同一张网格里。 |
| `compactRoadSheet` | grid | 大路 + 3 个衍生路 | 在三路上方再加大路，共 12 个宏行。 |
| `bigRoadMergedDots` | overlay | 大路 + 3 个衍生路 | 把衍生路的颜色以小圆点/斜线画在大路的单元格上。 |
| `streakHighlight` | overlay | `bigRoad` | 在背景上高亮长龙、单跳和双跳。 |
| `statsPanel` | summary | `bigRoad` | 产出 `StatsData`。 |

`deriveRoad(bigRoad, k)` 是衍生路用的算法，`mergeBands(bands)` 是组合网格插件用的算法。

### 渲染器（`render/*`）

`RoadPainter`（`CustomPainter`）是唯一内置的 Flutter 渲染器。`renderToSvg(layout, theme, {width, height, grid})` 是导出 SVG 的纯函数，不引入 `dart:ui`。

**绘制钩子。** `RoadPainter`、`RoadFramePainter` 和 `RoadPanel` 接受四个可选回调，画在内置图形的下面或上面，不会替换内置绘制：

- `onBeforePaintGridCell`/`onAfterPaintGridCell`（`GridCellPaintCallback`）每个背景方块触发一次，只在 `GridStyle.tile` 下有效。收到 `GridCellPaintInfo`：当前的 `Canvas`、方块的 `rect` 和 `color`，以及循环顺序下的 `row`/`col`（做棋盘格填色很方便）。
- `onBeforePaintCommand`/`onAfterPaintCommand`（`CommandPaintCallback`）每条 `DrawCommand` 触发一次（圆、线、斜线、点、徽标、矩形，包括 overlay 的指令）。收到 `CommandPaintInfo`：当前的 `Canvas` 和原样的 `command`。按它的运行时类型分支，就能读到坐标、大小和颜色。

`before` 画在内置图形下面，`after` 画在上面。z 序能控制的就这些。

四个都是 `null`（默认）时没有任何影响，网格层和内容层仍走 Picture 缓存的快速路径。只要设了其中任何一个，那一层就改成每帧直接绘制，因为 Picture 回放没法调用 Dart 回调。拖动和惯性滑动的帧会因此变慢。

### 面板（`panel/*`）

- `RoadPanel` 是组件本体。它和 `RoadPainter` 一样接受这四个绘制钩子，并原样传给内部的 painter。
- `FollowTail`（`none`/`hard`/`ease`）控制是否跟随尾部。`RoadUpdateKind`（`setResults`/`append`/`patch`）控制是否播放插入动画。
- `createReplayer(fullResults, store, {opts})` 返回 `Replayer`，有 `play`/`pause`/`seek`/`stop`。

### 交互小功能（`panel/ux/*`）

`createPulseEffect`、`createCelebrationEffect`、`EmptyStateOverlay` 组件、`createHapticsEffect`、`createDoubleTapToTail`、`prefersReducedMotion(context)`、`createSkeletonRenderer`/`defaultSkeletonAdapter`。它们比 TS 版刻意做得更简单，原因见 [ARCHITECTURE.md](ARCHITECTURE.md)。

## 开发

```bash
flutter pub get
flutter analyze
flutter test
```

## 许可证

MIT
