# roadsman 架构文档

## 项目概述

**roadsman** 是百家乐/龙虎斗/骰宝路子图（露珠图）的 Flutter 实现，移植自 casino monorepo 的 `apps/baccarat-roadmap`（TypeScript，`main` 分支）。核心设计沿用 TS 版本的三层架构：`core`（纯 Dart 算法层，零 Flutter 依赖）→ `render`（消费算法层产出的绘制指令）→ `panel`（Flutter widget 外壳：手势、视口、动画、回放、UX 增强）。

## 核心架构

```
数据源（RawResult[] / Shoe）
    ↓
[core 层 — 纯 Dart，零 Flutter 依赖]
    ├─ GameSpec（可插拔游戏规则：百家乐/龙虎斗/骰宝/自定义）
    ├─ Engine（插件依赖拓扑排序 + 错误边界）
    ├─ RoadPlugin 注册表（roadRegistry：12 个内置插件）
    │    derive() → BigRoadData / DerivedRoadData / StatsData
    │    layout()  → RoadLayout { cells: LayoutCell[], decorations, contentWidth/Height }
    │    predict() → PredictionForRoad（问路，仅 3 条衍生路）
    ├─ ViewportState 状态机（拖拽阻尼/惯性/回弹/缩放，纯函数）
    ├─ diffLayout + sampleEnter/Move/Exit（逐格动画采样）
    └─ RoadmapStore（setResults/append/patch）+ Pipeline（横切指令变换）
    ↓
[render 层 — 消费 DrawCommand]
    ├─ RoadPainter（CustomPainter，Flutter 原生 Canvas，全量重绘）
    └─ renderToSvg（纯函数，可在无 Flutter 的 Dart 环境跑，服务端出图用）
    ↓
[panel 层 — Flutter widget 外壳]
    ├─ RoadPanel（StatefulWidget：CustomPaint + 手势 + 视口 + diff 动画）
    ├─ Replayer（Timer 驱动逐局回放）
    └─ ux/*（呼吸高亮/长龙庆祝/空态/触觉反馈/双击回尾/reduced-motion/骨架屏）
```

## 与 TS 版本的关键差异

roadsman 不是逐行翻译，`core/` 之外的两层按 Flutter 的原生能力做了针对性简化：

1. **渲染模型更简单**：TS 版本的渲染层经历过 Canvas → Konva → Hilo.js 场景图的演进，`main` 分支落地的是 Canvas 版——每帧对 `DrawCommand[]` 全量重绘。Flutter 的 `CustomPainter` 天生就是这个模型，`shouldRepaint` 直接对应"要不要在下一帧重绘"，不需要额外维护场景图节点或 Tween 对象。
2. **不移植 `gesture-adapter.ts`**：TS 版本手写了 AlloyFinger（触屏）+ Pointer Events（鼠标）两套兼容层去统一拖拽/缩放手势。Flutter 的 `GestureDetector`（`onScaleStart/Update/End`）原生跨端支持单指拖拽和双指缩放，直接用即可——但 `viewport.dart` 里的阻尼/惯性/回弹**纯状态机算法**原样移植，因为那是这个项目的核心手感，不是平台相关代码。
3. **不移植 `frame-driver.ts`/Hilo 的 `StageDriver`**：两者都是为了把多个面板的动画帧合并到同一个驱动循环里，手写的批处理器。Flutter 的 `Ticker`/`SchedulerBinding` 本身就会把同一帧内所有 widget 的重绘请求合并，`RoadPanel` 直接用 `SingleTickerProviderStateMixin` 即可，不需要重新发明这层调度。
4. **组件注册表简化为 `switch`**：TS 版本 `renderer-shapes/` 用 `Component` 抽象类 + 注册表把 6 种指令类型分发给对应组件，是为了绕开 TS `switch` 对判别联合类型穷尽检查的某些历史限制。Dart 的 `sealed class` + `switch` 表达式本身就是穷尽检查的，`RoadPainter` 直接内联 `switch (cmd) { CircleCommand c => ..., ... }`，不需要额外的注册表间接层。
5. **UX 增强包简化为开关控制器**：`pulse`/`celebration` 在 TS demo 里是手写的独立动画帧循环，直接在指令层叠加临时指令；Flutter 版本把它们简化成"是否启用"的开关控制器，具体视觉效果交给消费方按需用 `AnimatedContainer`/`CustomPaint` 叠加层实现，避免在库内部重复一套动画系统。

## 数据流：从一局新结果到屏幕像素

```
用户操作 / Replayer
   │ store.append(rawResult)
   ▼
RoadmapStore（微任务合并：同一 tick 内多次 append 只触发一次下游计算）
   │ emit ChangeEvent { kind: append }
   ▼
Engine.compute(全量 results, cfg)  →  ComputeOutput { layouts, predictions, errors }
   │
   ▼
RoadPanel.didUpdateWidget：diffLayout(prevLayout, nextLayout) → Transition[]
   │
   ▼
Ticker 驱动逐帧：按 easing 进度对 enter/move/exit 采样出临时 DrawCommand[]
   │
   ▼
RoadPainter.paint()：viewport 变换 + 可视裁剪 + 逐条指令画到 Canvas
```

三个"不重算/不重绘"的性能关键点（与 TS 版本一致）：

1. **微任务合并**（`store.dart`）——同一 tick 内连续 append 多局，只触发一次 `engine.compute`。
2. **按 key diff**（`diffLayout` + `RoadPanel` 的 `didUpdateWidget`）——只有新增、移动、消失的格子才参与动画采样。
3. **视口裁剪**（`RoadPainter._isOutside`）——拖到很靠前的历史记录时，屏幕外的指令不参与本帧绘制。

## 目录结构

```
lib/
  roadsman.dart              # 库入口（barrel export）
  src/
    core/                    # 纯 Dart，零 Flutter 依赖
      types.dart               # 全部公共类型（RawResult/DrawCommand/LayoutCell/RoadPlugin 等）
      theme.dart                # 主题体系（颜色统一用 ARGB 整数，不是 CSS 字符串）
      engine.dart               # 插件注册表、拓扑排序、错误边界
      viewport.dart             # 拖拽阻尼/惯性/回弹/缩放的纯状态机
      animation.dart            # diffLayout、缓动函数、enter/move/exit 动画采样
      store.dart                # 数据 Store
      emitter.dart              # 类型安全事件发射器
      pipeline.dart             # 指令管道
      predict.dart              # 问路统计预测
      grid_layout.dart          # 物理网格布局
      game_spec.dart / stream.dart / game_specs/  # 可插拔游戏规则
      roads/                    # 12 个内置路插件 + band_merge/derived_road 公用逻辑
    render/
      road_painter.dart         # CustomPainter
      svg_renderer.dart          # 纯函数 SVG 渲染（零 Flutter 依赖）
    panel/
      road_panel.dart           # RoadPanel widget
      replayer.dart              # 回放
      ux/                        # UX 增强包
example/                    # Flutter demo app
test/                       # 核心算法单测 + RoadPanel 挂载冒烟测试
```
