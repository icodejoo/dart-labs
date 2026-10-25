# mova：宿主易用性九项增强 — 实现计划

> 2026-10-23 · 落地计划 · 起因：宿主 bingo 接入直播卡片
> （`E:\workspaces\bingo\lib\pages\pinoy\widgets\live\pinoy_live_panel.dart`）时为绕开 mova 不足写的样板，
> 以及真机排查中踩到的九个缺口。

**Goal:** 让宿主"挂一个直播/点播卡片"不再需要自己管引擎生命周期、自己猜"出没出画面"、自己写皮肤、
自己做超时兜底、自己处理前后台/Tab/路由遮挡，并且能在 widget 测试里不碰 media_kit。九项一次规划，
按依赖顺序拆成 16 个 Task。

**主干原则不变：** core/ui 分层纯净（`purity_test` 的 `_mediaKitExceptions` 恒为
`{'kernel/mpv_kernel.dart'}`）、**新功能默认关闭/不改变行为**、运行时可恢复错误走"策略对象 + 事件"
不 `throw`、**不引入任何新第三方依赖**、`MovaApi` 接口**零新增成员**（`FakeMovaApi`/`MovaSwapEngine`
不用跟着改）。

**Baseline（2026-10-23 本机实跑，作为本计划起点）：**

```
$ cd mova && flutter test -r compact
... 00:52 +1008: All tests passed!          （约 52s，exit 0）

$ flutter analyze lib test
No issues found! (ran in 11.1s)
```

即 **1008 项全绿、analyze 0 issues**，与 `CLAUDE.md` 记录的 1008 一致（未过时）。

**执行约束（2026-10-23 追加）：真机（STG AL00）暂不可用。** Task 1–15 的验收标准**只依赖**
`flutter analyze` / `flutter test` / 纯逻辑单测 / WidgetTester，任何 Task 都不得把真机结果当前置条件。
真机验证集中在 Task 16，标注【待定：等真机】，与其余 Task 解耦，不阻塞合入。

---

## 0. 现状核实（九项逐条，均已在源码中确认）

| # | 缺口 | 源码证据 | 落点 |
|---|---|---|---|
| 1 | 没有"已出画面"信号 | `MovaState.playing` 来自 media_kit `stream.playing`，而 media_kit `Player.open(play:true)` 在**发起加载之前**就 `playingController.add(true)`（`media_kit-1.2.6/.../real.dart:217-225`）；`MovaReady` 在 `await _kernel.open()` 返回后立刻发（`engine.dart:715`），离首帧还差网络+解封装+解码；`core/feed/engine_pool.dart:26-42` 注释承认"没有可重复的首帧事件"。原生 `PLAYBACK_RESTART` 已由 FFI 弱客户端订阅（`mpv_kernel.dart:226-269`），但**只在 `observeQoeSignals`（= 有 reporter）时才建泵**（`mpv_kernel.dart:119`、`wiring.dart:168`），且只喂给 QoE（`report/collector.dart:59`） | core：新纯逻辑 + `engine.dart` + `state.dart` + `events.dart`；kernel/wiring：拆开关 |
| 2 | 没有封面参数 | `MovaPlayer` 只有 `api/skin/autoLoadQualities/surface`（`ui/player.dart:38-44`）；`MovaSource` 只有 `uri/type/title`（`model/source.dart:19-48`） | ui：`player.dart` |
| 3 | fit 只能命令式 | `MovaState.fit` 默认 `contain`（`state.dart:204`）；`createMovaEngine`/`MovaOpts` 无 fit；`MovaFeedEnginePool` 创建后 `setFit`（`engine_pool.dart:386-387`）；宿主同样创建后 `setFit(MovaFit.cover)` | core：`engine.dart` 构造参；ui：`MovaPlayer(fit:)`；wiring |
| 4 | 无起播/卡顿超时 | 唯一与卡顿相关的自动动作是时移下的 `_maybeAutoBackToLive`（`engine.dart:1194-1204`，且只在已时移时生效）；`MovaAdConfig.loadTimeout` 只管广告。实测离线桌台缓冲十几秒无任何事件 | core：新 `recovery/` + `options/recovery_config.dart` + `engine.dart` |
| 5 | 只有单 `uri` | `MovaSource.uri` 单值（`model/source.dart:23`） | core：`model/source.dart` + `engine.dart` |
| 6 | 无自动暂停 | 全仓无 `AppLifecycleListener`/`RouteAware`/`TickerMode` 引用；CLAUDE.md 记录"Android 切后台被系统暂停、回前台需手动续播，需单独立项" | core：纯逻辑 gate；ui：守卫 widget |
| 7 | 无声明式组件 | 宿主 `_PinoyLivePanelState` 约 40 行管 `createMovaEngine`/`_openedUrl`/`didUpdateWidget`/`dispose` | ui：新 `view.dart` |
| 8 | 无极简皮肤 | 只有 `MovaDefaultSkin`/`MovaBilibiliSkin`/`MovaDouyinSkin`；宿主手写 `_PinoyLiveSkin`；`MovaBufferingComponent` 样式写死（`components/overlays.dart:38-49`，`MovaTheme` 无指示器尺寸/线宽） | ui：新皮肤；core：`theme.dart` 加可空字段 |
| 9 | 宿主测试报 `MediaKit.ensureInitialized must be called` | `MovaPlayer` 本身对非 `VideoController` 句柄已渲染占位（`player.dart:229-236`），报错来自 `createMovaEngine()` 默认构造 `MovaMpvKernel` → `Player()`（`wiring.dart:163`）；mova 的 `FakeKernel`/`FakeStatsKernel` 在 `test/support/`，未公开 | 新入口 `lib/testing.dart` + `lib/src/testing/`；wiring 加注入点 |

**宿主样板里藏着的一个真 bug（顺带记录，Task 2 修掉其根因）：** `_stage()` 用
`playing && !buffering && width > 0` 判出画面。但 `MovaEngine.open()` 不重置 `state.width/height`
（只重置 `duration`，`engine.dart:671-681`），换桌台时：`playing` 立刻为 true（见上）、`buffering`
在 open 后先发一个初始 `false`（CLAUDE.md TTFF 坑 #1）、`width` 还是上一条流的值——三个条件同时成立，
**封面会在新流出画面前提前淡出，露出黑屏或上一条的残帧**。

---

## 1. 架构决策

### D1 — 出画面信号：新增纯逻辑 `MovaFirstFrameGate`，引擎持有；不复用 `MovaTtffTracker`

**语义定义：**

- `MovaState.rendered`（`bool`，默认 `false`）：**当前源**已开始呈现媒体（视频源 = 首帧上屏；
  无视频的源/引擎 = 首段音频输出）。**只在 `open()`（宿主可见的换源）时重置为 `false`**。
- `MovaFirstFrame` 事件：`rendered` 每次 `false → true` 时发一次，带 `sinceOpen`（距 `open()` 的耗时）与
  `signal`（哪种信号落地的）。每次 `open()` 都会重新来一遍——这就是"可重复"。
- 引擎内部的**内核重载**（`switchQuality`、`_reopenLiveSource`、`_seekTimeshift`、Task 10 的重试、
  Task 11 的切备选地址）**不重置** `rendered`：它们不是换源，画面上通常还停着上一帧，把封面盖回去反而
  是一次闪烁。这些路径只会"重新武装一次尝试"（attempt），供 Task 10 的看门狗判断这次重载有没有起来；
  若 `rendered` 本来就是 `false`（起播还没成功就重载了），这次尝试落地时照常置 `true` 并发事件。

**判据（逐条对齐 QoE 已真机验证过的那套，见 `report/ttff.dart`、`report/collector.dart:516-551`）：**

| 信号 | 何时生效 | 说明 |
|---|---|---|
| 原生 `PLAYBACK_RESTART` | 任何时候到达都算（权威） | 订阅可用时 TTFF 真机 311–348ms，比兜底准约 200ms |
| `buffering` **true→false 下降沿** | 原生不可用时 | 只认下降沿：open 后 `buffering` 会先发一个初始 `false`（CLAUDE.md QoE bug #1） |
| 位置**连续两个递增且 > 0** 的样本 | 原生不可用时 | 单样本不可信：open 后内核会先回放上一条的残留位置 |
| 首个 `w>0 && h>0` 的尺寸 | 原生不可用、且本次以 `autoPlay:false` 打开时 | 暂停态打开时 `core-idle` 恒 true、位置不动，前两条兜底都不会触发；`video-params` 到达≈首帧已解码（feed 预热邻居就是这种打开方式） |
| 宽限超时 `grace` | 原生**可用**但兜底信号先到、`1500ms` 内仍无 RESTART | 防"原生订阅在工作却收不到 RESTART"（例如暂停态打开时 mpv 是否发 RESTART 尚未真机确认，见 Task 16 V2）把封面永远卡住 |

- **门控按落地时刻判断**（`nativeRestartAvailable` 在调用每个 `onXxx` 时传入），不是 open 时刻——
  泵是异步注册的（CLAUDE.md QoE 一节原话）。
- **内核 `open()` 在途期间丢弃一切观测**（RESTART/buffering/位置/尺寸）。依据：media_kit 1.2.6 的
  `Player.open()` 先 `stop`+`playlist-clear`（结束旧文件），**最后一步**才 `playlist-pos` 真正开始加载
  （`real.dart:173-228`），`loadlist ... append` 本身不起播；因此新文件的 RESTART/尺寸/位置必然晚于
  `_kernel.open()` 返回。而 open 在途期间收到的，只可能是旧文件残留（例如 open 前刚发起的 seek 引发的
  RESTART、旧位置回放）。这条比 QoE 更严，消掉了"陈旧 RESTART 让封面提前淡出"的竞态；万一真有新文件的
  信号被误丢，兜底信号 + 1.5s 宽限会兜住，最坏晚 1.5s。
- **为什么不复用 `MovaTtffTracker`：** 它 `autoPlay:false` 不武装、没有尺寸兜底与宽限、自带耗时口径，
  且是已真机验证的 QoE 代码——本计划不碰它一行。两套判据在"自动播放 + 原生可用"路径上结果一致；
  日后若要合并（让 QoE 直接消费 `MovaFirstFrame`）另立项，见 §5 排除项。

### D2 — 原生 RESTART 订阅：从 QoE 开关里拆出来，`createMovaEngine(preciseFirstFrame:)` 默认 `false`

现状：`MovaMpvKernel` 构造期只有 `observeQoeSignals` 一个开关，它同时控制 `paused-for-cache` 观察与
FFI 事件泵（`mpv_kernel.dart:119-149`）；`createMovaEngine` 传 `observeQoeSignals: reporter != null`。

改为两个开关：

- `MovaMpvKernel({bool observeQoeSignals = true, bool? observeNativeEvents, ...})`，
  `observeNativeEvents` 为 `null` 时取 `observeQoeSignals`——**既有调用点行为逐字节不变**。
- `createMovaEngine({bool preciseFirstFrame = false, ...})`：
  `observeQoeSignals: reporter != null`、`observeNativeEvents: reporter != null || preciseFirstFrame`。

**默认关闭的理由：** 泵是每引擎一个弱客户端 + debug 下 100ms 轮询 Timer；FFI 计划的 V9 不变量是
"`qoe:false` 时创建客户端数 0"（`doc/plans/2026-09-29-observe-event-ffi.md` §6）。默认开会打破它。
`rendered` 本身**不依赖**泵——泵不在时自动走兜底判据，所以默认关闭不影响功能可用，只影响精度（约早
200ms）。`MovaView` 是否默认开见 §6 开放问题 Q1。

`MovaEngine` 用的是 `_kernel is MovaStatsProbe` 能力探测订阅 `playbackRestarts`，与 QoE 同一模式，
**不给 `MovaKernel` 加抽象成员**（避免打断所有测试假内核）。

### D3 — fit：构造期初值 + 组件"变化时生效"，运行时 `setFit` 在两次声明变化之间胜出

三个入口、一条优先级规则：

| 入口 | 语义 |
|---|---|
| `MovaEngine(fit:)` / `createMovaEngine(fit:)`，默认 `MovaFit.contain` | 引擎**初始** `state.fit`。不发 `MovaFitChange`（不是变化，是初值） |
| `MovaPlayer(fit:)` / `MovaView(fit:)`，默认 `null` | `null` = 不碰引擎。非 `null`：**挂载时**应用一次（与当前值不同才调 `setFit`），之后**仅当该参数值变化**（或换了 `api`）才再应用 |
| `api.setFit()` / fit 按钮 | 立即生效，并**一直保持到**宿主下一次传入**不同的** `fit` 参数为止 |

即"声明式值是受控于变化的初值"，不是每次 build 都强制回写——否则 fit 按钮点了会被下一次父组件重建
立刻改回去。`MovaFeedPlayer.fit`（池创建时 `setFit`）不动。所有默认值与今天相同：**不传就零变化**。

`setFit` 是同步 `emit`（`MovaBus.emit` 同步更新值，`bus.dart:49-53`），所以 `MovaPlayer.initState`
里应用的 fit 在首帧 build 就生效，不会先闪一帧 contain。

### D4 — 封面：`MovaPlayer(poster:)` 叠在"视频画面"那一层，`rendered && 有画面尺寸` 才淡出

- 放在**传给 `skin.assemble()` 的 `video` 参数里**（`Stack[渲染面, 封面层]`），而不是整个播放器最上层：
  这样所有皮肤（含第三方皮肤）的缓冲转圈、错误层、控制条都自然画在封面**之上**——封面 + 转圈正是直播卡片
  要的效果；宿主旧实现把转圈盖在封面下面，是因为它没法插到皮肤中间。
- 淡出条件 `state.rendered && state.width > 0 && state.height > 0`：纯音频源/`audioOnly` 引擎没有画面
  可露，封面**常驻**（当专辑封面用）。`rendered` 先到、尺寸后到（或反之）时取较晚者，差几毫秒。
- 重新盖上（`rendered` 回到 `false`）**瞬间完成**、淡出走动画：`AnimatedOpacity` 的 `duration` 取
  `shown ? Duration.zero : posterFade`。
- `IgnorePointer` 包裹，不吃手势。`poster == null` 时**不插任何 widget**，树与今天逐节点相同。

### D5 — 极简皮肤 `MovaMinimalSkin` + `MovaTheme` 三个可空字段

- `MovaMinimalSkin({bool showBuffering = true, bool showError = false})`：只有画面 + 中心槽
  （缓冲转圈，可选错误层），不挂手势层、不挂任何栏。
- `MovaTheme` 新增 `bufferingSize`（`double?`）、`bufferingStrokeWidth`（`double?`）、
  `bufferingColor`（`int?` ARGB），**全部默认 `null` = 沿用今天的 Material 默认尺寸/线宽与
  `accentColor`**，因此默认皮肤的转圈一个像素都不变。`MovaBufferingComponent` 读这三个字段（`null` 时
  不包 `SizedBox`、不传 `strokeWidth`）。

### D6 — 声明式组件 `MovaView`：拥有引擎；`MovaSource.sameAs()` 判同源；命令式 API 原样保留

- `MovaView` 内部调 `createMovaEngine()`（或宿主给的 `engineFactory`），**拥有**并负责 `dispose` 这个引擎，
  组合 `MovaPlayer(fit:, poster:, skin:)` 与（Task 13 起）`MovaAutoPause`。
- **同源不重开**：`MovaSource` 刻意**不重写 `==`**（它是 `const` 值、可能被宿主当 Map key 按身份用，
  改 `==` 是隐性 breaking），新增 `bool sameAs(MovaSource other)`：比较 `uri`、`type`、（Task 11 起）
  `alternatives`；`title` 不参与（标题变了不值得重开流）。
- `source == null`：不建引擎（懒创建，第一次有源才建，对齐宿主今天的行为）；已有引擎时 `pause()` 并只显示
  封面（无封面则黑底）。
- `options` 变化（`MovaOpts` 已有 `==`）→ 重建引擎（`MovaOpts` 是构造期配置，没法热改），旧引擎
  `dispose`，新引擎重开当前源。文档写明开销。`engineFactory`/`autoPlay` 变化不触发重建/重开。
- `autoLoadQualities`：今天 `MovaPlayer.initState` 里调 `loadQualities()` 时，引擎的 `_source` 往往还没设上
  （`open()` 在第一个 `await` 之后才写 `_source`），实际是空操作。`MovaView` 改为在 `open()` 完成后自己调，
  并给内部 `MovaPlayer` 传 `autoLoadQualities: false`。
- 打开失败（未开 recovery 时 `open()` 会把内核异常抛出来）：`MovaView` 捕获，交给 `onOpenError`，
  未提供则 `FlutterError.reportError`（不让未捕获异步异常打崩宿主）。**不改** `MovaEngine.open()` 的抛出
  语义——`MovaAdController` 依赖它区分 `openThrew`（`ad_controller.dart:762-767`）。

### D7 — 超时与恢复：看门狗 + 策略对象 + 事件，`MovaOpts.recovery` 默认关闭

仿 `core/ad/fail.dart`：**值对象 `MovaPlayFail` + 可注入 `MovaRecoveryPolicy` + 默认实现**，运行时
一律"策略 + 事件"，不 `throw`。

- **触发源（仅 `enabled: true` 时存在，关闭时不建任何 Timer、不订阅任何流）：**

  | `MovaPlayFailKind` | 判据 |
  |---|---|
  | `startTimeout` | 一次尝试武装后 `startTimeout` 内没落地首帧（D1 的 attempt 级落地）。**只在播放意图为 true 时计时**——`autoPlay:false` 的暂停态打开不计时，`play()` 后从头计 |
  | `stallTimeout` | 落地后，`buffering` 连续为 true 达 `stallTimeout` 且播放意图为 true（用户暂停即停表） |
  | `openThrew` | 内核 `open()` 抛异常。**仅 recovery 开启时**由引擎捕获转为失败；关闭时照旧抛给调用方 |
  | `nativeEndError` | 原生 `END_FILE(reason=error)`（泵存在时才有；坏地址可秒判，不必等超时） |
  | `liveEnded` | 直播源 `completed` 变 true（直播流被服务端断开会走到 EOF）；`liveEndIsFailure` 可关 |

- **刻意不把内核 `error` 流当触发源：** media_kit 的 `stream.error` 是 mpv error 级日志行（`real.dart`
  里按 prefix 过滤的 log），大量是非致命的；致命的要么有 `END_FILE(error)`（精确），要么表现为起不来
  （超时兜住）。拿日志当触发源会对 HLS 的瞬时报错过度反应。`MovaErrorEvent` 照旧原样外发，行为不变。
- **决策：** `MovaRecoveryDecision.retry(delay)` / `.failover(delay)` / `.giveUp()`。比 `MovaAdFailAction`
  多一个 `delay`——直播重连要退避，枚举装不下。默认策略 `MovaRetryThenFailover(maxRetries: 1,
  retryDelay: 1s)`：每个地址重试 1 次，再切下一个备选，全部用完放弃。另给 `MovaFailoverOnly`。
  策略抛异常 → 按 `giveUp` 处理（宿主代码绝不能打断引擎）。
- **事件（"可区分的错误事件"）：**
  - `MovaPlayFailure(fail, action)`：每次失败一条，`fail.kind` 区分起播超时/卡顿超时/…，`action` 告诉宿主
    mova 接下来要干什么。**此时不写 `state.error`**——还在重试，不该弹错误层。
  - `MovaRecovered(attempts)`：失败后某次尝试重新落地首帧时发，计数清零。
  - 放弃时：`state.error = MovaGiveUpError(lastFail)` + `MovaErrorEvent(MovaGiveUpError)` + 拦截链
    `onError`，并 `pause()` 内核（别让离线直播源在后台一直重连吃流量）。默认皮肤的错误层随之出现，
    点重试走 `reload()`（= 从主地址开一个全新会话）。
- **重试/切换 = 内核重载，不是新会话：** 不过 `beforeOpen` 拦截器、不发 `MovaSourceChange`、不动 QoE
  会话边界（TTFF 因此量的是"用户真实等了多久"，含重试）。`MovaSourceChange`+`MovaReady` 在本会话
  **第一次**内核 open 成功时发一次（不论是首次还是重试成功）。点播源若失败前已出过画面，重载后按
  `_seekOrPark(lastPosition)` 续播（与 `switchQuality` 同一套寄存保证，`engine.dart:1046-1096`）。
