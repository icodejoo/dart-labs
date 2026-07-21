## Unreleased

- 移除 `README.zh-CN.md`（不再维护中文版 README）
- `pubspec.yaml` 去掉 `homepage`/`repository`/`issue_tracker` 的 GitHub 链接
- 代码注释统一改为纯英文（原双语注释中的中文部分已删除/合并进英文）
- 新增 `CLAUDE.md` 记录本包的项目规则（README 单一英文版、注释禁止中文）

## 0.1.0

包名从 `roadmap` 改为 `roadsman`（pub.dev 上 `roadmap` 已被占用）；其余无变化。

绘制回调（自定义底部背景 + 任意绘制指令的前/后挂钩）：

- 新增 `lib/src/render/paint_hooks.dart`：`GridCellPaintCallback`/`GridCellPaintInfo`（网格瓷砖，仅 `GridStyle.tile`，携带 canvas/rect/color/row/col）、`CommandPaintCallback`/`CommandPaintInfo`（每条 `DrawCommand`，携带 canvas + 原始指令对象）
- `RoadPainter`/`RoadFramePainter`/`RoadPanel` 均新增 `onBeforePaintGridCell`/`onAfterPaintGridCell`/`onBeforePaintCommand`/`onAfterPaintCommand` 四个可选回调——纯增量挂钩，`before` 画在内置内容下面、`after` 画在上面，内置绘制本身永远照常执行
- 未设置回调时零开销，网格层/内容层原有的 Picture 缓存快速路径不受影响；设置后对应层当帧退回逐条直绘（缓存重放没法触发 Dart 回调），正确性优先于纯视口帧的部分性能
- 新增 `test/paint_hooks_test.dart`：触发顺序、携带信息正确性、`GridStyle.line` 不触发瓷砖回调、两处缓存旁路逻辑生效、不设回调时行为不变，共 6 个用例
- README/README.zh-CN 补了对应的 API 说明
- 验收：`dart analyze` 零问题；`flutter test` 46 个测试全绿

性能优化第二轮：动画帧底图分离 + repaint Listenable 路由（附对抗性复核）：

- `panel/road_panel.dart` + `render/road_painter.dart`：插入动画期间把"不在动的格子 + decorations"冻结为动画底图（独立 `CommandLayerCache`，整个 280ms 只录一次 Picture），正在 enter/move/exit 的格子每帧采样进叠加层——动画帧直绘量从 O(全部指令) 降到 O(动的格子)，每帧全部 badge 的 TextPainter 重排版（满屏约 3-8ms/帧）随之消失。过渡索引（enters/moves/exits）也改为 didUpdateWidget 算一次、全程复用
- `render/road_painter.dart`：新增 `RoadFrameState`（ChangeNotifier 帧状态）与 `RoadFramePainter`（以 frame 为 `repaint` Listenable）；面板内部不再有任何 setState——Ticker/手势帧只写帧状态 + `markFrame()`，经 Listenable 直达 `markNeedsPaint`，动画/拖拽帧零 widget 重建、零 element diff。原 `RoadPainter` 公开 API 不变，两个 painter 共享同一套绘制实现
- 行为说明：动画中的格子在过渡期内绘制在静止格子之上（原先按 cells 顺序插绘），≤280ms 的瞬时表现，移动中的格子"浮在上面"反而更自然；数据未变的父级重建不再触发 followTail（不会把正在看历史的用户拽回尾部）
- `panel/road_panel.dart`：几何守卫补上 contentWidth/contentHeight（复核指出的潜在耦合：理论上内容尺寸可在 cells 引用不变时变化）
- 复核结论：0 个实锤问题；状态变更全路径可达 painter、painter 换代时 Listenable 干净换绑、无 notify-after-dispose、共享 Paint 无重入，均验证通过
- 验收：`dart analyze` 零问题；`flutter test` 40 个测试全绿


性能优化专项（3 个性能专家评审 + 1 个对抗性终审）：

