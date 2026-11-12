# 自定义能力盘点：转盘

> 只读审计原文（2026-11，Codex 逐条核对代码，含 文件:行号）。代码此后有变动，行号仅供定位；已落地项见 CHANGELOG 与 docs/E1_E2_DEVICE_REPORT.md。

已经开放得好的点：

- 加减速缓动、时长、速度、时间基准、单帧推进上限和停止求解器均可配置；未发现 wheel 内另行写死 `Curves`。布局中的 `sin/cos/tan` 用于几何计算。
- `WheelController` 支持注入 `PrizePicker`、`Random`，支持指定奖项、额外圈数和异步选奖。
- 支持奖品局部 `painter`、动态/静态 layer、完整 renderer 替换及 Widget 叠加层。
- 已暴露扇区路径、锚点、旋转、图片摆放规则、文字行布局，以及当前旋转角、目标项、指针所在项和帧通知器。
- 已提供阶段、经过扇区、结束、图片失败、就绪回调；缓存模式、采样质量、隐藏暂停及文字缩放可配置。
- 导出面交叉核实通过：`LuckyRenderer`、`LuckySurfaceData`、图片布局、文字行、停止求解上下文等可从 `extend.dart` 导入，不能因为 `wheel.dart` 未直接导出就判为缺失。

以下路径相对 `lib/src/wheel/`。P0 表示沿用内置转盘时，缺少关键局部自定义能力；整体替换 renderer 或重写玩法仍可能绕过。建议中的新增参数均应默认保持现有行为。