- **计数口径：** `attempt` = 当前地址自上次落地以来的连续失败次数；`streak` = 跨地址的连续失败次数。
  落地即清零——长时间播放后偶发一次卡顿不会因为"预算早用完了"直接放弃。

### D8 — 多地址：`MovaSource.alternatives`，切换由 D7 的策略驱动；排序/过滤留给宿主

- `MovaSource(uri, {type, title, List<String> alternatives = const []})`，`uris = [uri, ...alternatives]`。
  默认空列表 → 行为不变。
- **只有 `MovaOpts.recovery.enabled` 时备选才会被用到**（失败检测是 recovery 提供的）；关闭时
  `alternatives` 被忽略，文档写明（是否改为"给了备选就隐式开启"见 Q3）。
- `MovaState.sourceIndex`（`int`，默认 0）+ `MovaFailover(from, to, uri)` 事件告知当前用的是哪条。
- 引擎内部所有"当前地址"的读取点改走 `_activeUri`：`loadQualities`、`switchQuality`（auto 档）、
  `_reopenLiveSource`、`_seekTimeshift` 的 `urlBuilder` 基址。`reload()` 仍是 `open(_source)` = 回到主地址
  的全新会话（用户点重试就该从最好的那条再来）。切到备选时清空 `qualities`（那是主地址的 master 档位）。
- **排序/过滤钩子——评估结论：留给宿主，mova 不提供排序钩子。** 宿主的规则是"按档位名
  `m_main_720` > `p_main` > 其余、剔除 `webrtc://`"：名字是宿主接口的业务元数据，`MovaSource` 只承载
  URI，钩子拿到的只能是字符串，排不了名字；协议能否播放取决于具体 libmpv 构建（mova 自己的瘦身版就收窄过
  protocol 白名单），mova 硬编码一份黑名单迟早过时。宿主排好序传进来即可，mova 只保证"按给定顺序尝试"。
  只提供一个纯清洗辅助 `MovaSource.pick(Iterable<String?>, {type, title})`：去空白、去空串、去重保序，
  首个作主地址、其余作备选，全空返回 `null`——省掉宿主那段 `nonEmpty` 样板。

### D9 — 自动暂停守卫：纯逻辑 gate 在 core，信号采集 widget 在 ui，**零新依赖**

**信号采集（全部 Flutter SDK 自带）：**

| 场景 | 实现 | 覆盖 / 局限 |
|---|---|---|
| 滚出视口 | 沿祖先链收集所有 `Scrollable` 的 `ScrollPosition` 监听；每次滚动/布局后取自身 `RenderBox` 全局矩形，与各祖先视口矩形逐层求交，得可见比例 | 覆盖 `ListView`/`CustomScrollView`/`PageView`/`TabBarView`（后两者也是 Scrollable）。**不覆盖**任意 `ClipRect`/`Transform`/被 `Overlay` 遮住——那需要 `visibility_detector` 那种按 layer 合成的方案，见 Q6 |
| Tab/Offstage 隐藏 | `TickerMode.getNotifier(context)`（ValueListenable，不触发子树重建） | go_router 17.5 `StatefulShellRoute.indexedStack` 给非活跃分支套 `Offstage + TickerMode(enabled:false)`（`go_router-17.5.0/lib/src/route.dart:1631-1636`，已核实），bingo 用的正是 `indexedStack` |
| 被其他路由盖住 | ① `ModalRoute.isCurrentOf(context)`（依赖注册，路由栈变化自动通知）；② 可选 `RouteObserver<ModalRoute<dynamic>>`：对自身路由及**每一层祖先路由**订阅 `RouteAware`，`didPushNext`/`didPopNext` | ① 只看所在 navigator：go_router shell 里卡片在分支 navigator，**登录页 push 到根 navigator 时分支路由仍是 current**，① 看不到。② 解决它，需宿主把同一个 observer 挂到根 `GoRouter(observers:)` 与 `StatefulShellBranch(observers:)`（各一行）。不用 secondaryAnimation 启发式：`fullscreenDialog` 页面和 `PopupRoute` 都不驱动它，不可靠 |
| 前后台 | `AppLifecycleListener(onStateChange:)`：`hidden`/`paused` 视为隐藏；`inactive` **不暂停**但做"播放意图快照" | `inactive` 不暂停是为了 Android 系统 PiP（Activity onPause → `inactive`，画面仍可见）与下拉通知栏 |

**决策逻辑（纯 Dart `MovaAutoPauseGate`，可单测）：**

- 隐藏原因集合由空变非空 → 记录"隐藏前是否在播"（`state.playing`，即播放意图，缓冲中也算在播），在播则
  `pause()`。集合由非空变空 → 隐藏前在播且 `resumeOnShow` → 续播。中间原因增减不动作。
- **意图快照取最早的那一刻：** `inactive` 时先快照 `playing`。Android 切后台时 libmpv 会因 surface 被回收
  自己先暂停（CLAUDE.md 小窗真机 ③），等 `hidden` 到达时 `state.playing` 已经是 false——不快照就会误判
  "隐藏前没在播"，回前台照样不续。这正是 CLAUDE.md 记的"回前台需手动续播"问题的解法。
- **豁免：** `state.pip || state.mini` 时不因任何原因暂停（画面在系统画中画/App 内小窗里继续播，页面侧
  看不见是正常的）。
- **直播恢复语义（必须说清）：** 直播暂停后 `play()` 是从**暂停点**接着播，不是边缘——HLS 的暂停点可能
  已滑出 playlist 窗口（卡顿/报错），HTTP-FLV 的连接可能已被服务端断开。因此：
  `liveResume: reloadEdge`（默认）且隐藏时长 ≥ `liveResumeGrace`（默认 3s）→ `backToLiveEdge()`；
  若之后仍未在播（`seekEnd` 分支只 seek 不 play，`engine.dart:1136-1142`）再补一次 `play()`；
  隐藏不足 3s（快速切个 Tab 回来）→ 普通 `play()`，没必要重连。`liveResume: resume` 则一律普通续播。
  点播一律普通续播。
- **为什么守卫不进 `MovaOpts`：** 它描述的是"某个挂载点怎么随可见性变化"，而同一个引擎可能同时被页面和
  小窗两处挂载；`MovaOpts` 是引擎级配置。`MovaAutoPauseConfig` 是纯 Dart 值类（放 core，不含任何
  Flutter 类型——`AppLifecycleState` 等由 ui 层映射成 `MovaHideReason`），只作为 widget 参数。
- **不要给 `MovaFeedPlayer` 的页套守卫：** 池的 `focus()` 已经管"只有一页出声"，两套逻辑会打架。文档写明。

### D10 — 测试替身：独立入口 `package:mova/testing.dart`，`createMovaEngine` 留一个注入点

- **不进主 barrel**（`lib/mova.dart` 一行不加）：测试工具不该出现在宿主 app 的补全列表里。新入口
  `lib/testing.dart` 导出 `MovaTestKernel`（公开版 `FakeKernel` + `MovaStatsProbe` 桩，可推所有流与
  RESTART/END_FILE）与 `MovaTesting`（安装/复位/取已创建内核）。
- 注入点放在 `lib/src/testing/hooks.dart`（一个可空的内核工厂变量，**不被主 barrel 导出**），
  `createMovaEngine()` 检查它：非空时改为 `MovaEngine(kernel: hook(), ...)`，且**平台端口默认值换成
  `MovaEngine` 自己的空实现、不注入 `thumbDir`**——否则宿主测试还会撞上 `path_provider`/
  `screen_brightness` 的平台通道（mova 自己的 `wiring_test.dart` 为此专门 mock 了 `PathProviderPlatform`）。
  显式传入的 `kernel:`/端口仍然优先。
- `lib/src/testing/` 在 `core/` 之外，`purity_test` 不受影响；它**不 import `flutter_test`**（否则
  `flutter_test` 会变成常规依赖），只依赖 mova 自己的 core。
- mova 自己的 `test/support/fake_kernel.dart` 不动（1008 项依赖它）；去重留作后续，见 §5。
- `MovaTestKernel.nativeRestartAvailable` 默认 `false`：`emitRestart()` 照样落地（RESTART 不看门控），
  而 buffering/位置兜底会**立即**落地、不起 1.5s 宽限 Timer——宿主测试不会因挂起 Timer 失败。

---

## 2. 文件结构

**新建**

| 文件 | 职责 | Task |
|---|---|---|
| `lib/src/core/render/first_frame.dart` | `MovaFirstFrameSignal` + `MovaFirstFrameGate`（纯逻辑） | 1 |
| `lib/src/ui/poster.dart` | `MovaPosterLayer`（封面层，`MovaPlayer` 内部用） | 5 |
| `lib/src/ui/skins/minimal_skin.dart` | `MovaMinimalSkin` | 7 |
| `lib/src/ui/view.dart` | `MovaView` + `MovaViewEngineFactory` | 8 |
| `lib/src/core/options/recovery_config.dart` | `MovaRecoveryConfig` | 9 |
| `lib/src/core/recovery/fail.dart` | `MovaPlayFailKind`/`MovaPlayFail`/`MovaRecoveryAction`/`MovaRecoveryDecision`/`MovaRecoveryPolicy`/`MovaRetryThenFailover`/`MovaFailoverOnly`/`MovaGiveUpError` | 9 |
| `lib/src/core/recovery/watchdog.dart` | `MovaPlayWatchdog`（Timer 驱动，不导出） | 9 |
| `lib/src/core/guard/auto_pause.dart` | `MovaHideReason`/`MovaLiveResume`/`MovaAutoPauseConfig`/`MovaGuardAction`/`MovaAutoPauseGate`（纯 Dart） | 12 |
| `lib/src/ui/guard/auto_pause.dart` | `MovaAutoPause` widget | 13 |
| `lib/testing.dart` | 测试入口 barrel | 14 |
| `lib/src/testing/hooks.dart` | 内核工厂注入点（不进主 barrel） | 14 |
| `lib/src/testing/test_kernel.dart` | `MovaTestKernel` | 14 |
| `lib/src/testing/testing.dart` | `MovaTesting` | 14 |

**修改**

| 文件 | 改动 | Task |
|---|---|---|
| `lib/src/core/state/state.dart` | `rendered`、`sourceIndex` 字段 + `copyWith`/`==`/`hashCode` | 2, 11 |
| `lib/src/core/events/events.dart` | `MovaFirstFrame`、`MovaPlayFailure`、`MovaRecovered`、`MovaFailover` | 2, 10, 11 |
| `lib/src/core/engine.dart` | 首帧闸门接线、open 重置宽高、`fit` 构造参、看门狗/恢复、`_activeUri` | 2, 4, 10, 11 |
| `lib/src/core/kernel/mpv_kernel.dart` | `observeNativeEvents` 开关拆分 | 3 |
| `lib/src/platform_impl/wiring.dart` | `preciseFirstFrame`、`fit`、测试注入点、`movaObserveFlags` | 3, 4, 14 |
| `lib/src/ui/player.dart` | `fit`、`poster`、`posterFade` | 4, 5 |
| `lib/src/ui/feed_player.dart` | `posterUntilFirstFrame`（opt-in） | 6 |
| `lib/src/core/options/theme.dart` | `bufferingSize`/`bufferingStrokeWidth`/`bufferingColor` | 7 |
| `lib/src/ui/components/overlays.dart` | `MovaBufferingComponent` 读主题新字段 | 7 |
| `lib/src/core/model/source.dart` | `sameAs`、`alternatives`、`uris`、`pick` | 8, 11 |
| `lib/src/core/options/options.dart` | `recovery` 节 + export | 9 |
| `lib/mova.dart` | 增补导出（不含 testing） | 1, 7, 8, 9, 12, 13 |
| `test/support/fake_kernel.dart` | `FakeKernel` 加 `openGate`（阻塞 open）与 `openError`（让 open 抛） | 2, 10 |
| `README.md`/`CHANGELOG.md`/`doc/SPEC.md`/`CLAUDE.md`/`example/` | 文档、基线、验证 demo 页 | 15 |

**测试数量推进**（基线 **1008**）：

| Task | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 新增 | +14 | +13 | +5 | +8 | +7 | +3 | +7 | +13 | +19 | +14 | +12 | +12 | +11 | +7 | +3 | 0 |
| 累计 | 1022 | 1035 | 1040 | 1048 | 1055 | 1058 | 1065 | 1078 | 1097 | 1111 | 1123 | 1135 | 1146 | 1153 | **1156** | 1156 |

预计数只是规划值；落地 agent 以每个 Task 提交时**实跑**的 `flutter test` 数为准，并按 CLAUDE.md 约定
立即回写 `CLAUDE.md` 与本文件的基线。

**实施状态（2026-10-23 更新）：Task 1–8 已完成**，实测 `flutter analyze lib test` 0 issues、`flutter test` **1078** 全绿；
各 Task 实测新增/累计：1 → +14/1022，2 → +13/1035，3 → +5/1040，4 → +8/1048，5 → +7/1055，6 → +3/1058，
7 → +7/1065，8 → +13/1078，均与上表规划值一致。