- `panel/road_panel.dart`：`CustomPaint` 外包一层 `RepaintBoundary`——此前一个面板动画时 markNeedsPaint 传播到共同祖先，同屏 ~8 个面板每帧全部重画，现在只画动的那一个
- `panel/road_panel.dart`：修复真 bug——dragging 阶段被当作活跃工作，拖拽途中数据到达会让 Ticker 以 60fps 空转（setState 无视觉变化）直到手指抬起；现在 dragging 由指针事件驱动，Ticker 的步进与唤醒都排除该阶段
- `panel/road_panel.dart`：`didUpdateWidget` 加数据未变守卫（cells/decorations 按引用比较）——父级因无关 UI 状态重建时不再重跑 diff、不失效指令/Picture 缓存；面板几何变化时把静止视口重新夹回新边界（终审发现的边界残留问题）
- `panel/road_panel.dart` + `render/road_painter.dart`：呼吸光圈改走 `overlayCommands` 叠加层——底层内容在光圈 2s 动画期间保持同一 List 实例，Picture 缓存持续命中（此前一次"加一局"= 每面板 2 秒 × 60fps 全量直绘，含每帧全部 BadgeCommand 的 TextPainter 布局）
- `render/road_painter.dart`：新增 `GridLayerCache`——背景网格按 (grid, scale, 尺寸) 录制一次原点对齐的 Picture，每帧只按相位平移重放；tile 模式拖拽帧原来每帧几百次 drawRRect，现在为零
- `render/road_painter.dart`：直绘路径复用两个静态 Paint（fill/stroke，每次使用重置全部字段），消除动画帧每条指令 1-2 次 Paint 分配
- `core/engine.dart`：`compute` 按 (results, cfg) 引用备忘上次输出——UI 侧无关重算直接命中，布局对象保持同一实例，下游 identity 缓存不被击穿；配合 `core/store.dart` 的 `getResults()` 稳定快照（数据未变返回同一实例，三处变更入口失效）
- `core/predict.dart`：基线大路从构建 3 次改为 1 次（三条衍生路共用），整函数省 ~40%
- `core/grid_layout.dart`：`placeOnGrid` 占用集从 `'$col,$row'` 字符串键改为整数键（col*4096+row）——布局热路径上最大的分配来源清零
- `core/stream.dart`：新增 `outcomeIndexOf`（Expando 按 spec 实例缓存的 code→OutcomeDef 索引），`colorForToken`/`labelForToken`/珠盘路的 outcomes 线性扫描全部变 O(1)（轮盘 37 个 outcome 时尤其明显）
- `core/stream.dart`：`labelForToken` 补百家乐向后兼容桥——继续尊重 `theme.labels.banker/player/tie` 定制（终审发现珠盘路 spec 化后丢了这层）
- `core/game_spec.dart`：`validateGameSpecJson` 放开 paletteKey 白名单——自定义键运行时经 `theme.palette.outcomes` 解析，校验只要求非空字符串（终审发现校验与新特性矛盾）
- `example/main.dart`：`LayoutConfig` 缓存为字段；合并 decorations 按 (layout, prediction, predictMode) 引用备忘；`predictNextOutcome` 按 results 引用备忘（终审发现每次无关重算都重跑并击穿 decorations 备忘）
- 终审结论：0 个实锤问题，4 个中等问题全部修复；Ticker 生命周期全路径枚举、网格 Picture 像素等价、Paint 复用字段泄漏、Expando 键合法性、备忘录失效完备性均验证通过
- 验收：`dart analyze` 零问题；`flutter test` 40 个测试全绿


轮盘露珠图 + 珠盘路去硬编码 + 渲染层 Picture 缓存：

- `core/roads/bead_plate.dart`：珠盘路插件接入 spec 执行层，移除全部百家乐硬编码——圆色走 `colorForToken`（paletteKey → 主题色，可被 `theme.palette.outcomes[code]` 逐 code 覆盖）、文字走 `labelForToken`、点数模式改由 `OutcomeDef.beadTextField` 声明取哪个 extras 字段、角标泛化为遍历 `spec.markers` 的 dot 标记（按 position 四角定位）。百家乐行为不变，骰宝/龙虎珠盘路从"显示错的"变成正确
- `core/stream.dart`：抽出 `colorForPaletteKey`——内置五键之外的自定义 paletteKey 先查 `theme.palette.outcomes[key]` 再回落 blue，规格作者可发明新色键而无需改库代码
- 新增 `core/game_specs/roulette.dart`：欧式轮盘规格（0-36 共 37 个 outcome，红/黑/绿走 paletteKey），露珠图零渲染代码开箱即用；大小/单双衍生流已声明（0 号 `skipOutcomes` 跳过，同骰宝围骰机制），但依赖 `extras.number`/`marks.odd`，待数据层支持 GenericResult 后接通
- `render/road_painter.dart`：新增 `CommandLayerCache`（`ui.Picture` 缓存）——同一份指令列表只录制一次（含 TextPainter 布局、Paint 构造），拖拽/惯性/自动滚动等纯视口帧只 `drawPicture` 重放。选 Picture 而非栅格化 `ui.Image`：矢量重放缩放不糊、无 DPR 问题、录制同步完成
- `panel/road_panel.dart`：面板持有 `CommandLayerCache` 跨 painter 实例复用（painter 每次 build 重建），仅对静止帧的缓存指令列表启用——动画帧每帧指令不同，录制是纯开销，仍走直绘+可视裁剪
- `example/main.dart`：demo 游戏类型加入轮盘（衍生路插件目前只认百家乐语义，轮盘只开放珠盘露珠）
- 新增 `test/bead_plate_test.dart`：百家乐颜色/文字/角标与硬编码时代一致、轮盘号码取色、主题逐号覆盖、自定义 paletteKey 回落，4 个用例
- 验收：`dart analyze` 零问题；`flutter test` 40 个测试全绿