| 编号 | 文件:行号 | 写死了什么（具体值/表达式） | 为什么使用者改不了 | 建议的开放方式 | 优先级 | 改动量 |
|---|---|---|---|---|---|---|
| 01 | `render/wheel_painter.dart:120、205、237`；`layout/wheel_layout.dart:268` | 圆环/按钮固定画圆；指针固定三角形 `(-r,0)→(r,0)→(0,-2r)`，与按钮共用背景；奖品 painter 固定插在图片后、文字前 | 没有圆环、按钮、指针及奖品背景的独立替换回调；layer 只能叠画，无法局部委托默认绘制 | `WheelPartPainter(Canvas, WheelPartContext, VoidCallback paintDefault)`；分别提供 `blockPainter/buttonPainter/pointerPainter/prizeBackgroundPainter`，默认 null | P0 | M |
| 02 | `render/wheel_painter.dart:136、165、220、269`；`model/wheel_parts.dart:194` | 奖品整段默认 `isStatic=true`；局部 painter 仅收到几何参数；样式从静态配置读取 | painter 捕获外部动画值也不会逐帧执行；没有按 index、指针态、目标态、阶段解析背景/文字/图片的入口。动态 layer 可绕过，但须重新组织部件绘制 | `WheelPrizePainter.isStatic=true`、`Listenable? repaint`；上下文增加 frame/layout；增加 `WheelPrizeVisual Function(WheelVisualContext)? prizeStyleResolver`，默认 null | P0 | L |
| 03 | `motion/wheel_motion.dart:38、107、110、113、116、140` | frame 只有 phase、`rotateDeg/targetIndex/pointerIndex`；阶段时间、减速起点及总位移均私有 | renderer/layer 无法准确同步减速进度、剩余圈数、速度及关联动效；帧监听不补足这些状态 | frame 增加只读 `elapsedMs/phaseElapsedMs/phaseProgress/angularVelocity/stopPlan`；沿现有复用帧更新 | P0 | M |
| 04 | `layout/wheel_layout.dart:187、213、229、241`；`wheel_game.dart:20、118`；`widgets/lucky_wheel.dart:120` | 外半径 `min(width,height)/2`；内容高度 `prizeRadius-maxBtnRadius`；锚点固定外缘，内容径向朝内；Widget 盒子固定弦长×内容高度 | alignment、padding 可调，但不能替换布局计算或局部内容变换；`WheelGame` 为 final，`LuckyWheel` 固定使用它。renderer 替换不会替换布局 | `WheelLayoutBuilder(config,input,computeDefault)`；`LuckyItemGeometry? itemGeometry`；局部 `contentTransformBuilder`，均默认使用现有实现；角度表须与 motion 共用 | P0 | L |
| 05 | `control/wheel_controller.dart:21`；`motion/wheel_motion.dart:219、243、296、303、308` | 控制器固定创建 `WheelMotion`；停止等待加速条件满足；减速后拒绝停止/取消；加速阶段依赖 `currSpeed == speed` 切换 | easing/solver 只能替换局部公式，无法实现立即减速、减速中改目标、拖动接管等流程；自定义 easing 还须满足精确端点约定 | `WheelController({WheelMotionFactory? motionFactory})`，配套公开含 `requestStop` 的 `WheelMotionStrategy`；默认工厂保留当前状态机 | P0 | L |
| 06 | `layout/wheel_layout.dart:221、268`；`layout/wheel_angles.dart:68`；`motion/wheel_motion.dart:359` | 扇区基准为正上方 `-90°`；指针朝上；反算/停止目标均隐含上方指针 | `offsetDegree` 改的是盘面偏移，不能独立设置指针所在角度并同步命中、经过和停止计算 | `WheelOptions.pointerDegree=-90`；统一传入布局、反算、停止候选及默认指针路径 | P1 | M |
| 07 | `layout/wheel_layout.dart:255、261、264、282、336` | 奖品行宽固定 `(R-fontY)*tan(sweep/2)*2-gutter`；奖品丢弃空行；按钮强制 `wrap:false`；按钮文字百分比横偏移基于最后一个扇区弦长 | `lengthLimit/wordWrap` 不能覆盖全部布局策略；不等分扇区还会影响按钮文字偏移。完整 `TextStyle`、对齐和排版回调也未透传 | `WheelTextLayoutPolicy?`，提供 `maxWidthOf/dropEmptyLines/wrap/leftBase/textStyleResolver`；null 使用原公式 | P1 | M |
| 08 | `layout/wheel_layout.dart:203、247、280、302` | 奖品图片宽百分比基于弧长，横偏移基于弦长；按钮宽高基于直径，偏移基于半径；统一 `box:Rect.zero`、横向居中 | 可改静态 top/left/width/height，但不能选择百分比基准、锚点或按布局动态摆放 | `LuckyImagePlacement Function(WheelImageLayoutContext, LuckyImagePlacement)? imagePlacementBuilder`，默认 null | P1 | M |
| 09 | `render/wheel_painter.dart:119、135、139、142、198、215` | 仅四个 layer 插入点；自动随盘旋转只认可 `belowItems/aboveItems`；奖品图片、文字和 painter 不裁到扇区 | 无法直接插入某个按钮/圆环之间；background/foreground 的旋转标记被忽略；默认内容不能选择扇区裁剪 | 增加带部件 index 的 layer slot、`WheelLayerTransform` 和 `clipPrizeContent=false`；默认顺序、旋转及不裁剪行为保持 | P1 | M |
| 10 | `wheel_game.dart:37`；`widgets/lucky_wheel.dart:31、120` | 命中仅检查圆形按钮，固定选择包含点的最小半径按钮；不返回奖品命中；wheel 没有拖动策略 | 自定义按钮形状不能同步命中；无奖品点击、按钮按下/取消状态及拖动入口。外层手势可补部分能力，但须重算命中并处理竞争 | `WheelHitTest? hitTest`、`onPrizeTap`、`onButtonPointer(index,event)`、`WheelGesturePolicy?`，默认保留当前策略 | P1 | M |
| 11 | `widgets/lucky_wheel.dart:164` | overlay 固定放最上层并包 `IgnorePointer`；`Stack` 未开放裁剪设置 | overlay 无法承载可点击控件或调整层级、溢出策略；可以自行包装默认 renderer 绕过，但便捷入口不支持 | `overlayIgnorePointer=true`、`overlayPosition=foreground`、`overlayClipBehavior=Clip.hardEdge` | P1 | S |
| 12 | `model/wheel_parts.dart:138`；`render/wheel_painter.dart:55`；`widgets/lucky_wheel.dart:109、118` | `WheelPrize.semanticsLabel` 未被默认绘制消费；`WheelPainter` 未实现语义节点；宿主固定根节点语义 | 默认 Canvas 中逐奖品标签不起作用；根 label/value 可改，但无法局部提供奖品/按钮节点、动作及播报策略 | `WheelSemanticsBuilder? semanticsBuilder`、`liveRegion=true`；默认分支保留现状，显式启用时构建部件节点 | P1 | M |
| 13 | `motion/wheel_motion.dart:333`；`widgets/lucky_wheel.dart:130` | 仅比较前后 `pointerIndex`，每 tick 最多报告一个帧末下标 | 一帧跨多个扇区会漏报；转过整圈回同项甚至没有事件，无法可靠驱动逐格音效/触觉反馈 | 新增 `onSectorCrossed(WheelCrossing)`，按累计角度枚举边界，携带方向/圈次；旧 `onSectorPassed` 保持原语义 | P1 | M |
| 14 | `motion/wheel_motion.dart:347、351、353、375` | 停点固定 `(r*sweep-sweep/2)*stopRange`，边界余量 `min(1e-9,sweep/2)`；与选奖共用随机源；固定请求 `nearest` | Random 和 solver 可替换，但没有独立、带目标扇区上下文的停点采样入口；修改分布或精确落点要绕到随机源/solver | `WheelStopOffsetSampler? stopOffsetSampler`、独立 `Random? stopRandom`、`stopBoundaryEpsilon=1e-9`、`stopSelection=nearest`；默认沿原路径 | P1 | M |
| 15 | `motion/wheel_motion.dart:283、304、306、366` | 待机、加速、匀速速度均先 `%360`；求解未传 direction，使用默认 `+1` | 配置速度 `360` 会成为零位移；负速度与默认正向停止求解没有统一方向约定。自定义 solver 可绕过部分限制 | `normalizeSpeed=true`、`WheelDirection direction=clockwise`；方向贯穿速度、候选及 solver，默认保留旧路径 | P1 | M |
| 16 | `wheel_game.dart:84`；`motion/wheel_motion.dart:93、156、171、308` | 结构字段固定为数量/角宽权重/offset；减速参数整组冻结；目标缩减后按 `%count` 重映射 | 使用者不能选择立即应用、延后、作废或按稳定 ID 保留目标；也不能选择减速期间哪些参数实时生效 | `WheelConfigUpdatePolicy`、`WheelTargetRemapper(oldIndex,oldConfig,newConfig)`；默认采用现有延后、快照和取余策略 | P1 | M |
| 17 | `render/wheel_painter.dart:89、196` | layer context 只填入 size/layout/frame/DPR，没有解析图片、文字方向及缩放 | renderer 能拿到这些数据，局部 layer 拿不到；要复用宿主已解析图片或保证文字与默认绘制一致，需额外包装 renderer | 扩展为 `WheelLayerContext`，提供只读 config/images/textScale/textDirection；默认不改变绘制 | P1 | M |
| 18 | `wheel.dart:7、19、20`；`render/wheel_painter.dart:55`；`layout/wheel_layout.dart:184` | `WheelPainter`、`computeWheelLayout` 未导出；默认部件绘制方法又是私有的 | 关键上下文类型已由 `extend.dart` 提供，**不存在类型层面的硬阻断**；但复用默认画笔、离屏录制和局部委托不便。布局已有 `WheelGame.computeLayout` 替代入口 | 在扩展入口导出默认画笔/布局助手；优先配合 01 提供公开 `paintDefault` 委托，避免只导出一个不可拆分的画笔 | P2 | S |

建议的实施批次：第一批一起做 **01–03、17–18**，先补齐部件上下文、默认绘制委托和动态失效机制；第二批做 **04、06–12**，统一布局、指针、命中和语义，避免视觉与交互几何分离；第三批做 **05、13–16**，开放运动策略及停止/配置更新策略，依赖第一批的帧状态。所有新增能力默认关闭或使用原实现，保留现有求值顺序、绘制顺序和缓存路径，默认画面及 golden 应当全部不变；经过事件应新增回调，避免直接改变旧回调语义。本次仅只读核查，未修改文件、执行 git 或运行测试。