**实施状态（2026-10-23 再更新）：Task 9–15 已完成，Task 16 待定（等真机）**。最终实测 `flutter analyze lib test` 0 issues、
`flutter test` **1158** 全绿、`flutter pub publish --dry-run` 0 warnings。Task 9–15 实测新增/累计：
9 → +20/1098，10 → +14/1112，11 → +12/1124，12 → +12/1136，13 → +12/1148，14 → +7/1155，15 → +3/**1158**
（规划终点 1156，多出的 2 项：Task 9 配置测试拆成 5 条而非 4 条，Task 13 多一条"不透明外层路由由 TickerMode 兜住"的断言）。

落地时与本文的偏差（均不改变设计与验收）：
- 计划里 `api.events.whereType<...>()` 的写法在 `Stream` 上不存在（`whereType` 只属于 `Iterable`）；`MovaFirstFrame` 的示例注释与
  测试改用 `where((e) => e is MovaFirstFrame).cast<MovaFirstFrame>()` / `listen` + `is`。后文 Task 10 的 `MovaPlayFailure` 示例同样需要这样改。
- `movaObserveFlags` 放在 `wiring.dart` 文件末尾（紧贴 `createMovaEngine` 文档注释的位置不能插入，否则会抢走其文档）。
- Task 2 断言 12 改为"无 1500ms 宽限计时器残留"：`open()` 自带的控制栏 3s 自动隐藏计时器是既有行为，不属于本任务。
- Task 7 的 `MovaTheme` 值语义断言放在 `test/ui/minimal_skin_test.dart`（计划写在 `options_test.dart`），Task 8 的 `sameAs` 三条放在 `test/core/model_test.dart`，总数不变。
- `MovaView` 的 `engineFactory` 缺省按 Q1 推荐值实现（有封面才开 `preciseFirstFrame`）。

Task 9–15 落地时与本文的偏差：
- **（Task 13，必要偏差）`routeObserver` 改为 `routeObservers`（列表）**：Flutter 的 `NavigatorObserver` 只能挂到一个 Navigator
  （`NavigatorState.initState` 里断言 `observer.navigator == null`），D9 里"同一个 observer 挂到根 `GoRouter(observers:)` 与每个
  `StatefulShellBranch(observers:)`"在 debug 下会直接断言失败。守卫改为接收每个 navigator 各一个观察者的列表，按
  `observer.navigator == route.navigator` 给每一层路由匹配观察者。`MovaAutoPause` 与 `MovaView` 都是这个签名。
- **（Task 13）不透明的外层路由已被 `TickerMode` 兜住**：Overlay 会禁用被不透明路由盖住的子树的 ticker，所以 D9 表格里"根 navigator
  push 登录页时 ① 看不到"只对**半透明**路由成立（对话框、透明页）；`routeObservers` 的增益也只在这里。测试 5 改用 `PageRouteBuilder(opaque:false)`，
  另加 5b 锚定不透明情形。
- **（Task 13）`TickerMode.getNotifier` 已弃用**，实现用 `TickerMode.getValuesNotifier(context).value.enabled`。
- **（Task 13）生命周期测试必须走合法迁移**（`resumed→inactive→hidden`，`hidden→inactive→resumed`），`AppLifecycleListener` 会断言；
  进入 `hidden` 后 Flutter 停止出帧，测试里卸载组件要在前台做。守卫在 `hidden→inactive` 时即清除 background 原因并续播。
- **（Task 9）`MovaRecoveryConfig.copyWith` 增 `clearStallTimeout`/`clearPolicy`**（否则无法把可空字段置回 `null`）。
- **（Task 9）既有测试 `test/core/openness_audio_test.dart` 钉死了 `MovaOpts` 的节清单**（"audioOnly 不是配置节"），新增 `recovery` 节必然要在
  清单里追加 `'recovery'`；断言语义不变，仅此一处既有测试改动（计划写的"允许的既有测试改动：无"漏了它）。
- **（Task 10）起播期限在 `_loadKernel` 返回后才武装**（而非 `_armAttempt` 里）：避免内核 `open()` 在途时期限先到期；只在没有其他加载在途时武装。
  `_onPlayFail` 在 `_kernelOpening > 0` 时忽略（原生 `END_FILE(error)` 可能来自旧文件）。`_announceReady()` 里一并做 `_recomputeLiveSeekable`
  与控制条安顿，使 `open()` 首次失败后重试成功也走同一套收尾。`FakeKernel` 额外加了 `openedUris`（每次 `open` 的 uri 列表）。
- **（Task 10）给 `MovaPlayFailure` 的示例注释改为 `listen` + `is`**（`Stream` 上没有 `whereType`），同 Task 2 的处理。
- **（Task 11）`_sourceIndex`/`_activeUri` 在 Task 10 先以单地址占位落地，Task 11 补成按 `src.uris` 取值**；`loadQualities` 的 master 播放列表基址也改走 `_activeUri`。
- **（Task 14）`nativeRestartAvailable` 默认 `false`** 与计划一致；`createMovaEngine()` 的测试分支同样应用 `probe` 参数（计划草图漏了）。
- **（Task 15）验证页不传 `routeObservers`**：本页只有根 Navigator 一层，`isCurrentOf` 已够用；页内注释说明了嵌套场景才需要。
- 开放问题按用户确认的推荐值落地：Q2 起播/卡顿超时各 10s、默认策略每地址重试 1 次间隔 1s 再切备选、直播 EOF 计失败；Q3 备选在 recovery 关闭时被忽略（README/CHANGELOG 已写明）；
  Q4 排序/过滤留给宿主，仅提供 `MovaSource.pick`；Q5 Dialog/BottomSheet 视为被盖住；Q6 不引入 `visibility_detector`（局限写进 README「已知限制」）；Q10 新增 sealed 事件子类（CHANGELOG 注明）。


### 评审修复（2026-10-23）

11 条全部处理（#9 按终审降级为防御性加固）。按根因统一实现：播放意图与内核观测分离；
打开请求 `_openGen` 与已接受会话 `_sessionGen` 分离；恢复任务同时绑定会话与失败尝试，所有内核加载共享异常入口。
`MovaApi` 无新增成员；`MovaState.playbackIntent` 为默认 false 的新增可观测字段，纳入 copyWith/相等/hashCode。
recovery 关闭时仍不建恢复 Timer、不订阅 endFiles，内核 open 异常照旧抛出；既有关闭对账与广告测试通过。
看门狗旧测试 5/7 改经引擎 play()/pause() 表达播放意图，原超时/停表断言保留；未放宽 openness 断言。

文件缩写：E = `lib/src/core/engine.dart`；S = `lib/src/core/state/state.dart`；
G = `lib/src/core/guard/auto_pause.dart`；U = `lib/src/ui/guard/auto_pause.dart`；V = `lib/src/ui/view.dart`。
引擎回归在 `test/core/recovery/review_regression_test.dart`（12 条），守卫/视图回归在
`test/ui/review_regression_test.dart`（7 条，含一条纯 Dart gate 时间断言）。现有 FakeKernel 无需再改。

| 缺陷 | 修法 | 改动文件 | 回归测试名（完整或参数展开） |
|---|---|---|---|
| #1 | play/open 接受后写播放意图，pause 清意图；重试按最新意图加载，暂停时停看门狗，后续 play 重计 | E、S | `#1 pause during pending retry loads paused and play restarts watchdog` |
| #2 | 隐藏期间订阅意图、playing 与 PiP/mini；新播放或豁免结束重新暂停并记恢复意图；换 api 重绑 | E、S、G、U | `#2 hidden MovaView pauses asynchronous open and resumes on show`；`#2 hidden guard rebinds engines and pauses after mini exemption ends` |
| #3 | 视图加载世代在 source=null 时失效；迟到完成补 pause 并跳过档位探测 | V | `#3 source null invalidates delayed beforeOpen and skips quality probe` |
| #4 | 恢复绑定失败 attempt；任何 _armAttempt 路径取消旧恢复计时器 | E | `#4 replacement quality attempt cancels pending recovery`；`#4 replacement live edge attempt cancels pending recovery` |
| #5 | 直播恢复绑定动作世代；await 后检查可见性与 api；失效后补暂停 | U | `#5 delayed live resume checks hidden generation`；`#5 delayed live resume checks api replacement` |
| #6 | _loadKernel 统一把 recovery 开启时的内核异常交给 _onPlayFail(openThrew)，失败加载不继续成功收尾；关闭时保留 rethrow | E | `#6 internal quality open error enters recovery`；`#6 internal live edge open error enters recovery` |
| #7 | 独立保存恢复位置，跨失败重试保留；有效尝试首帧或新 open 会话清除 | E | `#7 recovery retains VOD position across a thrown retry` |
| #8 | 仅 beforeOpen 通过、会话实际替换时推进会话世代，恢复不受被拒 open 的请求世代影响 | E | `#8 rejected open preserves accepted session recovery` |
| #9 | 暂停加载成功返回后，向闸门补喂当前非零尺寸；注释明确防御信号早于 open 返回、Task 16 待验证 | E | `#9 paused open replays size received before open completes` |
| #10 | gate 就地重配，保留隐藏意图、inactive 快照与起始时间；从未过滤的原始原因重算生效集合 | G、U | `#10 gate config update preserves original hidden timestamp`；`#10 config update preserves hidden intent and original grace start` |
| #11 | 档位请求捕获会话世代、地址下标；成功/null/异常返回均丢弃过期结果 | E | `#11 stale quality playlist response is discarded`；`#11 stale quality null response is discarded`；`#11 stale quality error response is discarded`；`#11 stale quality session response is discarded` |

实跑验收（未 build、未连设备、未用 adb、未 git commit）：

- `flutter analyze lib test`：`No issues found! (ran in 8.1s)`，exit 0。
- `flutter test --reporter expanded`：`01:05 +1177: All tests passed!`，exit 0；1158 → 1177，新增 19 条。
- `flutter pub publish --dry-run`：`Package has 0 warnings.`，exit 0；仅预检，未发布。
- 日志保留在 `.dart_tool/review-2026-10-23/`（不进入发布包）。

仍需 Task 16 真机确认：#9 暂停态 mpv 尺寸/RESTART 是否早于 open 返回及宽限兜底；
Android inactive→hidden 与系统暂停的真实顺序、PiP/mini 豁免结束后的暂停；隐藏 ≥3s 后直播回边缘的实际效果；
坏地址 END_FILE(error) 与内部重载异常的真实时机。此次均只有纯逻辑/WidgetTester 证据，无真机结论。

---

## 3. Global Constraints

- 包名 `mova`，公开类前缀 `Mova`；`src/` 内文件名不带前缀；沿用既有命名风格（事件不带 `Event` 后缀，
  `MovaErrorEvent` 是历史例外）。
- **`lib/src/core/**` 禁止 `import 'package:flutter/...'`；`_mediaKitExceptions` 恒为
  `{'kernel/mpv_kernel.dart'}`，任何 Task 不许改。** 守卫 gate、恢复策略、首帧闸门全部是纯 Dart。
- 注释（CLAUDE.md）：每个类/方法/getter/字段都要注释，**先英文、空行、后中文**；公开 API 带参数/返回/示例。
- 值对象构造期不变量用 `assert`；含 `Duration` 比较的 `const` 构造器**不能**在初始化列表写 assert，
  改提供 `assertValid()` 由持有者在入口调用（照 `MovaAdBreak.assertValid()`）。
- **不新增任何第三方依赖**（含 `visibility_detector`、`clock`）。
- **`MovaApi` 零新增成员**；`FakeMovaApi`、`MovaSwapEngine`、`MovaCtrl` 不需要改。
- **既有 1008 项一项都不许删、断言语义不许放松。** 允许的既有测试改动：无（新增字段都有默认值）。
- 每个 Task 一个 commit（`type(mova): message`），`flutter analyze lib test` 0 issues + `flutter test`
  全绿再往下走；提交后用实测数字回写基线。
- **验收只依赖 analyze/test/纯逻辑/WidgetTester，不依赖真机**（见文首执行约束）。
- 时间相关断言用 `fake_async`（dev 依赖已在，`pubspec.yaml`），不 sleep。
- `MovaEvent` 是 `sealed`：新增 4 个子类对宿主里**没有 `default` 的穷尽 switch** 是编译期 breaking；
  mova 自己的 `translateMovaEvent` 有 `default`（`report/translator.dart:145`）不受影响。CHANGELOG 注明。

---

## Task 1：首帧闸门纯逻辑 `MovaFirstFrameGate` ✅ 已完成（实测 +14，累计 1022）

**Files:** Create `lib/src/core/render/first_frame.dart`；Modify `lib/mova.dart`；
Test: `test/core/render/first_frame_test.dart`。

**Produces:**

```dart
/// Which observation landed the first frame of a playback attempt.
///
/// 哪一种观测让一次播放尝试的首帧落地。
enum MovaFirstFrameSignal {
  /// Native `MPV_EVENT_PLAYBACK_RESTART` — the precise signal.
  ///
  /// 原生 `MPV_EVENT_PLAYBACK_RESTART`——精确信号。
  restart,

  /// A `buffering` true→false falling edge (fallback).
  ///
  /// `buffering` 的 true→false 下降沿（兜底）。
  buffering,

  /// Two consecutive increasing positions above zero (fallback).
  ///
  /// 连续两个递增且大于 0 的位置样本（兜底）。
  progress,

  /// The first non-zero video size after a paused open (fallback).
  ///
  /// 暂停态打开后首个非零画面尺寸（兜底）。
  size,

  /// A fallback fired while the native signal was live, and no restart
  /// followed within the grace window.
  ///
  /// 原生信号在工作时兜底信号先到，且宽限期内始终没等到 RESTART。
  grace,
}

/// Decides when one playback attempt has actually started presenting media.
///
/// Pure logic: no `Timer`, no clock. The owner feeds observations and starts
/// the grace timer itself when [awaitingGrace] turns true. Every `onXxx`
/// returns the landing signal exactly once, or `null`.
///
/// 判定一次播放尝试何时真正开始呈现媒体。
///
/// 纯逻辑：无 `Timer`、无时钟。持有者喂观测，并在 [awaitingGrace] 变 true 时自己
/// 起宽限计时。每个 `onXxx` 只在落地那一次返回信号，否则返回 `null`。
///
/// Example / 示例:
/// ```dart
/// final gate = MovaFirstFrameGate()..arm(autoPlay: true);
/// gate.onBuffering(true, nativeLive: false);           // null
/// gate.onBuffering(false, nativeLive: false);          // MovaFirstFrameSignal.buffering
/// ```
class MovaFirstFrameGate {
  /// Whether an attempt is armed (landed or not).
  ///
  /// 是否已武装一次尝试（无论是否已落地）。
  bool get armed;

  /// Whether the current attempt has landed.
  ///
  /// 当前尝试是否已落地。
  bool get landed;

  /// True once a fallback fired while the native signal was live and the
  /// attempt is still waiting for a restart — the owner should start a
  /// grace timer and call [onGraceExpired] when it fires.
  ///
  /// 原生信号在工作时兜底信号先到、当前尝试仍在等 RESTART 时为 true——持有者应
  /// 起一个宽限计时器，到点调用 [onGraceExpired]。
  bool get awaitingGrace;

  /// Arms a fresh attempt; [autoPlay] false enables the size fallback.
  ///
  /// 武装一次新尝试；[autoPlay] 为 false 时启用尺寸兜底。
  void arm({required bool autoPlay});

  /// Feeds a native restart; always authoritative.
  ///
  /// 输入一次原生 RESTART；任何时候都权威。
  MovaFirstFrameSignal? onRestart();

  /// Feeds a buffering flag; lands only on a true→false edge.
  ///
  /// 输入一次缓冲标志；只在 true→false 下降沿落地。
  MovaFirstFrameSignal? onBuffering(bool buffering, {required bool nativeLive});

  /// Feeds a position; lands on the second consecutive increase above zero.
  ///
  /// 输入一次位置；在连续第二次递增且大于 0 时落地。
  MovaFirstFrameSignal? onProgress(Duration position, {required bool nativeLive});

  /// Feeds a video size; lands only for a paused open on the first non-zero size.
  ///
  /// 输入一次画面尺寸；只在暂停态打开且首个非零尺寸时落地。
  MovaFirstFrameSignal? onSize(int width, int height, {required bool nativeLive});

  /// Lands the attempt via [MovaFirstFrameSignal.grace] if still waiting.
  ///
  /// 若仍在等待，则以 [MovaFirstFrameSignal.grace] 落地。
  MovaFirstFrameSignal? onGraceExpired();

  /// Disarms everything.
  ///
  /// 解除一切武装。
  void reset();
}
```

规则：未武装或已落地时一律返回 `null`；兜底信号在 `nativeLive == true` 时**不落地**，只把
`awaitingGrace` 置 true（首次）；`onRestart()` 不看 `nativeLive`。

**断言（14）：**
1. 未 `arm` 时所有 `onXxx` 返回 `null`。
2. `onRestart()` 武装后立即落地，`landed` 为 true；再调返回 `null`（只落一次）。
3. 只收到初始 `false`（之前没有 `true`）不落地。
4. `true`→`false`（`nativeLive:false`）落地为 `buffering`。
5. 同序列 `nativeLive:true` 不落地，`awaitingGrace` 变 true；随后 `onRestart()` 落地为 `restart`，`awaitingGrace` 复位。
6. `awaitingGrace` 状态下 `onGraceExpired()` 落地为 `grace`；未进入宽限时调它返回 `null`。
7. 位置 `0 → 40ms` 不落地（首个样本不可信）；`40 → 80ms`（`nativeLive:false`）落地为 `progress`。
8. 位置非递增（`80 → 80`、`80 → 40`）不落地。
9. `arm(autoPlay:false)` 后 `onSize(1280,720)` 落地为 `size`；`onSize(0,0)` 不落地。
10. `arm(autoPlay:true)` 后 `onSize(1280,720)` 不落地（播放态有更可靠的兜底）。
11. `arm(autoPlay:false)` + `nativeLive:true` 的尺寸只进宽限，不落地。
12. 重新 `arm` 清掉上一次的下降沿记忆与位置记忆（`true` 后 `arm` 再收 `false` 不落地）。
13. `reset()` 后 `armed`/`landed`/`awaitingGrace` 全 false。
14. `landed` 之后的兜底信号不再让 `awaitingGrace` 变 true。

**验收：** analyze 0；测试 **1022**。

---

## Task 2：引擎接线——`MovaState.rendered` + `MovaFirstFrame` + open 重置宽高 ✅ 已完成（实测 +13，累计 1035）

**Files:** Modify `lib/src/core/state/state.dart`、`lib/src/core/events/events.dart`、
`lib/src/core/engine.dart`、`test/support/fake_kernel.dart`（加 `openGate`）；
Test: `test/core/first_frame_engine_test.dart`、`test/core/state_test.dart`（增补）。

**Produces（公开面）：**

```dart
// state.dart
/// Whether the current source has started presenting media: its first video
/// frame is on screen, or — for a source/engine without video — its first
/// audio is playing. Reset to false by every `open()`; internal reloads
/// (quality switch, back-to-live reopen, recovery retries) leave it alone.
///
/// 当前源是否已开始呈现媒体：视频源的首帧已上屏；无视频的源/引擎则是首段音频
/// 已在播放。每次 `open()` 都会重置为 false；内部重载（换档、回直播边缘重开、
/// 恢复重试）不动它。
final bool rendered;

// events.dart
/// The current source presented its first frame (or first audio).
///
/// Fires once per `open()`, every time — the repeatable counterpart of
/// media_kit's one-shot `waitUntilFirstFrameRendered`.
///
/// 当前源呈现了首帧（或首段音频）。
///
/// 每次 `open()` 都会触发一次——是 media_kit 一次性
/// `waitUntilFirstFrameRendered` 的可重复版本。
///
/// Example / 示例:
/// ```dart
/// api.events.whereType<MovaFirstFrame>().listen((e) => log('ttff ${e.sinceOpen} via ${e.signal}'));
/// ```
class MovaFirstFrame extends MovaEvent {
  /// Elapsed time since the `open()` call that started this source.
  ///
  /// 距开始本源的那次 `open()` 调用的耗时。
  final Duration sinceOpen;

  /// Which observation landed it.
  ///
  /// 由哪种观测落地。
  final MovaFirstFrameSignal signal;

  /// Creates the event.
  ///
  /// 创建事件。
  const MovaFirstFrame({required this.sinceOpen, required this.signal});
}
```

`MovaState` 的 `hashCode` 把 `rendered` 并入第一组 `Object.hash`（9 个参数，上限 20）。

**引擎改动草图（全部是增量）：**

```dart
final MovaFirstFrameGate _frameGate = MovaFirstFrameGate();
StreamSubscription<void>? _restartSub;
Timer? _graceTimer;
DateTime? _openedAt;

/// In-flight kernel `open()` calls; gate observations are dropped while > 0.
///
/// 在途的内核 `open()` 调用数；大于 0 时丢弃一切闸门观测。
int _kernelOpening = 0;

/// How long a fallback may wait for a native restart before landing anyway.
///
/// 兜底信号先到后，最多等原生 RESTART 多久再自行落地。
static const Duration _firstFrameGrace = Duration(milliseconds: 1500);

bool get _nativeLive {
  final k = _kernel;
  return k is MovaStatsProbe && (k as MovaStatsProbe).nativeRestartAvailable;
}

/// Wraps every kernel open so the gate ignores stale signals meanwhile.
///
/// 包住每一次内核 open，使闸门在途期间忽略陈旧信号。
Future<void> _loadKernel(String uri, {required bool play}) async {
  _kernelOpening++;
  try {
    await _kernel.open(uri, play: play);
  } finally {
    _kernelOpening--;
  }
}

void _armAttempt({required bool autoPlay}) {
  _graceTimer?.cancel();
  _graceTimer = null;
  _frameGate.arm(autoPlay: autoPlay);
}

void _feedGate(MovaFirstFrameSignal? Function() observe) {
  if (_kernelOpening > 0 || _events.isClosed) return;
  final landed = observe();
  if (landed != null) return _onAttemptLanded(landed);
  if (_frameGate.awaitingGrace && _graceTimer == null) {
    _graceTimer = Timer(_firstFrameGrace, () {
      _graceTimer = null;
      _feedGate(_frameGate.onGraceExpired);
    });
  }
}

void _onAttemptLanded(MovaFirstFrameSignal signal) {
  _graceTimer?.cancel();
  _graceTimer = null;
  // Task 10 在此插入：_watchdog?.onLanded() 与 MovaRecovered。
  if (state.rendered) return;
  _state.emit(state.copyWith(rendered: true));
  final at = _openedAt;
  _events.add(MovaFirstFrame(
    sinceOpen: at == null ? Duration.zero : DateTime.now().difference(at),
    signal: signal,
  ));
}
```

接线点：
- 构造期：`if (_kernel is MovaStatsProbe)` 订阅 `playbackRestarts` →
  `_feedGate(_frameGate.onRestart)`。
- `_bufferingSub`：`_feedGate(() => _frameGate.onBuffering(v, nativeLive: _nativeLive))`。
- `_positionSub`：在 `_lastPosition = v` 之后（即 seek 结算过滤之后）喂 `onProgress`。
- `_sizeSub`：喂 `onSize`。
- `open()`：在 `_qoe?.onOpen(...)` 之后，把既有那次 `_state.emit(state.copyWith(qualities: ..., duration:
  Duration.zero, ...))` **并入** `rendered: false, width: 0, height: 0`；`_openedAt = DateTime.now()`；
  `_armAttempt(autoPlay: autoPlay)`；`await _kernel.open(...)` 改为 `await _loadKernel(...)`。
- `switchQuality`/`_reopenLiveSource`/`_seekTimeshift`：内核 open 改走 `_loadKernel`，之前
  `_armAttempt(autoPlay: true /* switchQuality 用 wasPlaying */)`，**不碰 `rendered`**。
- `dispose()`：**在第一个 `await` 之前同步** `_graceTimer?.cancel()`（`_restartSub` 的取消可以放后面）。
  原因：`MovaView`/宿主是在 `State.dispose()` 里 `unawaited(engine.dispose())`，只有 async 函数的同步前缀
  会在拆树时立刻执行；flutter_test 在拆树后检查挂起 Timer（"A Timer is still pending even after the
  widget tree was disposed"），放在 `await _playingSub.cancel()` 之后就会让宿主测试红。

**宽高重置是一处有意的行为微调**（Q8）：今天宽高要等 media_kit `stop()` 异步发出的 `null` 才归零；
提前到 `open()` 同步归零与 `duration` 重置同理，换源后旧画面比例不会再漏进新源的视频矩形计算和封面判据。
不额外发 `MovaSizeChange`。

**测试支持改动：** `FakeKernel` 加 `Completer<void>? openGate`——非空时 `open()` 等它完成，用来模拟
"内核 open 在途"。

**断言（13）：**
1. 先推尺寸 `1280x720`，再 `open()` → `state.rendered == false`、`width == 0`、`height == 0`。
2. `FakeStatsKernel(nativeRestartAvailable: true)`：`emitRestart()` → `rendered == true` + 恰好一条 `MovaFirstFrame(signal: restart)`，`sinceOpen >= 0`。
3. 原生可用、只有 buffering 下降沿 → 未渲染；`fake_async` 推进 1500ms → 渲染，`signal == grace`。
4. 原生可用、下降沿后 500ms 内 RESTART → `signal == restart`，推进 1500ms 后**没有**第二条事件。
5. `FakeKernel`（无探针）：`buffering` true→false → 渲染，`signal == buffering`。
6. 只有初始 `false` → 不渲染。
7. 位置 `40ms → 80ms` → 渲染，`signal == progress`。
8. `open(autoPlay:false)` 后推尺寸 → 渲染，`signal == size`；`autoPlay:true` 时只推尺寸不渲染。
9. 第二次 `open()` → `rendered` 回 false，再落地后第二条 `MovaFirstFrame`（可重复）。
10. `openGate` 未完成时 `emitRestart()` 与 buffering 下降沿均被忽略；完成后再 `emitRestart()` 才渲染。
11. 已渲染后 `switchQuality` → `rendered` 仍为 true，无新 `MovaFirstFrame`。
12. 宽限计时中 `dispose()` → 推进时间不抛、不发事件。
13. `state_test`：`copyWith(rendered:)`、`==`、`hashCode` 覆盖新字段；默认 `false`。

**验收：** 既有 `engine_test.dart`/`report_engine_test.dart` 全部原样通过（`rendered` 默认值不影响任何
既有断言）；测试 **1035**。

---

## Task 3：原生事件订阅与 QoE 解耦——`observeNativeEvents` / `preciseFirstFrame` ✅ 已完成（实测 +5，累计 1040）

**Files:** Modify `lib/src/core/kernel/mpv_kernel.dart`、`lib/src/platform_impl/wiring.dart`；
Test: `test/core/kernel/mpv_kernel_events_test.dart`（增补，复用其 `_FakePlayer`/`_FakeNative`）、
`test/platform_impl/wiring_test.dart`（增补）。

**内核构造期改写（保持 QoE 路径的调用顺序逐字不变）：**

```dart
MovaMpvKernel({
  Player? player,
  this.audioOnly = false,
  this.lazyVideo = false,
  bool observeQoeSignals = true,
  bool? observeNativeEvents,
  MovaMpvEventBackendFactory? backendFactory,
  this.tlsVerify = false,
  this.tlsCaFile,
}) : ... {
  // ...宽高订阅不变...
  final wantNative = (observeNativeEvents ?? observeQoeSignals) && backendFactory != null;
  if (!observeQoeSignals && !wantNative) return;
  final native = _player.platform;
  if (native is! NativePlayer) return;
  var setup = Future<void>.value();
  if (observeQoeSignals) {
    setup = native.observeProperty('paused-for-cache', ...).catchError((_) {});
  }
  if (wantNative) setup = setup.then((_) => _observeNativeEvents(native));
  _observeSetup = setup;
}
```

`createMovaEngine` 新增：

```dart
/// - [preciseFirstFrame]: subscribe to libmpv's native `PLAYBACK_RESTART` even
///   without a reporter, so `MovaState.rendered`/`MovaFirstFrame` land on the
///   real first frame (~200ms later and exact) instead of the buffering/position
///   fallback. Costs one weak mpv client per engine (plus a 100ms poll in debug).
///   Default `false`; ignored when [kernel] is supplied /
///   即使没有 reporter 也订阅 libmpv 原生 `PLAYBACK_RESTART`，让
///   `MovaState.rendered`/`MovaFirstFrame` 落在真正的首帧上（比 buffering/位置兜底
///   准，约晚 200ms），代价是每引擎一个 mpv 弱客户端（debug 下另有 100ms 轮询）。
///   默认 `false`；传入 [kernel] 时忽略
```

为了不构造真 `Player` 也能测"参数是否正确传到内核"，把标志推导抽成纯函数（`@visibleForTesting`）：

```dart
/// Which native observations the default kernel should set up.
///
/// 默认内核应开启哪些原生观察。
@visibleForTesting
({bool qoe, bool native}) movaObserveFlags({required bool hasReporter, required bool preciseFirstFrame}) =>
    (qoe: hasReporter, native: hasReporter || preciseFirstFrame);