代码质量清理（/simplify 评审：复用/简化/效率/实现深度四个视角）：

- `panel/road_panel.dart`：Ticker 不再常驻——静止时（视口 idle、无格子动画、无呼吸光圈）自动停止，有新工作时按需重启，多面板场景不再每 vsync 空转；动画/光圈起点改用哨兵值在首帧对齐，兼容 Ticker 重启后 elapsed 清零。
- `panel/road_panel.dart`：静止帧的绘制指令列表加缓存（数据不变时复用同一 List 实例），配合兜底 `GridSpec` 缓存，恢复 `RoadPainter.shouldRepaint` 的精确性——纯视口帧不再逐帧重展开全部指令。
- `panel/road_panel.dart`：删除手写的 `_VelocitySample` 5 采样测速环（`DateTime.now()` 壁钟抖动），改用手势系统自带的最小二乘估计 `ScaleEndDetails.velocity`。
- `panel/road_panel.dart`：呼吸光圈时长/颜色改为引用 `ux/pulse.dart` 的 `PulseOptions` 默认值，消除面板内重复的 2000ms/金色字面量两处真源。
- `core/engine.dart`：删除 `createEngine` 里名为"收集传递依赖"却从不入队依赖的死循环（真正的传递加载在第二个循环），加载循环直接以 enabledIds 起步，错误消息不变。
- `core/theme.dart`：`darkTheme` 原来是把 `defaultTheme` 的相同值再 copyWith 一遍的空操作，改为直接共用同一实例。
- `core/types.dart`：删除无调用方的 `DerivedColor.label` getter（Dart 枚举自带等价的 `.name`）。
- `core/roads/big_eye_boy.dart`：循环体内恒真的 `data.entries.isNotEmpty ? i : 0` 简化为 `i`（对齐小路/曱甴路写法）。
- `example/main.dart`：`resolveTheme()` 从每次 `_recompute`/`build` 各调一次改为字段缓存一次；问路 ghost 点颜色不再硬编码 ARGB，改取 `theme.palette.red/blue`，换主题时与路子图配色保持一致。
- 验收：`dart analyze` 零问题；`flutter test` 36 个测试全绿。

## 0.0.1

初始版本：从 casino monorepo 的 `apps/baccarat-roadmap`（TypeScript，`main` 分支）完整移植到 Flutter。

- `core/`：类型系统、主题、引擎（插件依赖拓扑排序 + 错误边界）、视口拖拽/惯性/回弹/缩放状态机、动画（`diffLayout` + enter/move/exit 采样）、数据 Store、事件发射器、指令管道、问路、物理网格布局、可插拔游戏规则（`GameSpec`/`StreamSelector`）、内置百家乐/龙虎斗/骰宝三套规格、12 个内置路插件（珠盘路/大路/大眼仔/小路/曱甴路/对子路/例牌路/三合一/紧凑路纸/大路合并显示/长龙高亮/统计面板）。
- `render/`：`RoadPainter`（`CustomPainter`，全量重绘，支持 line/tile 两种背景网格风格）、`renderToSvg`（纯 Dart 函数，零 Flutter 依赖，服务端出图用）。
- `panel/`：`RoadPanel`（`CustomPaint` + 手势 + 视口 + 逐格插入/移动/退出动画）、`Replayer`（`Timer` 驱动回放）、UX 增强包（呼吸高亮/长龙庆祝/空态/触觉反馈/双击回尾/reduced-motion/骨架屏）。
- `example/`：Flutter demo app，功能对齐 TS 版 `example/main.ts`（切换游戏类型、勾选路、加一局、回放、问路、UX 开关）。
- 35+ 项核心算法单测（大路归并、衍生路推导、引擎依赖解析、视口状态机、动画 diff、网格布局），以及 `RoadPanel`/demo app 的挂载冒烟测试。
