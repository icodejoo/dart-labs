## 0.0.1

初始版本：从 casino monorepo 的 `apps/baccarat-roadmap`（TypeScript，`main` 分支）完整移植到 Flutter。

- `core/`：类型系统、主题、引擎（插件依赖拓扑排序 + 错误边界）、视口拖拽/惯性/回弹/缩放状态机、动画（`diffLayout` + enter/move/exit 采样）、数据 Store、事件发射器、指令管道、问路、物理网格布局、可插拔游戏规则（`GameSpec`/`StreamSelector`）、内置百家乐/龙虎斗/骰宝三套规格、12 个内置路插件（珠盘路/大路/大眼仔/小路/曱甴路/对子路/例牌路/三合一/紧凑路纸/大路合并显示/长龙高亮/统计面板）。
- `render/`：`RoadPainter`（`CustomPainter`，全量重绘，支持 line/tile 两种背景网格风格）、`renderToSvg`（纯 Dart 函数，零 Flutter 依赖，服务端出图用）。
- `panel/`：`RoadPanel`（`CustomPaint` + 手势 + 视口 + 逐格插入/移动/退出动画）、`Replayer`（`Timer` 驱动回放）、UX 增强包（呼吸高亮/长龙庆祝/空态/触觉反馈/双击回尾/reduced-motion/骨架屏）。
- `example/`：Flutter demo app，功能对齐 TS 版 `example/main.ts`（切换游戏类型、勾选路、加一局、回放、问路、UX 开关）。
- 35+ 项核心算法单测（大路归并、衍生路推导、引擎依赖解析、视口状态机、动画 diff、网格布局），以及 `RoadPanel`/demo app 的挂载冒烟测试。