```

**断言（5）：**
1. `observeQoeSignals:false, observeNativeEvents:true` + 假后端 → `backendFactory` 被调用、`callLog` 里**没有** `native.observeProperty:paused-for-cache`。
2. `observeQoeSignals:true, observeNativeEvents:false` → 观察了 `paused-for-cache`、`backendFactory` 未被调用。
3. 两者默认（`observeNativeEvents` 省略）→ 与改前一致（既有 `observeQoeSignals=false never calls backendFactory` 仍过，另补 `true` 时两者都发生且 `paused-for-cache` 在前）。
4. `movaObserveFlags` 四种组合真值表。
5. `observeNativeEvents:true` 但非 `NativePlayer` 平台 → 不调工厂、不抛。

**验收：** FFI 计划的 V9 不变量在默认参数下成立（无 reporter、`preciseFirstFrame:false` → 不建客户端，
由断言 4 + 既有测试覆盖）；测试 **1040**。

---

## Task 4：填充模式可声明——`MovaEngine/createMovaEngine(fit:)` + `MovaPlayer(fit:)` ✅ 已完成（实测 +8，累计 1048）

**Files:** Modify `lib/src/core/engine.dart`（`_state` 改在初始化列表里用 `MovaState(fit: fit)` 播种）、
`lib/src/platform_impl/wiring.dart`、`lib/src/ui/player.dart`；
Test: `test/core/engine_test.dart`（增补）、`test/platform_impl/wiring_test.dart`（增补）、
`test/ui/player_fit_test.dart`。

**Produces：**

```dart
// MovaEngine / createMovaEngine
/// - [fit]: the initial `MovaState.fit`; defaults to [MovaFit.contain]. This is
///   a starting value, not a lock — `setFit()` and the fit button still change
///   it at runtime / 初始的 `MovaState.fit`，默认 [MovaFit.contain]。只是初值不是
///   锁定——运行时 `setFit()` 与 fit 按钮照常可改
MovaFit fit = MovaFit.contain,

// MovaPlayer
/// Declarative fit for [api]. `null` leaves the engine untouched. Otherwise it
/// is applied when this widget mounts and again only when this value changes
/// (or [api] changes) — a user's fit-button choice survives unrelated rebuilds
/// until the parent passes a *different* fit.
///
/// [api] 的声明式填充模式。`null` 表示不碰引擎。否则在本组件挂载时应用一次，之后
/// 只有该值变化（或换了 [api]）才再应用——用户用 fit 按钮选的值在无关重建中保留，
/// 直到父组件传入一个**不同的** fit。
///
/// Example / 示例:
/// ```dart
/// MovaPlayer(api: engine, fit: MovaFit.cover)
/// ```
final MovaFit? fit;
```

`_MovaPlayerState`：`initState` 与 `didUpdateWidget` 里调用

```dart
void _applyFit({MovaFit? previous, bool apiChanged = false}) {
  final f = widget.fit;
  if (f == null) return;
  if (!apiChanged && previous == f) return;
  if (widget.api.state.fit != f) widget.api.setFit(f);
}
```

**断言（8）：**
1. `MovaEngine(kernel: FakeKernel())` → `state.fit == contain`（默认不变）。
2. `MovaEngine(kernel:, fit: cover)` → `state.fit == cover`，且构造后事件流里没有 `MovaFitChange`。
3. `createMovaEngine(kernel: FakeKernel(), fit: MovaFit.cover)` → `cover`。
4. `MovaPlayer(fit: cover)` 挂载 → `FakeMovaApi.lastFit == cover`，`calls` 里 `setFit` 恰 1 次。
5. 同 `fit` 父组件重建 → `setFit` 次数不增（用户改动不被覆盖）。
6. `fit` 从 `cover` 改为 `fill` → 再调一次，`lastFit == fill`。
7. `fit: null` → 从不调 `setFit`。
8. 换一个新的 `FakeMovaApi`、`fit` 不变 → 新 api 收到 `setFit(cover)`。

**验收：** 测试 **1048**。

---

## Task 5：内置封面——`MovaPlayer(poster:, posterFade:)` ✅ 已完成（实测 +7，累计 1055）

**Files:** Create `lib/src/ui/poster.dart`；Modify `lib/src/ui/player.dart`；
Test: `test/ui/poster_test.dart`。

**Produces：**

```dart
/// A widget painted over the video surface until the current source shows
/// its first frame, then faded out; re-covers instantly on every source
/// change. Sits *under* the skin's chrome (buffering spinner, error, bars).
/// Stays visible for sources/engines without a picture (audio-only).
/// `null` (the default) adds nothing to the tree.
///
/// 盖在视频画面上的组件，当前源出首帧后淡出；每次换源立即重新盖上。位于皮肤
/// chrome（缓冲转圈、错误层、控制条）**之下**。没有画面的源/引擎（仅音频）时
/// 常驻。默认 `null`，不向树中添加任何节点。
///
/// Example / 示例:
/// ```dart
/// MovaPlayer(api: engine, poster: Image.network(coverUrl, fit: BoxFit.cover))
/// ```
final Widget? poster;

/// How long the poster takes to fade out; re-covering is always instant.
///
/// 封面淡出的时长；重新盖上始终是瞬间完成。
final Duration posterFade; // 默认 const Duration(milliseconds: 300)
```

```dart
// poster.dart（不导出）
class MovaPosterLayer extends StatelessWidget {
  const MovaPosterLayer({super.key, required this.poster, required this.fade});
  final Widget poster;
  final Duration fade;

  @override
  Widget build(BuildContext context) {
    return MovaSelect<bool>(
      selector: (s) => !(s.rendered && s.width > 0 && s.height > 0),
      builder: (context, shown) => IgnorePointer(
        child: AnimatedOpacity(
          opacity: shown ? 1 : 0,
          duration: shown ? Duration.zero : fade,
          child: poster,
        ),
      ),
    );
  }
}

// player.dart build() 中：
final surface = widget.surface ?? const _RenderSurface();
final video = widget.poster == null
    ? surface
    : Stack(fit: StackFit.expand, children: [surface, MovaPosterLayer(poster: widget.poster!, fade: widget.posterFade)]);
final assembled = widget.skin.assemble(context, bundle, video);
```

**断言（7）：**
1. `poster: null` → 树中没有 `MovaPosterLayer`，`skin.assemble` 收到的 `video` 就是原渲染面（用记录型测试皮肤捕获 `video` 参数）。
2. 挂载时封面的 `AnimatedOpacity.opacity == 1`。
3. 推 `MovaState(rendered: true, width: 1280, height: 720)` → `opacity == 0`，`duration == posterFade`；`pump(300ms)` 后封面不再绘制。
4. `rendered: true` 但 `width == 0` → 仍 `opacity == 1`。
5. 再推 `rendered: false` → `opacity == 1` 且 `duration == Duration.zero`。
6. 封面被 `IgnorePointer` 包裹。
7. 封面是 `skin.assemble` 收到的 `video` 的后代（证明 chrome 在其之上）。

**验收：** `test/ui/player_test.dart`/`skin_test.dart`（含"恰好 3 个 RepaintBoundary"）原样通过；测试 **1055**。

---

## Task 6：feed 引擎池接入评估与 opt-in——`MovaFeedPlayer(posterUntilFirstFrame:)` ✅ 已完成（实测 +3，累计 1058）

**评估结论：** 池的 `MovaFeedSlot.ready`（= `open()` resolve）**语义不改**，core 的 `MovaFeedEnginePool`
一行不动。原因：① 改语义会让 placeholder 显示得更久，是可见行为变化；② 预热邻居是 `autoPlay:false`
打开的，没有原生泵时只能靠尺寸兜底（D1），有泵时依赖"暂停态 mpv 是否发 RESTART"——这一点尚未真机确认
（Task 16 V2）。所以只在 UI 层给一个默认关闭的开关：`ready` 之后照常挂真实画面，但把 placeholder 当
**封面**传给 `MovaPlayer(poster:)`，由 `rendered` 决定何时淡出——这正好消除"open 已完成、首帧未到"那段
黑屏。默认 `false`，行为与今天逐字节相同。是否本期做见 Q7。

**Files:** Modify `lib/src/ui/feed_player.dart`；Test: `test/ui/feed_player_test.dart`（增补）。

```dart
/// When true, a ready page keeps showing [placeholderBuilder] as a poster
/// over the live surface until that engine reports its first frame
/// (`MovaState.rendered`). Default `false`: the placeholder disappears the
/// moment `open()` resolves, exactly as before.
///
/// 为 true 时，已就绪的页面会把 [placeholderBuilder] 作为封面继续盖在真实画面上，
/// 直到该引擎报告首帧（`MovaState.rendered`）。默认 `false`：`open()` 一完成占位就
/// 消失，与之前完全相同。
final bool posterUntilFirstFrame;
```

`_buildPage`（`feed_player.dart:265-294`）：`slot.ready && posterUntilFirstFrame` 时
`MovaPlayer(api: slot.api, skin: skin, autoLoadQualities: false, poster: placeholder)`。

**断言（3）：** 默认 `false` 时就绪页无 `MovaPosterLayer`；`true` 且未渲染时就绪页的封面是 placeholder
且 `opacity == 1`；该引擎推 `rendered+尺寸` 后 `opacity == 0`。

**验收：** 既有 `feed_player_test.dart`/`douyin_skin_test.dart` 原样通过；测试 **1058**。

---

## Task 7：极简皮肤 `MovaMinimalSkin` + 缓冲指示主题 ✅ 已完成（实测 +7，累计 1065）

**Files:** Create `lib/src/ui/skins/minimal_skin.dart`；Modify `lib/src/core/options/theme.dart`、
`lib/src/ui/components/overlays.dart`、`lib/mova.dart`；Test: `test/ui/minimal_skin_test.dart`、
`test/core/options_test.dart`（增补）。

**Produces：**

```dart
/// A chrome-free skin: just the picture plus an optional buffering spinner
/// (and optionally the error overlay). No gesture layer, no bars — taps fall
/// through to whatever wraps the player. For preview cards, live tiles and
/// backgrounds.
///
/// 无 chrome 的皮肤：只有画面加可选的缓冲转圈（以及可选的错误层）。不挂手势层、
/// 不挂任何栏——点击会落到包住播放器的外层组件上。适用于预览卡片、直播小窗格、
/// 背景视频。
///
/// Example / 示例:
/// ```dart
/// MovaPlayer(
///   api: engine,
///   skin: const MovaMinimalSkin(),
/// )
/// // spinner style comes from MovaOpts.theme / 转圈样式来自 MovaOpts.theme:
/// createMovaEngine(options: const MovaOpts(
///   theme: MovaTheme(bufferingSize: 24, bufferingStrokeWidth: 2, bufferingColor: 0xFFFFFFFF),
/// ));
/// ```
class MovaMinimalSkin implements MovaSkin {
  /// Creates the skin.
  ///
  /// 创建皮肤。
  ///
  /// - [showBuffering]: show the spinner while buffering, default true / 缓冲时显示转圈，默认 true
  /// - [showError]: show the error overlay with its retry button, default false / 显示带重试按钮的错误层，默认 false
  const MovaMinimalSkin({this.showBuffering = true, this.showError = false});

  final bool showBuffering;
  final bool showError;

  @override
  List<MovaComponent> components() => [
        if (showBuffering) MovaBufferingComponent(),
        if (showError) MovaErrorComponent(),
      ];

  @override
  Widget assemble(BuildContext context, MovaSlotBundle slots, Widget video) => Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: video),
          Positioned.fill(child: Stack(children: slots[MovaSlot.center])),
        ],
      );
}
```

```dart
// theme.dart 新增（全部可空，null = 沿用今天的行为）
/// Spinner diameter; `null` keeps the Material default.
///
/// 转圈直径；`null` 沿用 Material 默认值。
final double? bufferingSize;

/// Spinner stroke width; `null` keeps the Material default.
///
/// 转圈线宽；`null` 沿用 Material 默认值。
final double? bufferingStrokeWidth;

/// Spinner ARGB color; `null` falls back to [accentColor].
///
/// 转圈的 ARGB 颜色；`null` 时回落到 [accentColor]。
final int? bufferingColor;
```

`MovaBufferingComponent.build`：

```dart
final indicator = CircularProgressIndicator(
  color: Color(theme.bufferingColor ?? theme.accentColor),
  strokeWidth: theme.bufferingStrokeWidth, // Flutter 3.47 该参数可空，null 走主题默认；落地时以 SDK 签名为准
);
final size = theme.bufferingSize;
return Center(child: size == null ? indicator : SizedBox.square(dimension: size, child: indicator));
```

**断言（7）：**
1. `components()` 默认只有 `buffering`；`showBuffering:false` 为空；`showError:true` 含 `error`。
2. 挂 `MovaMinimalSkin` 时树中没有 `MovaGestureLayerComponent` 产出的手势层、没有顶/底栏。
3. `buffering: true` 显示 `CircularProgressIndicator`，`false` 不显示。
4. 主题三字段生效：`SizedBox` 尺寸 24、`strokeWidth == 2`、颜色白。
5. 默认主题下 `MovaBufferingComponent` 的指示器颜色 = `accentColor` 且外层**没有** `SizedBox`（默认皮肤零变化）。
6. `MovaTheme` 的 `==`/`hashCode` 覆盖三新字段；默认值均 `null`。
7. 外层 `GestureDetector` 包住 `MovaPlayer(skin: MovaMinimalSkin())` 时，点击画面能触发外层 `onTap`。

**验收：** 测试 **1065**。

---

## Task 8：声明式组件 `MovaView` + `MovaSource.sameAs` ✅ 已完成（实测 +13，累计 1078）

**Files:** Create `lib/src/ui/view.dart`；Modify `lib/src/core/model/source.dart`、`lib/mova.dart`；
Test: `test/core/model_test.dart`（增补）、`test/ui/view_test.dart`。

**Produces：**

```dart
// source.dart
/// Whether [other] would play the same media: same uri and type (and, once
/// alternatives exist, the same alternatives in the same order). The title
/// is ignored — a renamed source is not worth reopening.
///
/// [other] 是否会播放同一份媒体：uri 与 type 相同（有备选地址后还要求备选相同且
/// 顺序一致）。标题不参与比较——只改了名字不值得重开流。
///
/// Example / 示例:
/// ```dart
/// const MovaSource('https://a/live.flv').sameAs(const MovaSource('https://a/live.flv', title: 'x')); // true
/// ```
bool sameAs(MovaSource other) => uri == other.uri && type == other.type;
```

```dart
/// Builds an engine for [MovaView] from the view's [MovaOpts].
///
/// 依据 [MovaView] 的 [MovaOpts] 构建引擎。
typedef MovaViewEngineFactory = MovaApi Function(MovaOpts options);

/// A declarative player: give it a [source] and it owns the whole engine
/// lifecycle — created lazily on the first non-null source, reopened only
/// when the source really changes ([MovaSource.sameAs]), recreated when
/// [options] change, paused when the source goes null, disposed with the
/// widget. The imperative API (`createMovaEngine` + `MovaPlayer`) is unchanged
/// and still the way to go when you need to hand an engine around.
///
/// 声明式播放器：给它一个 [source]，它就接管整个引擎生命周期——第一次拿到非空源
/// 时懒创建、只有源真正变了（[MovaSource.sameAs]）才重开、[options] 变化时重建、
/// 源变为 null 时暂停、随组件销毁一并释放。命令式 API（`createMovaEngine` +
/// `MovaPlayer`）不变，需要把引擎传来传去时仍然用它。
///
/// Example / 示例:
/// ```dart
/// MovaView(
///   source: url == null ? null : MovaSource(url, type: MovaStreamType.live),
///   fit: MovaFit.cover,
///   poster: Image.network(cover, fit: BoxFit.cover),
///   skin: const MovaMinimalSkin(),
/// )
/// ```
class MovaView extends StatefulWidget {
  const MovaView({
    super.key,
    required this.source,
    this.autoPlay = true,
    this.fit,
    this.poster,
    this.posterFade = const Duration(milliseconds: 300),
    this.skin = const MovaDefaultSkin(),
    this.options = const MovaOpts(),
    this.engineFactory,
    this.autoLoadQualities = true,
    this.onEngine,
    this.onOpenError,
    // Task 13 追加：this.autoPause, this.routeObserver
  });

  /// What to play; `null` shows only the poster (or black).
  ///
  /// 要播放的源；`null` 时只显示封面（或黑底）。
  final MovaSource? source;
  /// Whether a newly opened source starts playing; changes apply to the next open only.
  ///
  /// 新打开的源是否立即播放；改动只影响下一次打开。
  final bool autoPlay;
  final MovaFit? fit;               // 见 MovaPlayer.fit（D3）
  final Widget? poster;             // 见 MovaPlayer.poster（D4）
  final Duration posterFade;
  final MovaSkin skin;
  /// Construction-time engine options; a different value recreates the engine.
  ///
  /// 引擎构造期配置；传入不同的值会重建引擎。
  final MovaOpts options;
  /// Builds the engine; defaults to `createMovaEngine(options: o, preciseFirstFrame: poster != null)`
  /// (Q1). Changing it after mount has no effect.
  ///
  /// 构建引擎；默认见上（Q1）。挂载后更换它不会生效。
  final MovaViewEngineFactory? engineFactory;
  final bool autoLoadQualities;
  /// Called with each engine right after it is created (and after a recreate),
  /// for hosts that need events or imperative calls.
  ///
  /// 每个引擎创建（及重建）后立即回调，供需要监听事件或命令式调用的宿主使用。
  final void Function(MovaApi api)? onEngine;
  /// Receives an `open()` failure; `null` reports it via `FlutterError.reportError`.
  ///
  /// 接收 `open()` 的失败；为 `null` 时经 `FlutterError.reportError` 上报。
  final void Function(Object error, StackTrace stack)? onOpenError;
}
```

`_MovaViewState` 核心：

```dart
MovaApi? _engine;
MovaSource? _opened;

@override
void initState() { super.initState(); _sync(); }

@override
void didUpdateWidget(MovaView old) {
  super.didUpdateWidget(old);
  if (_engine != null && widget.options != old.options) {
    final dead = _engine!;
    _engine = null;
    _opened = null;
    unawaited(dead.dispose());
  }
  _sync();
}

void _sync() {
  final src = widget.source;
  if (src == null) {
    if (_opened != null) unawaited(_engine?.pause());
    _opened = null;
    return;
  }
  if (_opened != null && _opened!.sameAs(src)) return;
  final engine = _engine ??= _create();
  _opened = src;
  unawaited(engine.open(src, autoPlay: widget.autoPlay).then((_) {
    if (widget.autoLoadQualities && identical(_engine, engine)) return engine.loadQualities();
  }).catchError(_reportOpenError));
}

@override
Widget build(BuildContext context) {
  final engine = _engine;
  if (engine == null || widget.source == null) return _posterOrBlack();
  return MovaPlayer(
    api: engine, skin: widget.skin, fit: widget.fit,
    poster: widget.poster, posterFade: widget.posterFade, autoLoadQualities: false,
  );
}

@override
void dispose() { final e = _engine; _engine = null; if (e != null) unawaited(e.dispose()); super.dispose(); }
```

`MovaPlayer` 自带 `KeyedSubtree(ValueKey(api))`（`player.dart:137-138`），引擎重建时整棵子树会重挂，
无需 `MovaView` 额外处理。文档注明：`MovaView` 拥有的引擎**不要**交给 `MovaMini` 跨路由持有（view 销毁时
会被 dispose，触发 `dispose()` 里的 mini assert）。

**断言（13）：**
- `sameAs`（3）：同 uri/type 不同 title → true；不同 uri → false；不同 type → false。
- `MovaView`（10，用 `engineFactory: (_) => FakeMovaApi()` 或 `MovaEngine(kernel: FakeKernel())`）：
  1. `source: null` → 工厂未被调用，显示封面。
  2. 有源 → 工厂恰 1 次，`open` 收到该 uri 与 `autoPlay`。
  3. 新实例但 `sameAs` 的源 → 不再 `open`。
  4. 换不同 uri → 同一引擎再 `open`（工厂仍 1 次）。
  5. 源变 `null` → `pause` 被调，显示封面。
  6. `options` 变化 → 旧引擎 `disposed == true`，工厂 2 次，新引擎重开当前源。
  7. 组件卸载 → 引擎 `dispose`。
  8. `fit: cover` 透传 → 引擎 `setFit(cover)`。
  9. `open` 抛异常（`FakeMovaApi.openThrows`）→ `onOpenError` 收到，测试无未捕获异常。
  10. `autoLoadQualities: true` → `loadQualities` 在 `open` **之后**被调用（`calls` 顺序）。

**验收：** 测试 **1078**。

---

## Task 9：起播/卡顿超时与恢复——配置、失败值对象、策略、看门狗（纯逻辑） ✅ 已完成（实测 +20，累计 1098）

**Files:** Create `lib/src/core/options/recovery_config.dart`、`lib/src/core/recovery/fail.dart`、
`lib/src/core/recovery/watchdog.dart`；Modify `lib/src/core/options/options.dart`（`recovery` 节，
`copyWith`/`==`/`hashCode`）、`lib/mova.dart`（导出 `fail.dart`；watchdog 不导出）；
Test: `test/core/recovery/config_test.dart`、`policy_test.dart`、`watchdog_test.dart`。

**Produces：**

```dart
/// Start-up/stall timeouts and how to recover from them. Off by default:
/// with [enabled] false no timer is created, no stream is subscribed and
/// `open()` failures still throw to the caller exactly as before.
///
/// 起播/卡顿超时以及如何从中恢复。默认关闭：[enabled] 为 false 时不创建任何计时器、
/// 不订阅任何流，`open()` 的失败也照旧抛给调用方。
///
/// Example / 示例:
/// ```dart
/// createMovaEngine(options: const MovaOpts(
///   recovery: MovaRecoveryConfig(enabled: true, startTimeout: Duration(seconds: 8)),
/// ));
/// ```
class MovaRecoveryConfig {
  /// Master switch. 总开关。
  final bool enabled;
  /// Longest wait from an attempt being armed (while playback is intended) to
  /// its first frame. 一次尝试（在播放意图为真时）从武装到首帧的最长等待。
  final Duration startTimeout;
  /// Longest continuous buffering after the first frame while playing; `null`
  /// disables the stall watchdog. 出首帧后、播放中连续缓冲的最长时长；`null` 关闭卡顿看门狗。
  final Duration? stallTimeout;
  /// Whether a live source reaching its end counts as a failure (default true).
  /// 直播源走到结尾是否算失败（默认 true）。
  final bool liveEndIsFailure;
  /// Injectable recovery rule; `null` selects [MovaRetryThenFailover].
  /// 可注入的恢复规则；`null` 选用 [MovaRetryThenFailover]。
  final MovaRecoveryPolicy? policy;

  const MovaRecoveryConfig({
    this.enabled = false,
    this.startTimeout = const Duration(seconds: 10),
    this.stallTimeout = const Duration(seconds: 10),
    this.liveEndIsFailure = true,
    this.policy,
  });

  /// The policy actually in effect. 实际生效的策略。
  MovaRecoveryPolicy get effectivePolicy => policy ?? const MovaRetryThenFailover();

  /// Debug-checks the timeouts are positive; called by the engine on construction.
  /// debug 下检查超时为正；由引擎构造时调用。
  void assertValid() { assert(startTimeout > Duration.zero); assert(stallTimeout == null || stallTimeout! > Duration.zero); }

  MovaRecoveryConfig copyWith({...});
  // == / hashCode
}
```

```dart
/// What went wrong with a playback attempt. 一次播放尝试出了什么问题。
enum MovaPlayFailKind { openThrew, startTimeout, stallTimeout, nativeEndError, liveEnded }

/// One playback failure, fed to a [MovaRecoveryPolicy]. A plain value so the
/// recovery rule is testable without any player.
///
/// 一次播放失败，喂给 [MovaRecoveryPolicy]。纯值对象，使恢复规则无需播放器即可测试。
class MovaPlayFail {
  final MovaPlayFailKind kind;
  /// Index into `MovaSource.uris` of the failing address. 失败地址在 `MovaSource.uris` 里的下标。
  final int sourceIndex;
  final String uri;
  /// How many addresses the source has (1 + alternatives). 源一共有几个地址（1 + 备选数）。
  final int sourceCount;
  /// Consecutive failures on this address since the last first frame, from 1.
  /// 自上次出首帧以来该地址的连续失败次数，从 1 起。
  final int attempt;
  /// Consecutive failures across all addresses since the last first frame.
  /// 自上次出首帧以来跨所有地址的连续失败次数。
  final int streak;
  /// Whether this source had shown a frame before failing (a mid-stream failure).
  /// 失败前本源是否出过画面（即播放中途失败）。
  final bool afterFirstFrame;
  /// How long the attempt or stall lasted before it was declared failed.
  /// 判定失败前这次尝试/卡顿持续了多久。
  final Duration waited;
  final Object? error;
  /// Whether an untried address remains after this one. 当前地址之后是否还有备选。
  bool get hasNextSource => sourceIndex + 1 < sourceCount;
  const MovaPlayFail({...});
}

/// What the engine does next. 引擎接下来要做什么。
enum MovaRecoveryAction { retry, failover, giveUp }

/// A policy's answer: an action plus how long to wait before acting.
/// 策略的答复：一个动作，加上执行前等多久。
class MovaRecoveryDecision {
  final MovaRecoveryAction action;
  final Duration delay;
  const MovaRecoveryDecision.retry({this.delay = Duration.zero}) : action = MovaRecoveryAction.retry;
  const MovaRecoveryDecision.failover({this.delay = Duration.zero}) : action = MovaRecoveryAction.failover;
  const MovaRecoveryDecision.giveUp() : action = MovaRecoveryAction.giveUp, delay = Duration.zero;
}

/// Decides how to recover from a playback failure. The playback-side twin of
/// [MovaAdFailPolicy]: pure and injectable, so hosts with their own retry
/// budgets replace it wholesale.
///
/// 判定如何从一次播放失败中恢复。是播放侧的 [MovaAdFailPolicy]：纯粹、可注入，
/// 有自己重试预算的宿主可以整体替换。
abstract class MovaRecoveryPolicy {
  MovaRecoveryDecision onFailure(MovaPlayFail fail);
}

/// Retries each address [maxRetries] times after [retryDelay], then moves to
/// the next alternative, then gives up. The default.
///
/// 每个地址等 [retryDelay] 后重试 [maxRetries] 次，再切下一个备选，全部用完则放弃。默认策略。
///
/// Example / 示例:
/// ```dart
/// const MovaRecoveryConfig(enabled: true, policy: MovaRetryThenFailover(maxRetries: 2));
/// ```
class MovaRetryThenFailover implements MovaRecoveryPolicy {
  final int maxRetries;          // 默认 1
  final Duration retryDelay;     // 默认 1s
  const MovaRetryThenFailover({this.maxRetries = 1, this.retryDelay = const Duration(seconds: 1)});
  @override
  MovaRecoveryDecision onFailure(MovaPlayFail f) => f.attempt <= maxRetries
      ? MovaRecoveryDecision.retry(delay: retryDelay)
      : f.hasNextSource ? const MovaRecoveryDecision.failover() : const MovaRecoveryDecision.giveUp();
}

/// Never retries the same address: next alternative, else give up.
/// 从不重试同一地址：有备选就切，否则放弃。
class MovaFailoverOnly implements MovaRecoveryPolicy { ... }

/// The error placed in `MovaState.error` once recovery gives up.
/// recovery 放弃后写入 `MovaState.error` 的错误。
class MovaGiveUpError implements Exception {
  final MovaPlayFail last;
  const MovaGiveUpError(this.last);
  @override
  String toString() => 'MovaGiveUpError(${last.kind.name}, ${last.uri})';
}
```

```dart
/// Arms start-up and stall deadlines for one engine. Owns its timers; the
/// engine feeds it playback observations and receives timeouts.
///
/// 为一个引擎武装起播与卡顿期限。自持计时器；引擎喂播放观测、接收超时回调。
class MovaPlayWatchdog {
  MovaPlayWatchdog({required Duration startTimeout, Duration? stallTimeout,
      required void Function(MovaPlayFailKind kind, Duration waited) onTimeout});
  /// New attempt; the start deadline runs only while [playing] intent is true.
  /// 新的一次尝试；起播期限只在播放意图为真时计时。
  void armStart({required bool playing});
  /// Playing intent changed: pauses/resumes (restarts) the running deadline.
  /// 播放意图变化：暂停/恢复（从头重计）正在计的期限。
  void onPlaying(bool playing);
  /// The attempt showed its first frame: stop the start deadline, watch stalls.
  /// 本次尝试出了首帧：停掉起播期限，转入卡顿监视。
  void onLanded();
  /// Buffering flag while running: true starts the stall deadline, false clears it.
  /// 运行中的缓冲标志：true 起卡顿期限，false 清除。
  void onBuffering(bool buffering);
  /// Stops all deadlines until the next [armStart]. 停掉所有期限，直到下一次 [armStart]。
  void disarm();
  void dispose();
}
```

**断言（19）：**
- config（4）：默认值全覆盖（`enabled:false`、10s、10s、`liveEndIsFailure:true`、`policy:null`）；
  `effectivePolicy` 默认是 `MovaRetryThenFailover`；`copyWith` 单字段替换；`MovaOpts().recovery ==
  const MovaRecoveryConfig()` 且 `MovaOpts.copyWith(recovery:)` 不影响其他节；`assertValid()` 对 0 超时触发 assert。
- policy（7）：默认策略 attempt=1 → retry(1s)；attempt=2 且有备选 → failover；attempt=2 无备选 → giveUp；
  `maxRetries:0` 首次就 failover；`MovaFailoverOnly` 有/无备选两种；`MovaGiveUpError.toString` 含 kind 与 uri。
- watchdog（8，`fake_async`）：`armStart(playing:true)` 到 `startTimeout` 回调 `startTimeout`、`waited ≈ startTimeout`；
  `onLanded` 在期限前 → 不回调；`armStart(playing:false)` 永不回调，`onPlaying(true)` 后从头计；
  计时中 `onPlaying(false)` → 不回调；落地后 `onBuffering(true)` 持续 `stallTimeout` → `stallTimeout`；
  中途 `onBuffering(false)` → 不回调；`stallTimeout: null` 从不回调卡顿；`disarm()`/`dispose()` 后推进时间不回调。

**验收：** 纯 Dart，`purity_test` 通过；测试 **1097**。

---

## Task 10：恢复接线进引擎（重试/放弃/事件，`openThrew` 捕获） ✅ 已完成（实测 +14，累计 1112）

**Files:** Modify `lib/src/core/engine.dart`、`lib/src/core/events/events.dart`、
`test/support/fake_kernel.dart`（加 `Object? openError`，非空时 `open()` 抛它）；
Test: `test/core/recovery/engine_recovery_test.dart`。

**新事件：**

```dart
/// A playback attempt failed and recovery decided what to do. Only fires
/// when `MovaRecoveryConfig.enabled`. Not an error by itself — `MovaState.error`
/// is set only once recovery gives up.
///
/// 一次播放尝试失败，recovery 已决定如何处理。仅在 `MovaRecoveryConfig.enabled`
/// 时触发。它本身不是错误——只有 recovery 放弃时才写 `MovaState.error`。
///
/// Example / 示例:
/// ```dart
/// api.events.listen((e) {
///   if (e is MovaPlayFailure && e.fail.kind == MovaPlayFailKind.startTimeout) showToast('连接超时，正在重试…');
/// });
/// ```
class MovaPlayFailure extends MovaEvent {
  final MovaPlayFail fail;
  final MovaRecoveryAction action;
  const MovaPlayFailure(this.fail, this.action);
}

/// Playback showed a frame again after [attempts] consecutive failures.
/// 连续失败 [attempts] 次之后重新出画面。
class MovaRecovered extends MovaEvent {
  final int attempts;
  const MovaRecovered(this.attempts);
}
```

**引擎改动草图：**

```dart
MovaPlayWatchdog? _watchdog;            // 仅 options.recovery.enabled 时非空
StreamSubscription<MovaEndFileReason>? _endFileSub;
Timer? _recoverTimer;
int _attemptId = 0, _failedAttemptId = -1, _streak = 0;
final Map<int, int> _addrFailures = <int, int>{};
bool _readyAnnounced = false;

// 构造期
final rec = options.recovery;
if (rec.enabled) {
  rec.assertValid();
  _watchdog = MovaPlayWatchdog(
    startTimeout: rec.startTimeout,
    stallTimeout: rec.stallTimeout,
    onTimeout: (kind, waited) => _onPlayFail(kind, waited: waited),
  );
  final k = _kernel;
  if (k is MovaStatsProbe) {
    _endFileSub = (k as MovaStatsProbe).endFiles.listen((r) {
      if (r == MovaEndFileReason.error) _onPlayFail(MovaPlayFailKind.nativeEndError);
    });
  }
}

// _armAttempt 追加：_attemptId++; _watchdog?.armStart(playing: autoPlay);
// _playingSub 追加：_watchdog?.onPlaying(v);
// _bufferingSub 追加：_watchdog?.onBuffering(v);
// _completedSub 追加：if (v && state.type == MovaStreamType.live && options.recovery.liveEndIsFailure) _onPlayFail(MovaPlayFailKind.liveEnded);
// _onAttemptLanded 追加（在 rendered 判断之前）：
//   _watchdog?.onLanded();
//   if (_streak > 0) { _events.add(MovaRecovered(_streak)); _streak = 0; _addrFailures.clear(); }

void _onPlayFail(MovaPlayFailKind kind, {Object? error, Duration waited = Duration.zero}) {
  final wd = _watchdog;
  final src = _source;
  if (wd == null || src == null || _events.isClosed) return;
  if (_failedAttemptId == _attemptId) return;   // 同一次尝试只处理一次
  _failedAttemptId = _attemptId;
  wd.disarm();
  final idx = _sourceIndex;                     // Task 11 前恒为 0
  final fail = MovaPlayFail(
    kind: kind, sourceIndex: idx, uri: _activeUri, sourceCount: src.uris.length,
    attempt: _addrFailures[idx] = (_addrFailures[idx] ?? 0) + 1, streak: ++_streak,
    afterFirstFrame: state.rendered, waited: waited, error: error,
  );
  var d = _decide(fail);                        // try/catch：策略抛异常 → giveUp
  if (d.action == MovaRecoveryAction.failover && !fail.hasNextSource) d = const MovaRecoveryDecision.giveUp();
  _events.add(MovaPlayFailure(fail, d.action));
  switch (d.action) {
    case MovaRecoveryAction.retry:    _scheduleRecover(idx, d.delay, fail);
    case MovaRecoveryAction.failover: _scheduleRecover(idx + 1, d.delay, fail);
    case MovaRecoveryAction.giveUp:   _giveUp(fail);
  }
}

void _scheduleRecover(int index, Duration delay, MovaPlayFail cause) {
  final gen = _openGen;
  _recoverTimer?.cancel();
  _recoverTimer = Timer(delay, () => unawaited(_recover(index, cause, gen)));
}

Future<void> _recover(int index, MovaPlayFail cause, int gen) async {
  if (gen != _openGen || _events.isClosed) return;
  final resumeAt = state.type == MovaStreamType.vod && cause.afterFirstFrame ? _lastPosition : Duration.zero;
  // Task 11：index != _sourceIndex 时切换地址、清 qualities、发 MovaFailover
  _forgetMediaProgress();
  _abrPolicy.reset();
  _state.emit(state.copyWith(duration: Duration.zero));
  _armAttempt(autoPlay: true);
  try {
    await _loadKernel(_activeUri, play: true);
  } catch (e) {
    if (gen == _openGen) _onPlayFail(MovaPlayFailKind.openThrew, error: e);
    return;
  }
  if (gen != _openGen || _events.isClosed) return;
  _announceReady();                             // 本会话首次成功时发 MovaSourceChange + MovaReady
  if (resumeAt > Duration.zero) await _seekOrPark(resumeAt);
}

void _giveUp(MovaPlayFail fail) {
  final err = MovaGiveUpError(fail);
  _state.emit(state.copyWith(error: err));
  _events.add(MovaErrorEvent(err));
  _chain.onError(err, StackTrace.current);
  unawaited(_kernel.pause());
}
```

`open()` 改动：开头（世代号检查之后）`_recoverTimer?.cancel(); _addrFailures.clear(); _streak = 0;
_readyAnnounced = false; _failedAttemptId = -1;`；内核 open 处：

```dart
try {
  await _loadKernel(source.uri, play: autoPlay);
} catch (e) {
  if (_watchdog == null) rethrow;                       // 关闭态：行为与今天逐字节相同
  if (gen == _openGen) _onPlayFail(MovaPlayFailKind.openThrew, error: e);
  return;
}
```

尾部 `MovaSourceChange`/`MovaReady` 改为 `_announceReady()`（只发一次）。`dispose()`：与 Task 2 同理，
**在第一个 `await` 之前同步** `_recoverTimer?.cancel()` + `_watchdog?.dispose()`，之后再取消 `_endFileSub`。

**断言（14，`fake_async` + `FakeKernel`/`FakeStatsKernel`）：**
1. `enabled:false`（默认）：`FakeKernel.openError` 非空时 `open()` 照旧抛出；不产生任何 `MovaPlayFailure`。
2. 开启：`open()` 后无首帧，推进 `startTimeout` → `MovaPlayFailure(startTimeout, attempt 1, action retry)`；再推进 1s → 内核第二次 `open` 同一 uri。
3. 第二次仍超时 → `MovaPlayFailure(..., giveUp)` + `state.error is MovaGiveUpError` + 恰好一条 `MovaErrorEvent` + 内核收到 `pause`。
4. 期限内首帧落地 → 推进远超期限，无失败。
5. `open(autoPlay:false)` → 推进远超期限，无失败；`play()`（内核发 `playing:true`）后从头计时。
6. 落地后 `buffering:true` 持续 `stallTimeout` → `stallTimeout`；点播源重试后续播 seek 到失败前位置（寄存或 `lastSeek`）。
7. 卡顿中暂停（`emitPlaying(false)`）→ 无失败。
8. 开启时 `openError` → `open()` **正常完成**（不抛），`MovaPlayFailure(openThrew)`，随后重试成功并发出 `MovaReady`（只一次）。
9. 直播 `completed:true` → `liveEnded`；`liveEndIsFailure:false` 时不触发。
10. `FakeStatsKernel.emitEndFile(error)` → 立即 `nativeEndError`（不等超时）；`emitEndFile(stop)` 不触发。
11. 重试延迟中再次 `open()` 新源 → 旧的重试不再执行（内核 `open` 次数与 uri 断言）。
12. 失败后重新落地 → `MovaRecovered(1)`，之后再失败 `attempt` 从 1 计。
13. 自定义策略抛异常 → 按 `giveUp` 处理，引擎不抛。
14. `dispose()` 发生在重试延迟中 → 推进时间无异常、无事件。

**验收：** 既有 1008+ 项全部原样通过（关闭态零改变由断言 1 锚定）；测试 **1111**。

---

## Task 11：多地址兜底——`MovaSource.alternatives`、`MovaState.sourceIndex`、`MovaFailover` ✅ 已完成（实测 +12，累计 1124）

**Files:** Modify `lib/src/core/model/source.dart`、`lib/src/core/state/state.dart`、
`lib/src/core/events/events.dart`、`lib/src/core/engine.dart`；
Test: `test/core/model_test.dart`（增补）、`test/core/recovery/failover_test.dart`。

**Produces：**

```dart
/// Fallback addresses tried in order after [uri] fails, when
/// `MovaOpts.recovery` is enabled (ignored otherwise). Order them yourself —
/// mova only promises to try them in the order given.
///
/// [uri] 失败后按顺序尝试的备选地址；仅在 `MovaOpts.recovery` 开启时使用（否则
/// 忽略）。顺序由宿主排好——mova 只保证按给定顺序尝试。
final List<String> alternatives;

/// [uri] followed by [alternatives]. [uri] 后接 [alternatives]。
List<String> get uris => [uri, ...alternatives];

/// Builds a source from candidate addresses: trims, drops empty/null and
/// duplicates keeping order; the first becomes [uri], the rest
/// [alternatives]. Returns null when nothing usable is left.
///
/// 用候选地址构建源：去首尾空白、剔除空串/null 与重复项并保持顺序；第一个作 [uri]，
/// 其余作 [alternatives]。一个可用的都没有时返回 null。
///
/// Example / 示例:
/// ```dart
/// MovaSource.pick(['', ' https://a ', 'https://b', 'https://a'], type: MovaStreamType.live);
/// // → MovaSource('https://a', alternatives: ['https://b'])
/// ```
static MovaSource? pick(Iterable<String?> candidates, {MovaStreamType type = MovaStreamType.vod, String? title});
```

`sameAs` 追加 `alternatives` 逐项相等。`MovaState.sourceIndex`（`int`，默认 0；`hashCode` 并入外层）。

```dart
/// Playback moved to another address of the same source.
///
/// 播放切到了同一个源的另一个地址。
class MovaFailover extends MovaEvent {
  /// Index (into `MovaSource.uris`) left behind. 被放弃的地址下标。
  final int from;
  /// Index now playing. 当前播放的地址下标。
  final int to;
  /// The address now playing. 当前播放的地址。
  final String uri;
  const MovaFailover({required this.from, required this.to, required this.uri});
}
```

引擎：
- `int _sourceIndex = 0;`、`String get _activeUri => _source?.uris[_sourceIndex] ?? '';`
- `open()`：`_sourceIndex = 0` 并在那次合并 emit 里带 `sourceIndex: 0`。
- `_recover()` 中 `index != _sourceIndex` 时：`from = _sourceIndex; _sourceIndex = index;
  _state.emit(state.copyWith(sourceIndex: index, qualities: const [], clearQuality: true));
  _events.add(MovaFailover(from: from, to: index, uri: _activeUri));`
- 读"当前地址"的四处改走 `_activeUri`：`loadQualities`（`engine.dart:1004`）、`switchQuality` auto 档
  （`1047`）、`_reopenLiveSource`（`1177`）、`_seekTimeshift` 的 `urlBuilder(src.uri, ...)`（`900`）。
  `reload()` 不改（`open(_source)` = 回主地址的新会话）。

**断言（12）：**
- 模型（5）：`alternatives` 默认空、`uris` 顺序；`pick` 去空/去重/保序；全空返回 `null`；`sameAs` 比较备选（顺序不同 → false）；`const MovaSource('x')` 仍可 const 构造。
- 引擎（7）：主地址起播超时（`MovaFailoverOnly`）→ 内核 `open` 备选、`state.sourceIndex == 1`、`MovaFailover(from:0,to:1,uri)`；切换后 `qualities` 清空；切到备选后 `backToLiveEdge`（reopen 分支）打开的是备选地址；`switchQuality(auto)` 用备选地址；新 `open()` 把 `sourceIndex` 归 0；`recovery.enabled:false` 时有备选也从不切换（超时不存在）；最后一个备选也失败 → `giveUp`，`MovaGiveUpError.last.sourceIndex == 末位`。

**验收：** 测试 **1123**。

---

## Task 12：自动暂停守卫纯逻辑——`MovaAutoPauseConfig` + `MovaAutoPauseGate` ✅ 已完成（实测 +12，累计 1136）

**Files:** Create `lib/src/core/guard/auto_pause.dart`；Modify `lib/mova.dart`；
Test: `test/core/guard/auto_pause_gate_test.dart`。

**Produces：**

```dart
/// Why a player mount is currently considered hidden.
/// 某个播放器挂载点当前被视为隐藏的原因。
enum MovaHideReason { offscreen, tickerOff, routeCovered, background }

/// How a live source resumes after being hidden.
/// 直播源隐藏后如何恢复。
enum MovaLiveResume {
  /// Plain `play()` from where it paused. 从暂停点普通续播。
  resume,
  /// Jump back to the live edge (`backToLiveEdge()`), then play.
  /// 回到直播边缘（`backToLiveEdge()`）再播放。
  reloadEdge,
}

/// Which visibility changes pause a player, and how it resumes. A pure value
/// used by the `MovaAutoPause` widget; not part of `MovaOpts` because it
/// describes one mount point, while an engine may be mounted twice (page and
/// mini window).
///
/// 哪些可见性变化会暂停播放器，以及如何恢复。供 `MovaAutoPause` 组件使用的纯值；
/// 不放进 `MovaOpts`，因为它描述的是某个挂载点，而一个引擎可能同时挂在两处（页面和
/// 小窗）。
///
/// Example / 示例:
/// ```dart
/// MovaAutoPause(api: engine, config: const MovaAutoPauseConfig(minVisibleFraction: 0.5), child: player)
/// ```
class MovaAutoPauseConfig {
  final bool viewport;                 // true：滚出视口
  /// Pause when the visible fraction is at or below this; 0 = only when fully off-screen.
  /// 可见比例小于等于此值时暂停；0 表示完全滚出才暂停。
  final double minVisibleFraction;     // 0.0
  final bool tickerMode;               // true：Offstage / 非活跃 Tab
  final bool route;                    // true：被其他路由盖住
  final bool background;               // true：应用进后台
  final bool resumeOnShow;             // true
  final MovaLiveResume liveResume;     // reloadEdge
  /// Hidden for less than this, a live source simply resumes. 隐藏不足此时长的直播源直接续播。
  final Duration liveResumeGrace;      // 3s
  const MovaAutoPauseConfig({...});
}

/// What the widget should do after a visibility change.
/// 可见性变化后组件应执行的动作。
enum MovaGuardAction { none, pause, resume, reloadEdge }

/// Pure decision core of the auto-pause guard.
/// 自动暂停守卫的纯决策核心。
class MovaAutoPauseGate {
  MovaAutoPauseGate(this.config);
  final MovaAutoPauseConfig config;
  /// Current hide reasons (filtered by [config]). 当前的隐藏原因（已按 [config] 过滤）。
  Set<MovaHideReason> get reasons;
  bool get hidden;
  /// Snapshots playing intent at the first sign of backgrounding (`inactive`).
  /// 在进后台的第一个迹象（`inactive`）时快照播放意图。
  void onInactive({required bool playing});
  /// Clears the inactive snapshot (`resumed` without ever hiding).
  /// 清掉 inactive 快照（未曾隐藏就回到 resumed）。
  void onResumed();
  /// Sets one reason on/off and returns the action to take.
  /// 置位/清除一个原因，返回应执行的动作。
  MovaGuardAction update(MovaHideReason reason, bool active,
      {required bool playing, required bool live, required bool exempt, required DateTime now});
}
```

**断言（12）：**
1. 可见 → `offscreen` 且在播 → `pause`；不在播 → `none`。
2. 隐藏 → 恢复，隐藏前在播 → `resume`；隐藏前没在播 → `none`。
3. 两个原因叠加：去掉一个仍隐藏 → `none`；全去掉 → `resume`。
4. `exempt: true`（pip/mini）→ 隐藏时 `none`，恢复时也不续播。
5. `resumeOnShow: false` → 恢复时 `none`。
6. 直播 + `reloadEdge` + 隐藏 ≥ `liveResumeGrace` → `reloadEdge`。
7. 直播隐藏不足 grace → `resume`。
8. 直播 + `MovaLiveResume.resume` → `resume`；点播一律 `resume`。
9. `onInactive(playing:true)` 后 `background` 到达时 `playing:false`（系统已自动暂停）→ 仍记为"隐藏前在播"，恢复 → `resume`。
10. `onInactive` 后 `onResumed()`（只拉了下通知栏）→ 快照清除，后续不受影响。
11. `config.viewport: false` 时 `offscreen` 原因被忽略（`hidden` 仍 false）。
12. 同一原因重复置位/清除是幂等的（不重复 pause/resume）。

**验收：** 纯 Dart，`purity_test` 通过；测试 **1135**。

---

## Task 13：守卫 widget `MovaAutoPause` + `MovaView.autoPause` ✅ 已完成（实测 +12，累计 1148）

> **落地偏差**：下文草图里的 `routeObserver`（单个）实际是 `routeObservers`（列表，每个 navigator 一个），原因见文首偏差清单。

**Files:** Create `lib/src/ui/guard/auto_pause.dart`；Modify `lib/src/ui/view.dart`、`lib/mova.dart`；
Test: `test/ui/auto_pause_test.dart`。

**Produces：**

```dart
/// Pauses [api] while [child] is hidden — scrolled out of its viewport, in an
/// inactive tab/Offstage, covered by another route, or with the app in the
/// background — and resumes it afterwards if it was playing. Uses only the
/// Flutter SDK (no visibility package). Not for `MovaFeedPlayer` pages: the
/// feed pool already decides which page plays.
///
/// 在 [child] 被隐藏时暂停 [api]——滚出视口、处于非活跃 Tab/Offstage、被其他路由
/// 盖住、或应用进入后台——之后若隐藏前在播则恢复。只用 Flutter SDK（不依赖任何
/// 可见性三方包）。不要用于 `MovaFeedPlayer` 的页面：feed 池已经在决定哪一页播放。
///
/// Example / 示例:
/// ```dart
/// final movaRoutes = RouteObserver<ModalRoute<dynamic>>();
/// // GoRouter(observers: [movaRoutes], ...) and StatefulShellBranch(observers: [movaRoutes], ...)
/// MovaAutoPause(api: engine, routeObserver: movaRoutes, child: MovaPlayer(api: engine))
/// ```
class MovaAutoPause extends StatefulWidget {
  const MovaAutoPause({
    super.key,
    required this.api,
    this.config = const MovaAutoPauseConfig(),
    this.routeObserver,
    this.onChanged,
    required this.child,
  });
  final MovaApi api;
  final MovaAutoPauseConfig config;
  /// Optional observer registered on *every* navigator (root and nested); lets
  /// the guard notice routes pushed on an outer navigator, which
  /// `ModalRoute.isCurrentOf` cannot see.
  /// 可选，需注册到**每一个** navigator（根与嵌套）；让守卫能察觉推到外层 navigator
  /// 上的路由——这是 `ModalRoute.isCurrentOf` 看不到的。
  final RouteObserver<ModalRoute<dynamic>>? routeObserver;
  /// Called whenever the hide-reason set changes. 隐藏原因集合变化时回调。
  final void Function(Set<MovaHideReason> reasons)? onChanged;
  final Widget child;
}
```

State 要点（实现提示，非逐字代码）：
- `didChangeDependencies`：
  - `TickerMode.getNotifier(context)`：若与上次不同，换监听；值为 `false` → `tickerOff`。
  - `ModalRoute.isCurrentOf(context) == false` → `routeCovered`（注册依赖，栈变化自动回调）。
  - 有 `routeObserver` 时：从 `ModalRoute.of(context)` 起，沿 `route.navigator?.context` 逐层向上收集
    `ModalRoute`，对每一层 `subscribe(this-level RouteAware, route)`；任一层 `didPushNext` → 覆盖计数+1，
    `didPopNext` → -1。`dispose` 时全部 `unsubscribe`。
  - 视口：沿 `Scrollable.maybeOf(context)` → `Scrollable.maybeOf(scrollable.context)` 收集祖先
    `ScrollPosition` 并 `addListener`；每次回调及每帧布局后（`addPostFrameCallback`，只在需要时排一次）
    计算：自身 `RenderBox` 未 attach/无尺寸 → 跳过（交给 tickerMode）；否则全局矩形与各祖先 Scrollable
    的视口矩形逐层求交，`可见比例 = 交集面积 / 自身面积`，`<= minVisibleFraction` → `offscreen`。
- `AppLifecycleListener(onStateChange: …)`（`config.background` 为 true 时创建）：`inactive` →
  `gate.onInactive(playing: api.state.playing)`；`hidden`/`paused` → `background` 置位；`resumed` →
  `background` 清除 + `gate.onResumed()`。
- 每次原因变化：`gate.update(reason, active, playing: api.state.playing, live: api.state.type == live,
  exempt: api.state.pip || api.state.mini, now: DateTime.now())`，按动作调 `api.pause()` /
  `api.play()` / `await api.backToLiveEdge(); if (!api.state.playing) await api.play();`。
- `MovaView` 追加 `final MovaAutoPauseConfig? autoPause;`（`null` = 不挂守卫）与
  `final RouteObserver<ModalRoute<dynamic>>? routeObserver;`，非空时用 `MovaAutoPause` 包住内部 `MovaPlayer`。

**断言（11，WidgetTester + `FakeMovaApi`，`api.push(MovaState(playing: true))` 模拟在播）：**
1. `ListView` 里的卡片滚出视口 → `pause`；滚回 → `play`。
2. `minVisibleFraction: 0.5`：滚到只露 30% → `pause`。
3. 外层 `TickerMode(enabled: false)`（模拟 go_router 非活跃分支）→ `pause`；恢复 `true` → `play`。
4. 同一 navigator 上 `push(MaterialPageRoute)` → `pause`；`pop` → `play`。
5. 嵌套 navigator：卡片在内层，外层 navigator push 页面——无 observer 时**不**暂停（记录局限），提供 `routeObserver` 时暂停、pop 后恢复。
6. `tester.binding.handleAppLifecycleStateChanged(hidden)` → `pause`；`resumed` → `play`。
7. `inactive` 时在播 → 推 `playing:false`（模拟系统自动暂停）→ `hidden` → `resumed` → 仍调用 `play`。
8. `state.mini == true` 时进后台 → 不 `pause`。
9. 直播源 + `liveResumeGrace: Duration.zero` → 恢复时调 `backToLiveEdge`，随后 `play`。
10. 卸载后再触发生命周期/滚动 → 无调用、无异常（监听已移除）。
11. `MovaView(autoPause: const MovaAutoPauseConfig())` 树中有 `MovaAutoPause`；`autoPause: null` 时没有。

**验收：** 测试 **1146**。

---

## Task 14：宿主测试替身——`package:mova/testing.dart` ✅ 已完成（实测 +7，累计 1155）

**Files:** Create `lib/testing.dart`、`lib/src/testing/hooks.dart`、`lib/src/testing/test_kernel.dart`、
`lib/src/testing/testing.dart`；Modify `lib/src/platform_impl/wiring.dart`；
Test: `test/testing/testing_test.dart`（**整个文件不调用 `MediaKit.ensureInitialized`**，本身就是证据）。

**Produces：**

```dart
// lib/testing.dart
/// Test doubles for apps that embed mova: run widget tests with real
/// `MovaEngine`s on a scriptable kernel, never touching media_kit.
///
/// 给嵌入 mova 的应用用的测试替身：在可编程内核上跑真实的 `MovaEngine`，完全不碰
/// media_kit。
library;

export 'src/testing/test_kernel.dart';
export 'src/testing/testing.dart';
```

```dart
/// A scriptable [MovaKernel] (+ [MovaStatsProbe]) for widget tests: records
/// calls and lets the test push any kernel signal.
///
/// 供 widget 测试使用的可编程 [MovaKernel]（兼 [MovaStatsProbe]）：记录调用，并允许
/// 测试推送任意内核信号。
///
/// Example / 示例:
/// ```dart
/// final k = MovaTesting.lastKernel!;
/// k.emitSize(1280, 720);
/// k.emitRestart();       // MovaState.rendered → true
/// ```
class MovaTestKernel implements MovaKernel, MovaStatsProbe {
  MovaTestKernel({this.renderHandle, this.nativeRestartAvailable = false}); // false：兜底信号立即落地，不起宽限 Timer
  final List<String> calls;
  String? lastUri;
  Object? openError;                  // 非空时 open() 抛出它
  @override Object? renderHandle;     // 默认 null → MovaPlayer 渲染占位
  @override bool nativeRestartAvailable;
  void emitPlaying(bool v); void emitBuffering(bool v); void emitCompleted(bool v);
  void emitPosition(Duration v); void emitDuration(Duration v); void emitBuffer(Duration v);
  void emitSize(int w, int h); void emitError(Object e);
  void emitRestart(); void emitEndFile(MovaEndFileReason r); void emitStalling(bool v);
  // 其余 MovaKernel/MovaStatsProbe 成员按 FakeStatsKernel 实现
}

/// Switches `createMovaEngine()` to [MovaTestKernel]s for the current test.
///
/// 在当前测试里把 `createMovaEngine()` 切换为使用 [MovaTestKernel]。
///
/// Example / 示例:
/// ```dart
/// setUp(MovaTesting.useTestKernels);
/// tearDown(MovaTesting.reset);
/// ```
abstract final class MovaTesting {
  /// While installed, `createMovaEngine()` builds `MovaEngine(kernel: factory())`
  /// with no-op platform ports and a memory-only thumbnail cache; an explicitly
  /// passed `kernel:`/port still wins.
  /// 安装期间，`createMovaEngine()` 构建 `MovaEngine(kernel: factory())`，平台端口用空
  /// 实现、缩略图只用内存缓存；显式传入的 `kernel:`/端口仍然优先。
  static void useTestKernels([MovaTestKernel Function()? factory]);
  /// Kernels created since [useTestKernels], oldest first. 安装以来创建的内核，按创建顺序。
  static List<MovaTestKernel> get kernels;
  static MovaTestKernel? get lastKernel;
  static bool get active;
  /// Uninstalls and forgets every kernel. 卸载并清空已记录的内核。
  static void reset();
}
```

`wiring.dart`：函数体开头

```dart
final testKernel = movaTestKernelFactory;   // from src/testing/hooks.dart
if (kernel == null && testKernel != null) {
  return MovaEngine(
    kernel: testKernel(), audioOnly: audioOnly, fit: fit, options: options,
    interceptors: interceptors, brightness: brightness, volume: volume, pip: pip,
    orientation: orientation, thumbDir: thumbDir, extractor: extractor,
    fetcher: fetcher, reporter: reporter,
  );
}
```

**断言（7）：**
1. 安装后 `createMovaEngine()`（无参）不抛，`MovaTesting.lastKernel` 非空且是该引擎的内核（`open` 后 `lastUri` 对得上）。
2. 安装后平台端口是空实现（`debugBrightnessPort is MovaFallbackBrightnessPort`、`debugPipPort is MovaNoopPipPort`）。
3. 显式 `kernel: FakeKernel()` 仍胜出（`MovaTesting.kernels` 不增长）。
4. `reset()` 后 `active == false`、`kernels` 为空。
5. `nativeRestartAvailable` 默认 `false` 下：`emitRestart()` 与 buffering 下降沿都能让引擎 `rendered == true`，且无挂起 Timer。
6. widget 测试：`MovaView(source: ..., poster: ..., options: MovaOpts(recovery: MovaRecoveryConfig(enabled: true)))` 用默认工厂（不传 `engineFactory`）能 pump，推尺寸 + RESTART 后封面淡出；测试结束拆树时不报挂起 Timer（锚定 Task 2/10 的同步取消）。
7. 主 barrel 不导出测试符号：`lib/mova.dart` 文本中不含 `testing` 导出（读文件断言，与 `purity_test` 同一风格）。

**验收：** `purity_test` 原样通过；`flutter pub publish --dry-run` 无新增 warning（顺带跑一次，不作为硬门槛）；
测试 **1153**。

---

## Task 15：文档、开放性对账与验证 demo 页 ✅ 已完成（实测 +3，累计 1158）

**Files:**
- Test: `test/core/openness_host_test.dart`（3）：① 默认值全关——`MovaOpts().recovery.enabled == false`、
  `const MovaSource('x').alternatives.isEmpty`、`MovaTheme()` 三个缓冲字段为 `null`、
  `movaObserveFlags(hasReporter:false, preciseFirstFrame:false).native == false`；② 注入的
  `MovaRecoveryPolicy` 真被咨询（记录型策略计数 > 0，照 `openness_report_test.dart`）；③ 配置项可经
  `copyWith` 单独替换且不影响其他节。
- `README.md`：新增"声明式用法（MovaView）""封面与出画面信号""超时与多地址""自动暂停""widget 测试"五节；
  "已知限制"补：守卫的视口检测不覆盖 Clip/Transform/Overlay 遮挡、外层 navigator 需注册 `routeObserver`、
  recovery 与 `MovaAdController`/`MovaSwapEngine` 同开不在保证范围。
- `CHANGELOG.md`：未发布节，列新公开面；**注明 `MovaEvent` 新增 4 个子类**（穷尽 switch 需补分支）与
  `open()` 同步归零宽高。
- `doc/SPEC.md`：新增一节「宿主易用性（2026-10-23）」，记 D1–D10 的签名与落点、判据表。
- `CLAUDE.md`：在"当前状态"加一节摘要 + 测试基线回写（实跑数字）。
- `example/lib/main_host_ergonomics_verify.dart`：为 Task 16 单独建的验证页（不与其他 spike 混用），
  每次 open 给 URL 加 `?t=<timestamp>` 防缓存；页面把 `MovaFirstFrame`/`MovaPlayFailure`/`MovaFailover`/
  `MovaRecovered`/`MovaPause`/`MovaPlay`/`MovaLiveEdgeReach` 连同事件时间戳打到日志（`debugPrint` 带固定前缀
  便于 logcat 过滤）。**本 Task 只要求 `flutter analyze` 通过，不要求上机。**

**验收：** analyze 0（example 下仅既有 `avoid_print` info）；测试 **1156**；基线数字回写到 `CLAUDE.md` 与本文件。

---

## Task 16：真机验证【待定：等真机】

> **状态：待定。** STG AL00 当前不可用。本 Task 与 Task 1–15 完全解耦：不阻塞任何 Task 的合入，
> 也不是任何 Task 验收的前置条件。真机回来后单独一轮执行，结果回写本节与 `feedback_real_device_verification`。
> **2026-10-24 更新：** Windows 桌面可测的部分已跑完（见下「Windows 桌面实测（2026-10-24）」，含两个待决发现）；**Android 项（V9、V11 与各项的 Android 复测）仍待真机**，交接清单见 [2026-10-24-android-real-device-handoff.md](2026-10-24-android-real-device-handoff.md)。

**前置检查：** 手机亮屏且已解锁（`dumpsys window | grep isKeyguardShowing` 为 false），锁屏/熄屏时一切涉及
渲染面的结果作废（CLAUDE.md）。debug 与 release 各跑一遍（debug 是 100ms 轮询，精度不同）。

**测量方法（全部基于 App 内事件时间戳，不用墙钟、不用临近 EOF 的 seek）：** 验证页在 `open()` 调用处与各事件
回调处取 `DateTime.now()`，差值即耗时；`MovaFirstFrame.sinceOpen` 本身就是同一口径。需要"画面是否真的露出"
时，用 `adb shell screencap` 连续抓帧（约 250–330ms 一帧）与事件时间戳对齐，只做量级对账。每项至少 5 次取
min/max/avg，URL 加 timestamp 防缓存。

| 编号 | 验证项 | 方法 | 通过判据 |
|---|---|---|---|
| V1 | 出画面精度 | 同一源分别 `preciseFirstFrame: true/false` 各 5 次；同时开 reporter 取 QoE `firstFrame.ttffMs` 对账 | `true` 时 `signal` 全为 `restart` 且与 QoE `ttffMs` 差 < 50ms；`false` 时为 `buffering`/`progress`，比 `restart` 早约 200ms 量级（对齐 CLAUDE.md 612 vs 809ms） |
| V2 | 暂停态打开是否收到 RESTART | `open(autoPlay:false)` 5 次，看 `signal` | 记录事实：若为 `restart` → Task 6 的 feed opt-in 可放心推荐；若为 `size`/`grace` → 文档注明暂停态精度来源 |
| V3 | 换源重置 + 封面重盖 | 播 A 出画面后 `open(B)`；记录 `rendered=false` 的 state 时间戳与 B 的 `MovaFirstFrame`；抓帧看封面 | 每次换源都有新的 `MovaFirstFrame`；抓帧中 B 出画面前不出现黑帧/A 的残帧露出（受采样间隔限制，只做量级证据） |
| V4 | 陈旧 RESTART 竞态 | A 播放中 `seek` 后 ≤50ms 内 `open(B)`，重复 20 次 | B 的 `MovaFirstFrame.sinceOpen` 无一 < 100ms（若有，说明 D1 的"在途丢弃"没兜住） |
| V5 | 起播超时 | ① 实际离线桌台地址；② 本机 HTTP 服务（`adb reverse`）接受连接但不发数据 | `MovaPlayFailure(startTimeout)` 距 `open()` 与 `startTimeout` 差 < 300ms；重试次数符合策略；最终 `MovaErrorEvent(MovaGiveUpError)` 恰一次；之后无流量（内核已 pause） |
| V6 | 卡顿超时 + 续播 | 本机限速服务播放 N 秒后停止发送；点播源 | `MovaPlayFailure(stallTimeout)` 时刻 ≈ 断流起点 + `stallTimeout`；重试后续播位置与失败前位置差 < 500ms（取 `MovaProg` 事件） |
| V7 | 多地址兜底 | 主地址坏、备选好；以及主地址坏、备选也坏 | 前者 `MovaFailover(0→1)` + `MovaFirstFrame`，`sourceIndex == 1`；后者 `MovaGiveUpError.last.sourceIndex == 1` |
| V8 | 坏地址快判 | 不存在的资源，开 `preciseFirstFrame` | `nativeEndError` 在超时之前到达（记录耗时） |
| V9 | 前后台续播 | 播放中 `adb shell input keyevent KEYCODE_HOME`，5s 后 `am start` 回到前台 | 收到守卫触发的 `MovaPause` 与回前台后的 `MovaPlay`；直播源额外有 `MovaLiveEdgeReach`；**CLAUDE.md 记的"回前台需手动续播"不再复现** |
| V10 | Tab 与路由遮挡 | demo 内 `StatefulShellRoute.indexedStack` 两个分支来回切；push 全屏页（含 `fullscreenDialog`）到根 navigator | 切走即 `MovaPause`、切回即 `MovaPlay`；注册 `routeObserver` 后根 navigator push 也能暂停 |
| V11 | 系统 PiP 不受守卫影响 | 播放中 `enterPip()` | 无 `MovaPause`（`inactive` 不暂停 + `pip` 豁免） |
| V12 | 关闭态回归 | 全部默认参数跑一遍基础流程 | 事件序列与改造前相比只多 `MovaFirstFrame`；`preciseFirstFrame:false` 且无 reporter 时弱客户端创建数 0（FFI V9） |

### Windows 桌面实测（2026-10-24）

> 范围：只做"和平台无关"的验证点，Android 项一律**未完成**（见下文分类表）。验证页 `example/lib/main_host_ergonomics_verify.dart` 的脚本化模式
> （`--dart-define=AUTORUN=true`，实现在 `example/lib/verify_auto/he_auto.dart`），源由 `example/tool/verify_sources/` 提供。
> 所有耗时来自真实事件：`MovaFirstFrame.sinceOpen`、同一单调时钟上的事件到达；不用墙钟估算，不 seek 到临近 EOF，每次打开带新 `?t=`。

**环境**

| 项 | 值 |
|---|---|
| 系统 / 硬件 | Windows 10 Pro 10.0.19045；Intel Core i5-13500（14 核 / 20 线程）；Intel UHD Graphics 770（无独显）；硬解 `d3d11va-copy` |
| Flutter | 3.47.0（stable，4cf2416426，2026-08-11）；Skia 后端（环境变量 `FLUTTER_ENGINE_SWITCH_1=enable-impeller=false`，等价于 `--no-enable-impeller`，沿用 CLAUDE.md 的 Windows 规避手段） |
| 构建模式 | **release**（`flutter build windows --release` + 直接启动 exe）。理由：release 下 `pollInDebug=false`，原生 `PLAYBACK_RESTART`/`END_FILE` 走真实回调（debug 是 100ms 轮询，精度不同）；AOT 无 VM 服务干扰；release 桌面版 `print` 不回传，日志靠 `MOVA_LOG`/`LOG_FILE` 落盘。profile 能给同样的数字，但没有必要。debug 未测（其数字不可信，只能看行为）。 |
| libmpv | mova 自研瘦身版 `libmpv-2.dll`（`media_kit_libs_windows_video_slim`） |
| 源 | 本机 ffmpeg 8.0.1：`testsrc2` 640x360@25fps + `sine` 440Hz，libx264 ultrafast/zerolatency 600kbps，AAC 64kbps，`-re` 实时；**GOP 固定 50 帧（2s）**，`-sc_threshold 0`；每个连接起一个 ffmpeg（多客户端），`/live.flv`（FLV 直播）、`/hang`（接受连接不回数据）、`/stall.mp4`（点播素材 40s、300kbps、GOP 50，前 10% 后挂住直到页面放行）、`/vod.mp4`（同素材正常点播）；坏地址：拒连端口 `127.0.0.1:9`、404 |
| 参数 | `recovery`：`startTimeout=4s`（V8 为 15s）、`stallTimeout=4s`、默认策略（重试 1 次、间隔 1s）；每场景 3 次（V4 为 20 次） |
| 构建环境坑（非 mova 问题） | CMake 4.x 与插件 googletest 不兼容需 `CMAKE_POLICY_VERSION_MINIMUM=3.5`；`just_audio_windows` 用了被新 MSVC 废弃的 `<experimental/coroutine>`，需 `CL=-D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS`；第一次 CMake 配置失败后缓存会把 install prefix 留在默认值，需删 `build/windows` 重来 |

**逐项分类**（①Windows 可测且已测 ②只有 Android 能测 ③需要真实业务流或其他条件）

| 编号 | 分类 | 说明 |
|---|---|---|
| V1 | ① | 已测 |
| V2 | ① | 已测 |
| V3 | ①+③ | 事件部分已测；"抓帧看封面/黑帧/残帧"属 ③（需要逐帧抓取与图像比对，本轮未做） |
| V4 | ① | 已测 |
| V5 | ①+③ | 本机"接受连接不发数据"已测；"实际离线桌台地址"属 ③（需要真实业务地址） |
| V6 | ① | 已测（本机卡顿服务代替限速服务） |
| V7 | ① | 已测 |
| V8 | ① | 已测 |
| V9 | ② | HOME 键进后台再回前台，只有 Android |
| V10 | ①+③ | `TickerMode` 与"盖一层路由"已测（后者崩溃，见下）；`StatefulShellRoute.indexedStack` 与 `routeObservers` 属 ③（需要 go_router 的真实 demo / bingo） |
| V11 | ② | Android PiP（Windows `pipSupported=false`） |
| V12 | ①（部分） | 事件序列与无 recovery/standby 事件已测；"弱客户端创建数为 0"本页没有计数后端，未测 |

**原始数据与判定**（毫秒；括号内为每次的值，`avg` 为平均）

| 编号 | 结果 | 判定 |
|---|---|---|
| V1 | `precise=true`：`signal` 3/3 为 `restart`，`sinceOpen` = (3016, 2264, 2249)，avg 2509.7（首次含冷启动）；QoE `ttffMs` 与之差 = (0, 0, 0) ms。`precise=false`：`signal` 3/3 为 `buffering`，`sinceOpen` = (1743, 1742, 1790)，avg 1758.3 | **通过**（差 < 50ms；`false` 为 `buffering`）。量级与预期不同：`false` 比 `restart` 早约 **0.46–0.52s**（去掉冷启动那次），不是 CLAUDE.md 里的 ~0.2s——该源的 `buffering` 下降沿比 RESTART 更早 |
| V2 | `autoPlay:false`：`signal` 3/3 为 `restart`，`sinceOpen` = (2286, 2271, 2286)，avg 2281.0 | **事实**：暂停态打开**会**收到 RESTART → Task 6 的 feed opt-in 在 Windows 上可放心推荐；Android 仍需确认 |
| V3 | 换源后 `state.rendered=false` 距换源调用 = (17, 6, 16) ms，avg 13.0；新源 `MovaFirstFrame.sinceOpen` = (2116, 2103, 2090)，avg 2103.0，`signal=restart`；每次恰 1 个新 `MovaFirstFrame`，之后 `rendered=true` | **通过**（事件部分）；抓帧部分未测 |
| V4 | 20 次：seek 之后 10/20/30/40/50ms 轮换再 `open(B)`；B 的 `sinceOpen` min 2047、max 2114、avg 2078.7；**< 100ms 的次数 0** | **通过**（D1 的"在途丢弃"站得住） |
| V5 | 挂住的源：首次 `startTimeout` 失败距建引擎 = (4039, 4038, 4041)，与 `startTimeout=4000` 差 = (39, 38, 41) ms，avg 39.3；随后 1 次 retry，第 2 次失败即放弃，放弃时刻 = (9049, 9051, 9050)，avg 9050.0；`MovaErrorEvent(MovaGiveUpError)` 恰 1 次，`state.error` 已置；服务器日志：放弃之后**没有再建新连接**，旧连接约 1.1s 后关闭 | **通过**（< 300ms；重试次数符合策略；恰一次放弃；之后无流量） |
| V6 | 卡顿判定：`buffering=true` → `PlayFailure(stallTimeout)` = (4002, 4000, 4002) ms（偏差 +2/0/+2ms）；失败前位置 2840ms；重试后进度样本 `+201ms:160 +1009ms:960 +1815ms:1800 +2622ms:2600`（每 ~0.8s 一采样，线性增长，**没有跳到 2840ms**）；`MovaRecovered` 1 次 | 卡顿判定**通过**；**续播位置不通过**（判据 < 500ms，实际重试后从头播放，见"发现 1"） |
| V7 | 主坏备好：`MovaFailover(0→1)` 3/3，距建引擎 = (9052, 9046, 9050) ms，`sourceIndex=1`，`MovaFirstFrame` 在 (11889, 11818, 11807) ms；主备皆坏：`MovaGiveUpError.last.sourceIndex=1` 3/3，放弃时刻 = (10083, 10076, 10074) ms（`last.kind=startTimeout`） | **通过** |
| V8 | 拒连端口：`MovaPlayFailure(nativeEndError)` = (5069, 5070, 5064) ms，avg 5067.7；404：(37, 41, 38) ms，avg 38.7；`open()` 均未抛出（`onOpenError` 0 次） | **通过**（`startTimeout=15s` 之前到达）。注意拒连要 ~5.07s 才冒出 END_FILE(error)，`startTimeout` 设得比这短就会被超时先判掉（V7 主备皆坏那条即是 `startTimeout`） |
| V10 | `TickerMode` 关/开（`V10B`，3 次）：`MovaPause` 距动作 = (11, 12, 5) ms、avg 9.3，`MovaPlay` = (10, 11, 11) ms、avg 10.7，隐藏 < `liveResumeGrace` 故无 `LiveEdgeReach`。盖一层路由（`V10A`）：push 后 8ms 即收到 `MovaPause`；`guard` 关（`V10C`）push 后 5s 内无 `MovaPause`（符合预期）。**弹出（pop）覆盖路由时进程崩溃** | `TickerMode` **通过**；路由盖住 **不通过：原生崩溃**（见"发现 2"） |
| V12 | 3 次事件序列完全一致：`MovaFitChange, MovaPause, MovaDurationChange, MovaBufferChange, MovaSizeChange, MovaPlay, MovaSourceChange, MovaReady, … MovaFirstFrame … MovaSeek, MovaSeeked, MovaPlay, MovaPause …`；无 `MovaPlayFailure/MovaRecovered/MovaFailover/MovaStandby*`，`state.standby=off` | **通过**（只多了 `MovaFirstFrame`）。附带事实：默认参数下对拒连地址 `open()` **不抛异常、3s 内也没有 `MovaErrorEvent`**（`badOpenThrew=false errorEvents=0`） |

**发现（实测发现的 bug / 与预期不同，均未改库代码，由主会话决定）**

1. **V6 VOD 卡顿恢复后从头播放，没有续播到失败前位置**（疑似 bug）。
   复现：`example` 里 `ONLY=V6` 跑 `main_host_ergonomics_verify.dart`（源：`/stall.mp4`，`recovery` 开，`stallTimeout=4s`）。证据：失败时 `state.type=vod rendered=true duration=40023ms`、失败前
   `MovaProg.position=2840ms`；`_recover` 之后进度从 0 线性增长（见上表样本），5s 内无跳变；服务器侧重试连接是 `Range` 起点 0 的整文件请求。
   线索（未验证）：`_recover` 里 `_seekOrPark(resumeAt)` 在 `await _loadKernel()` 之后调用，若此时 `state.duration` 已 > 0 就走直发 `_kernel.seek()`，而 CLAUDE.md 记过"裸 seek 在文件未就绪时被 mpv 静默丢弃"。
   **已修复（2026-10-24，加载请求返回/时长到达不保证文件已就绪，原续播 seek 可被丢弃），待复测。** 当前有效尝试首帧落地后才发送续播 seek；真实 Windows V6 是否命中此窗口及修复后的 <500ms 落点仍须 release 复测，以上历史采样不改判。

   代码核对：`_onPlayFail` 首次失败保存 `_recoveryPosition` → `_recover` 读取该值、清媒体进度/时长、武装尝试 → `_loadKernel` 等内核 `open()` 请求返回 → 原实现 `_seekOrPark`（已有时长时立即 seek，否则等 duration 回调补发）→ 首帧落地清恢复位置。`MovaKernel.open` 的契约只是请求已提交；`MovaMpvKernel.open` 使用 `Media(uri)`，没有传 `start`，续播依赖引擎 seek，并非漏传已有 start 参数。缺口是续播没有等待当前尝试就绪；时长先到会导致提前发送，而丢失后首帧路径不会补救。

   修复：恢复目标仍跨失败保存；`_recoveryAwaitingFrame` 在 `_armAttempt` 时复位、恢复加载前设置，只有未判失败的当前尝试落地才发送 seek。首帧已就绪时不再依赖下一条 duration；已知时长仍钳位。按 D7 的“重试/切换 = 内核重载”语义，同内容点播备选续播；直播不发送 seek。未新增接口成员或依赖，未改 UI/example，未 build/连设备/adb/提交。

   原 #7 及 Task 10 测试只检查 FakeKernel 的 `lastSeek`，并在重试后人工补发 duration；FakeKernel 会记录任何时机的 seek，不能区分命令被记录与实际生效。现加强两条旧测试，要求首帧前无 seek、落地后正确 seek；新增 `resume_readiness_test.dart` 14 条，假内核在就绪前丢弃 seek，并检查实际落点。覆盖点播/直播 × stallTimeout、openThrew、nativeEndError、failover 共 8 条，以及无新时长时 restart/buffering/progress/暂停尺寸落地 4 条、已失败尝试迟到首帧不清目标、新会话丢弃旧目标 2 条。

   先失败后通过的实跑输出（2026-10-24）：修改引擎前新增的 8 条测试中，点播四条均 `Expected: Duration:<0:00:02.840000>` / `Actual: Duration:<0:00:00.000000>`，末行 `00:00 +4 -4: Some tests failed.`；修复与补充边界后 recovery 目录末行 `00:01 +67: All tests passed!`。全量基线先实跑 `00:40 +1302: All tests passed!`；最终 `flutter analyze lib test` 末行 `No issues found! (ran in 7.4s)`、`flutter test --reporter expanded` 末行 `00:43 +1316: All tests passed!`（新增 14）。这些是假内核证据，尚无本次 Windows/Android 原生复测结论。
2. **V10 `盖一层路由` 在弹出路由时原生崩溃（Windows，100% 复现 6/6）**。
   复现：`ONLY=V10A`（或 `V10C`，守卫关也崩）；`MovaView` 在根 navigator，push 一个不透明 `MaterialPageRoute` 后 pop。push 阶段正常（守卫开时 8ms 内 `MovaPause`），**pop 时进程以 `0xC0000005` 退出**；
   **（更正：此处"Skia 与默认后端各试过，均崩"是假对照——release 构建忽略 `FLUTTER_ENGINE_SWITCHES`，两次其实都是 Impeller；见下方"V10 崩溃根因与修复"）** `TickerMode` 路径（`V10B`）不崩，说明触发点是"路由弹出让播放器重新露出"。
   证据：Windows 事件日志 Id 1000，故障模块 `flutter_windows.dll`，偏移 `0x2c4427`（6 次一致）；WER 转储在 `C:\workspace\dart-labs\mova\_crash_dumps\`（已配置，每个 ~800MB），
   `cdb` 取栈：崩溃在引擎线程的**图层树递归遍历**中对空指针解引用（`mov rax,[rcx]`，`rcx=0`），帧数很深；只有导出符号，无法定位函数名。形态上像 `TextureLayer` 引用了已被注销的外部纹理，**仅为推测**。
   这与 CLAUDE.md "Windows 真机播放中途 libmpv 原生崩溃"那条（故障模块是 `libmpv-2.dll`）**不是同一处**（本次故障模块是 `flutter_windows.dll`，且无需任何鼠标交互）。
3. 其余为"与预期不同"的事实，已写进上表：V1 `false` 比 `restart` 早 ~0.5s；V8 拒连 ~5.07s 才判错；V12 默认参数下拒连地址既不抛也不发错误事件。

**V10 崩溃根因与修复（2026-10-24，Windows 10 / Flutter 3.47.0 engine 5f77625673 / release）**

结论：**不是 mova 的问题，是 Flutter 3.47.0/3.47.1 引擎在 Windows + Impeller 下的 bug**（flutter/flutter#190774：快照 GPU 外部纹理时 `LayerTree::Flatten` 没有 Impeller 上下文，
`EmbedderExternalTextureGL::ResolveTextureSkia` 解引用空 `GrDirectContext`；修复 PR #191017，cherry-pick 进稳定版 **3.47.2**，官方 CHANGELOG 3.47.2 一节有 `flutter/190774`）。
触发路径：`MaterialPageRoute` 在 Windows 的默认转场 `ZoomPageTransitionsBuilder` 用 `SnapshotWidget(mode: permissive)` 给页面拍快照；`TextureLayer.supportsRasterization()` 默认 `true`，
所以视频纹理被一起交给引擎快照。只有 `PlatformViewLayer` 返回 `false`。

对照实验（探针页 `example/lib/main_route_cover_probe.dart`，环境变量驱动，同一二进制；视频源同为本地直播 FLV，默认每轮 push 持有 600ms + pop 后 800ms，20 轮；"崩"= 进程 `0xC0000005`，故障模块均为 `flutter_windows.dll`+`0x2c4427`）：

| 条件 | 结果 |
|---|---|
| release，纯 media_kit `Video`（无 mova），不透明路由，zoom 转场 | **崩**（第 2 轮 push） |
| release，mova `MovaView` 不开守卫，不透明路由，zoom 转场 | **崩**（4/4，第 2 轮 push/pop） |
| release，mova `MovaView` 开自动暂停守卫，不透明路由，zoom 转场 | **崩**（第 1 轮 pop） |
| release，mova 引擎 + 裸 `Video`（不走 mova ui），不透明路由 | **崩** |
| release，`maintainState:false` 的覆盖路由 | **崩** |
| release，**半透明**路由（`PageRouteBuilder(opaque:false)`，无转场快照） | 不崩 20/20 |
| release，`showDialog` | 不崩 20/20 |
| release，同页 `Offstage` / `Opacity(0)` 切换（不走路由） | 不崩 20/20 |
| release，不透明路由但**不打开媒体**（无帧更新） | 不崩 20/20 |
| release，`ZoomPageTransitionsBuilder(allowSnapshotting: false)`：纯 media_kit / mova | 不崩 20/20、20/20 |
| release，`FadeUpwardsPageTransitionsBuilder`：纯 media_kit / mova | 不崩 20/20、20/20 |
| profile / debug，Impeller（默认，日志 `Using the Impeller rendering backend (OpenGLESSDF)`） | **崩**（第 1–2 轮） |
| profile / debug，**真 Skia**（`FLUTTER_ENGINE_SWITCH_1=enable-impeller=false`，profile/debug 才认）：纯 media_kit / mova | 不崩 20/20、20/20（debug 同） |

要点：① **release 下 `FLUTTER_ENGINE_SWITCHES` 环境变量被忽略**（实测如此；推测是 Windows 嵌入层只在非 release 读它，未核对引擎源码），所以前一轮 release 里的"Skia 也崩"其实是同一个 Impeller 后端；profile/debug 才能真切到 Skia，
且 Skia 下不崩。② 崩溃落在**路由转场动画期间**（日志最后一行都是该轮的 push 或 pop，崩溃早于下一条日志）；需要纹理在持续出帧（不开媒体就不崩），第 1 轮常常能躲过，第 2 轮起必崩。
③ cdb 转储（`C:\workspace\dart-labs\mova\_crash_dumps\`，纯 media_kit 那次，Full Memory）：崩溃线程栈是图层树 `Paint` 的深递归，叶子函数里 `mov rax,[rcx]; mov rax,[rax+0x38]`（CFG 间接调用前取虚表）`rcx=0`，
即对空指针做虚函数调用；官方没有 `flutter_windows.dll` 的符号包（`storage.googleapis.com/flutter_infra_release/flutter/<engine>/windows-x64/*symbols*` 全 404），cdb 里显示的 `InternalFlutterWindows_WindowManager_UpdatePopupPosition+0x28cc1c`
只是离得最近的导出符号，**不是真实函数名**。所以栈本身只能证明"图层树绘制里的空指针虚调用"，把它归到 #190774 是靠 ①复现条件（快照转场 + GPU 纹理 + Impeller，Skia 不崩）②同一引擎版本 ③升级到含修复的版本前无法验证——**我没有在 3.47.2+ 上实测**（没升级本机 SDK）。
④ 上一个子代理的"TextureLayer 引用已注销纹理"推测不成立：Offstage/Opacity(0)/半透明路由同样让纹理离开绘制或持续存在，都不崩，崩的只有"快照"。

mova 侧修复（只在 `lib/src/ui/`）：`snapshot_guard.dart` 的 `MovaSnapshotGuard`（`RenderMovaSnapshotGuard` 在 `paint` 里 `pushLayer` 一个 `supportsRasterization()==false` 的 `ContainerLayer`），
`MovaPlayer` 的渲染面（`player.dart` `_RenderSurface`）在 **Windows 上**启用（`movaSnapshotGuardNeeded()`：`!kIsWeb && defaultTargetPlatform == windows`），其他平台关闭、原样透传。
宽松快照发现图层不支持栅格化就退回正常绘制，转场只是少了快照这层优化，画面不变。core 层与公开 API 零改动。
回归（`flutter test`，`test/ui/snapshot_guard_test.dart` 共 8 项）：基线（无守卫时宽松 `SnapshotWidget` 确实快照）、守卫开则不快照退回普通绘制、守卫关则照旧快照、开关切换 `alwaysNeedsCompositing`、
`movaSnapshotGuardNeeded` 仅 Windows、Windows 下 `MovaPlayer` 渲染面带守卫、Windows 下 `SnapshotWidget(permissive)` 包住 `MovaPlayer` 不快照、其他平台照旧快照。

修复后 release 复测（同一验证页 `main_host_ergonomics_verify.dart` AUTORUN，Impeller 默认）：**V10A 20/20 通过**（每次新建 `MovaView`，push→pop 各一次；`MovaPause` 距 push 3–18ms，avg 9.3，`MovaPlay` 距 pop 7–13ms，avg 9.8）；
**V10（路由 + TickerMode）10/10 通过**；V10C（守卫关）10 次 push/pop 无崩溃（该场景判据要求有 pause，守卫关本来就没有，所以逐项 FAIL 是预期，之前文档已记）；
探针 mova 单个播放器连续 push/pop：**20/20、20/20、守卫开 20/20、30/30（持有 300ms）全部不崩**；同一次构建里**纯 media_kit 对照仍然第 2 轮崩**，证明修复生效、对照有效。修复前同验证页 V10A 6/6 崩（本次又复现 1/1）。

**宿主建议**：根治是升级 Flutter ≥ 3.47.2；mova 的守卫只覆盖 `MovaPlayer`，宿主自己用裸 media_kit `Video` 的页面不受保护，可对转场关快照
（`ZoomPageTransitionsBuilder(allowSnapshotting: false)`，只影响 Windows 的转场优化）。守卫在 Flutter ≥ 3.47.2 上是多余但无害的（转场失去快照优化），待 mova 的最低 Flutter 版本升到 3.47.2 后可删。

**日志摘录**（`[MOVA-HE]`，release，完整日志为本机 scratchpad 里的 `he_final.log`，不入库）

```
V5 PlayFailure kind=startTimeout attempt=1 action=retry at=4039ms waited=4000ms
V5 PlayFailure kind=startTimeout attempt=2 action=giveUp at=9049ms waited=4000ms
V6 stateAtFailure type=vod rendered=true duration=40023ms buffering=true
V6 kind=stallTimeout bufferingTrueToFailure=4002ms (stallTimeout=4000ms, offset=2ms) posBefore=2840ms ... samplesAfterRetryFirstFrame=[+201ms:160 +1009ms:960 +1815ms:1800 +2622ms:2600]
V8 refused kind=nativeEndError at=5069ms waited=0ms openErrors=0
V8 404 kind=nativeEndError at=37ms waited=0ms openErrors=0
V10A action: push covering route
V10A route covered; pause=true
V10A action: pop covering route            <- 此后无日志，进程以 0xC0000005 退出
```

**附：V9 的 Windows 类比（不是 Android 的 HOME 键，不算 V9 完成）。** 加了 opt-in 场景 `ONLY=V9`（页面打印 `V9 WAIT_HOME` / `V9 WAIT_FOREGROUND` 标记，由外部驱动动手；
Android 用 adb，Windows 用 `example/tool/verify_sources/bg_driver.ps1` 最小化/还原窗口）。Windows 上跑通两次：最小化 → `LIFECYCLE hidden`（直接 `hidden`，不是 Android 记的 `inactive→hidden`），
守卫 `MovaPause` 距标记 313ms / 320ms；还原 → `inactive`→`resumed`，随后 `MovaPlay` + `MovaLiveEdgeReach`，位置在 3s 内推进 3040ms，**无需手动点播放**。
这只证明脚本与守卫的 `hidden` 路径可用，Android 的 `inactive→hidden` 序列与 libmpv 自暂停时序仍须真机确认。`V11` 在 Windows 上 `pipSupported=false`，场景记为 n/a。

**未完成（需 Android 真机，本节不得视为完成）：** V9（HOME 进后台续播）、V11（PiP 不受守卫影响）、V1–V8 在 Android 上的复测（V2 尤其：Android 暂停态打开是否发 RESTART；V8：Android 上 `END_FILE(error)` 的真实时机）、
V10 的 `routeObservers` 与 `StatefulShellRoute` 路径。交接清单见 [2026-10-24-android-real-device-handoff.md](2026-10-24-android-real-device-handoff.md)。

---

## 4. 宿主（bingo）改造示例（草图，本计划不改 bingo）

`pinoy_live_panel.dart` 改造后（`_PinoyLivePanelState` 与 `_PinoyLiveSkin` 整个删除，变为无状态组件）：

```dart
/// [PinoyPage] 顶部左侧的直播面板：直播画面上叠一层深色渐变头部（LIVE 徽标、观看人数、标题、跑马灯副标题）。
///
/// 画面交给 [MovaView]：按 [orderStreamUrls] 排好的多档地址依次兜底，起播 8 秒没画面或卡顿 10 秒自动重试/换档；
/// 出画面前盖着 [cover]，出画面后淡出；切走 Tab、被登录页盖住、切后台时自动暂停，回来续播（直播回到最新画面）。
class PinoyLivePanel extends StatelessWidget {
  const PinoyLivePanel({super.key, this.title = '', this.subtitle = '', this.viewerCount = '', this.streamUrls, this.cover = ''});

  final String title;
  final String subtitle;
  final String viewerCount;
  final List<PinoyStreamUrl>? streamUrls;
  final String cover;

  /// 直播卡片的播放配置：白色细转圈 + 超时重试/换档。
  static const MovaOpts _opts = MovaOpts(
    theme: MovaTheme(bufferingSize: 24, bufferingStrokeWidth: 2, bufferingColor: 0xFFFFFFFF),
    recovery: MovaRecoveryConfig(enabled: true, startTimeout: Duration(seconds: 8)),
  );

  @override
  Widget build(BuildContext context) {
    final source = MovaSource.pick(
      orderStreamUrls(filterPlayableStreamUrls(streamUrls)).map((u) => u.addr),
      type: MovaStreamType.live,
      title: title,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 1.1), borderRadius: BorderRadius.circular(11)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFF0E0E0E)),
            MovaView(
              source: source,
              fit: MovaFit.cover,
              poster: cover.isEmpty ? null : UrlImage(imageUrl: cover, fit: BoxFit.cover),
              skin: const MovaMinimalSkin(),
              options: _opts,
              autoPause: const MovaAutoPauseConfig(),
              routeObserver: appRouteObserver, // 宿主在 GoRouter(observers:) 与各 StatefulShellBranch(observers:) 注册同一个实例
            ),
            const _PanelHeader(/* 原 Positioned 渐变头部原样搬过来 */),
          ],
        ),
      ),
    );
  }
}
```

`pinoy_stream_urls.dart` 的 `pickStreamUrl`（只选一条）改为排序（业务规则留在宿主，D8）：

```dart
/// 按优先级排序候选：[preferred] 档位最前，其次 [fallback]，其余保持原顺序；地址为空的剔除。
List<PinoyStreamUrl> orderStreamUrls(List<PinoyStreamUrl>? urls, {String preferred = kPreferredStream, String fallback = kFallbackStream}) {
  if (urls == null) return const [];
  int rank(PinoyStreamUrl u) => u.name == preferred ? 0 : u.name == fallback ? 1 : 2;
  final list = urls.where((u) => (u.addr ?? '').isNotEmpty).toList();
  return list..sort((a, b) => rank(a).compareTo(rank(b))); // List.sort 在 Dart 中不保证稳定——实现时改用带下标的稳定排序
}
```

宿主 widget 测试（不再报 `MediaKit.ensureInitialized must be called`）：

```dart
import 'package:mova/testing.dart';

void main() {
  setUp(MovaTesting.useTestKernels);
  tearDown(MovaTesting.reset);

  testWidgets('封面在出画面后淡出', (t) async {
    await t.pumpWidget(MaterialApp(home: PinoyLivePanel(streamUrls: [PinoyStreamUrl(name: 'p_main', addr: 'https://x/live.flv')], cover: 'https://x/c.webp')));
    final k = MovaTesting.lastKernel!;
    expect(k.lastUri, 'https://x/live.flv');
    k..emitSize(1280, 720)..emitRestart();
    await t.pumpAndSettle();
    // 断言封面 AnimatedOpacity.opacity == 0
  });
}
```

净效果：宿主删掉约 40 行生命周期样板 + 15 行自定义皮肤 + 出画面判据（连同 §0 那个提前淡出的 bug），
新增超时重连、多档兜底、自动暂停三项能力；业务排序规则仍在宿主。

---

## 5. 明确排除项

- **QoE 改为消费 `MovaFirstFrame`：** 两套首帧判据并存（QoE 的 `MovaTtffTracker` 已真机验证，本期不碰）。
  合并另立项。
- **新事件进上报白名单：** `MovaFirstFrame`/`MovaPlayFailure`/`MovaFailover`/`MovaRecovered` 不进
  `translateMovaEvent`；需要时宿主自己 `api.report(MovaReportName.custom(...))`，或另立项扩白名单。
- **把内核 `error` 流作为恢复触发源**（理由见 D7）。
- **recovery 与 `MovaAdController`/`MovaSwapEngine` 同开的组合语义**：广告控制器有自己的 `loadTimeout` +
  `failPolicy`，影子引擎由同一工厂创建也会带上 recovery；同开不在保证范围，README 注明。
- **备选地址的排序/过滤钩子**（理由见 D8），以及 mova 内置协议黑名单。
- **守卫的像素级可见性**（Clip/Transform/Overlay 遮挡）——需要 layer 合成方案，见 Q6。
- **`test/support/FakeKernel` 与公开 `MovaTestKernel` 去重**：1008 项依赖前者，本期不动。
- **`MovaApi` 新增成员**：九项全部经 `MovaState`/事件/构造参/widget 参数表达，接口零变化。
- **iOS/macOS**：原生泵在 Darwin 未验证（订阅失败即静默退化到兜底判据），守卫逻辑平台无关但未上 iOS 真机。

---

## 6. 开放问题（需用户拍板；括号内为推荐默认，不反对就按它走）

1. **Q1 `MovaView` 是否默认开原生首帧订阅？**（推荐：`poster != null` 时开，否则关。`createMovaEngine`
   本身保持 `preciseFirstFrame: false`，守住 FFI V9"无 reporter 零客户端"不变量。）
2. **Q2 recovery 默认值**：`startTimeout`/`stallTimeout` 各 10s，默认策略"每地址重试 1 次、间隔 1s，再换
   备选，全部失败放弃"，直播走到结尾算失败。（推荐如上；直播卡片场景宿主可自行收紧到 8s。）
3. **Q3 给了 `alternatives` 但没开 recovery 时怎么办？**（推荐：忽略备选并在文档写明，保持"显式开启"；
   备选方案是"有备选即隐式启用 recovery 默认配置"，更省事但是隐式行为。）
4. **Q4 排序/过滤留给宿主**（推荐：是，mova 只给 `MovaSource.pick` 清洗辅助，见 D8）。
5. **Q5 守卫的路由遮挡是否包括 Dialog/BottomSheet？** 当前设计用 `isCurrent`，弹任何路由都会暂停。
   （推荐：保持——直播卡片上弹确认框时暂停可接受；若要"只有整页覆盖才暂停"需额外一个 `pagesOnly` 选项，
   且对 `fullscreenDialog` 判不准。）
6. **Q6 视口检测不引入 `visibility_detector`：** 无依赖方案覆盖所有基于 `Scrollable` 的布局（列表、
   `PageView`、`TabBarView`），覆盖不了 Clip/Transform/Overlay 遮挡。（推荐：接受无依赖方案；若确有
   "被浮层盖住也要暂停"的需求，再评估引入 `visibility_detector`——这是唯一可能需要新依赖的点，按约定先不引入。）
7. **Q7 Task 6（feed 池 opt-in）本期做不做？**（推荐：做，3 个测试、默认关闭；真机 V2 结果出来后再决定是否
   在文档里推荐开启。）
8. **Q8 `open()` 同步把 `state.width/height` 归零**（D1）：今天它要等 media_kit `stop()` 异步归零，提前到
   同步是一处时序上的行为微调。（推荐：接受，换源后旧比例不再漏进新源；CHANGELOG 注明。）
9. **Q9 `MovaSource` 用 `sameAs()` 而不是重写 `==`**（推荐：`sameAs`，避免改变宿主把 `MovaSource` 当 Map key
   时的身份语义。）
10. **Q10 `MovaEvent` 新增 4 个 sealed 子类**对宿主无 `default` 的穷尽 switch 是编译期 breaking（推荐：接受，
    与 `MovaMiniChange` 等先例一致，CHANGELOG 注明。）
