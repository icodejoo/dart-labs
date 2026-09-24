# mova 技术规格（SPEC）

配套阅读：[PRD.md](PRD.md)（需求/决策）、[ROADMAP.md](ROADMAP.md)（里程碑）、
[DESIGN-0.2.0.md](DESIGN-0.2.0.md)（0.2.0 重构的原始设计，含尚未实现的阶段
B/C 细节）。本文档描述**当前代码实际落地**的架构；与 DESIGN 文档冲突之处
以本文档为准（阶段 A 落地过程中做过的微调见文末）。

## 架构分层

```
lib/
├─ mova.dart                      # 对外唯一入口 barrel
├─ mova_platform_interface.dart   # 平台通道接口（getPlatformVersion / isPipSupported / enterPip / get·setSystemVolume）
├─ mova_method_channel.dart       # MethodChannel 实现
└─ src/
   ├─ core/                           # 内核层：无 Flutter/media_kit UI 依赖
   │  ├─ api.dart                     # MovaApi：UI 层唯一依赖的抽象能力面
   │  ├─ engine.dart                  # MovaEngine implements MovaApi，生产实现
   │  ├─ compat.dart                  # MovaCtrl（@Deprecated，包一层 MovaEngine，0.3.0 移除）
   │  ├─ kernel/kernel.dart           # MovaKernel 抽象（可 fake）
   │  ├─ kernel/mpv_kernel.dart       # 唯一 import media_kit 的文件
   │  ├─ bus/bus.dart                 # MovaBus：broadcast + throttle/distinct
   │  ├─ events/events.dart           # sealed MovaEvent 事件表
   │  ├─ state/state.dart             # MovaState + copyWith（含 sourceTitle 字段，非独立 getter）
   │  ├─ state/progress.dart          # MovaProg（高频位置/缓冲）
   │  ├─ state/ui_state.dart          # MovaUiState（控制条可见/HUD/预览位置）
   │  ├─ interceptor/interceptor.dart # MovaHook + MovaHookChain
   │  ├─ options/options.dart         # MovaOpts 聚合（live/gesture/abr/controls/strings/theme）
   │  ├─ options/abr_config.dart      # MovaAbrConfig（含 MovaAbrPolicy 抽象；未落在 model/abr.dart）
   │  ├─ options/gesture_config.dart  # MovaGestConfig（自 0.1.0 迁入，字段不变）
   │  ├─ options/controls_config.dart # MovaCtrlsConfig
   │  ├─ options/live_config.dart     # MovaLiveConfig（含 urlBuilder/backToLive/windowResolver）
   │  ├─ live/timeshift.dart          # resolveWindow/behindOf/atLiveEdge 纯函数
   │  ├─ options/strings.dart         # MovaStrs（文案外置，默认简体中文）
   │  ├─ options/theme.dart           # MovaTheme（配色/尺寸外置，ARGB int 存储）
   │  ├─ model/source.dart            # MovaSource / MovaStreamType
   │  ├─ model/quality.dart           # MovaQual + parseHlsMasterPlaylist（纯函数）
   │  ├─ model/fit.dart               # MovaFit(contain/cover/fill)
   │  └─ platform/ports.dart          # MovaBrightPort / MovaVolumePort / MovaPipPort / MovaOrientPort
   ├─ platform_impl/                  # ports 的具体实现（screen_brightness / MethodChannel / SystemChrome）
   └─ ui/                             # UI 层：组件树 + 皮肤 + 手势，纯 Flutter widget
      ├─ player.dart                  # MovaPlayer 门面：接 MovaApi，渲染画面，用 MovaSkin 出树
      ├─ fit_ext.dart                 # movaBoxFit()
      ├─ format.dart                  # formatDuration()
      ├─ scope/scope.dart             # MovaScope：InheritedWidget 发布 MovaApi
      ├─ scope/selector.dart          # MovaSelect<T> / MovaUiSelect<T>：按选择器重建
      ├─ slots/slot.dart              # MovaSlot 枚举 + MovaSlotBundle
      ├─ slots/component.dart         # MovaComp 抽象（name/slot/children/build）
      ├─ slots/tree.dart              # buildSlots()：组件树 → MovaSlotBundle
      ├─ slots/patch.dart             # MovaPatch（replace/remove/insertAfter/add，路径寻址）+ applyPatches()
      ├─ scope/plugin.dart            # MovaPlugin：副作用型组件的能力 mixin（api + bind）
      ├─ skins/skin.dart              # MovaSkin 抽象（无参 components()/assemble()）
      ├─ skins/default_skin.dart      # MovaDefSkin：静态树 + 三层可覆写骨架
      └─ components/                  # 叶子/组合组件：top_bar/bottom_bar（自适应 VOD/直播）/
                                       # center_play/gesture_layer/hud_layer/overlays/common
android/src/main/kotlin/.../MovaPlugin.kt  # 原生 PiP：ActivityAware + enterPictureInPictureMode
```

Slint 无关；纯 Flutter/Dart + 少量 Kotlin。`core/` 目录不 import
`package:flutter/*`（`purity_test.dart` 断言此约束）；`ui/` 是唯一可以
import Flutter widget 与直接依赖 `MovaApi` 的地方。

## 关键 API 与不变式

- `MovaApi` 是 `ui/` 唯一依赖的抽象；`MovaEngine implements MovaApi` 是生产实现，
  测试用 `FakeMovaApi`（`test/support/fake_api.dart`）。
- `MovaApi.renderHandle`：底层渲染句柄（生产环境是 media_kit 的
  `VideoController`），`MovaPlayer` 仅当其 `is VideoController` 时渲染真实
  `Video`，否则渲染占位符——这是 widget 测试无需真实播放内核的关键。
- `MovaState.sourceTitle` 是 `MovaState` 上的可空字段（不是 `MovaApi` 的独立
  getter）；`copyWith` 用 `clearSourceTitle` 标志区分"不改"与"清空"。
- 直播下 `seek()` 受 `state.liveSeekable` 门控（`MovaLiveConfig.seekMode !=
  off` 且可拖窗口 > 0）：`dvr` 走内核原生 seek（clamp 到 `seekableWindow`）；
  `timeshift` 走 `MovaLiveConfig.urlBuilder` 重开源（没有 `urlBuilder` 则整个
  seek 是空操作）。`backToLiveEdge()` 按 `MovaLiveConfig.effectiveBackToLive`
  执行——`seekEnd` 直接 seek 到窗口末端，`reopen` 重开**原始**直播地址
  （绕过 `open()`，因为回边缘是位置变化不是换源，也不该清空清晰度列表）。
- `MovaPlayer` 组合渲染画面 + `MovaSkin.components()` 出的**静态**组件树
  （经 `buildSlots()` 分槽，只构建一次）+ `MovaSkin.assemble()` 拼装 `Stack`；默认皮肤
  `MovaDefSkin` 复刻 0.1.0 的分栏布局与"隐藏时可穿透点击"规则。

## 组件树 / 皮肤 / 补丁

- `MovaComp`：`name`（树内寻址用）+ `slot`（归属的 `MovaSlot`）+
  `children` + `build(context, api, children)`。叶子组件 `children` 为空；
  组合组件（如 `TopBarComponent`）持有多个子组件。
- `MovaSkin.components()`（0.3.0 起无参）返回**静态**顶层组件列表——树不随状态
  变化，显隐由组件各自的 `MovaSelect` 响应式决定。VOD/直播底栏合并为一个自适应
  `BottomBarComponent`：暴露两套布局子组件的并集（顶层 `name` 恒为 `bottomBar`，
  patch 路径不随流类型错位），只挂载与当前 `state.type` 相关的那些。
- `MovaPlugin`（`ui/scope/plugin.dart`）：给「事件副作用型」有状态组件的能力 mixin，
  提供 `api`（`MovaScope.readOf` 非依赖读，`initState` 安全）与 `bind()`（订阅并在
  `dispose` 自动回收）。纯渲染组件走 `MovaSelect`，不需要它。
- `MovaSlot`：`gesture`/`hud`/`top`/`center`/`bottomAbove`/`bottom`/`overlay` +
  `left`/`right`（0.3.0 新增的左右垂直边带，供侧栏等；HUD 维持居中不落两侧）。
- `MovaDefSkin.assemble` 是三层骨架（播放/操作/常驻），0.3.0 起拆为受保护的
  `buildPlaybackLayer`/`buildOperableLayer`/`buildPersistentLayer`，子类可只覆写一层。
  三层各自包一层 `RepaintBoundary`：操作层重绘最频繁（进度条 tick/HUD 淡出/栏显隐
  动画），隔离后不牵连播放层（视频画面）与常驻层一起重新光栅化，反之亦然；对宿主
  App 也一样，外部重绘不会牵连进这棵子树。`test/ui/skin_test.dart` 用
  `find.descendant(of: find.byType(MovaScope), ...)` 断言恰好 3 个（不能用全局
  `find.byType(RepaintBoundary)`——`MaterialApp`/测试绑定在外层还有框架级的）。
- `MovaPatch` 是数据不是动作，只有 `applyPatches()` 解释它们（纯函数、可测）：
  - `MovaPatch.replace(path, component)`：整替换一个节点。
  - `MovaPatch.remove(path)`：移除一个节点（顶层或嵌套）。
  - `MovaPatch.insertAfter(path, component)`：在锚点之后插入同级兄弟。
  - `MovaPatch.add(slot, component, {order = 0})`：向树追加一个新顶层组件，
    按 `order` 在该 `slot` 内排序（阶段 A 落地时修过这里的排序/挂载逻辑，
    以 `applyPatches` 的实现与 `tree_test.dart` 为准）。
- 定制无需继承旧版 `VodControls`/`LiveControls`/`MovaGestDetect`：给
  `MovaDefSkin(patches: [...])` 传补丁，或整体实现 `MovaSkin`。

## 文案 / 主题外置

- `MovaStrs`：`fitContain`/`fitCover`/`fitFill`/`live`/`backToLive`/
  `timeshift`/`auto`/`quality` 八个字段，默认简体中文（`backToEdge` 已在阶段 C
  被 `backToLive` 取代并删除）；
  `fitLabel(MovaFit)` 是唯一允许解析 `MovaFit → 文案` 的地方（0.2.0 落地审计中
  删除了 `ui/fit_ext.dart` 里重复且硬编码的 `movaFitLabel()`）。
- `MovaTheme`：`iconColor`/`textColor`/`accentColor`/`barGradientColor`/
  `sheetBackgroundColor`（弹层背景，审计中从硬编码 `Color(0xEE1A1A1A)`
  提炼出的新字段）+ 字号/尺寸字段，均以 ARGB `int` 存储以保持 `core/`
  零 Flutter 依赖；`ui/` 层用处转 `Color(...)`。
- 二者都经 `MovaOpts.strings`/`MovaOpts.theme` 注入，组件通过
  `api.options.strings`/`api.options.theme` 读取，不再有散落的中文字面量
  或 `Colors.*`/`Color(0x...)` 硬编码（`components/`、`skins/` 下）。

## 拦截点

`MovaHook`：`beforeOpen`/`beforeSeek`/`beforePlay`/`onError` 四个钩子，
`MovaHookChain` 按注册顺序依次咨询、遇否决/取消即短路；`onError` 对
每个拦截器独立 try/catch，一个抛异常不影响其余拦截器收到通知。经
`MovaEngine(interceptors: [...])` 注入。

## 手势数学（gesture_layer.dart）

- 横滑进度：`seconds = dx / width * hSeekSpanPerScreen.inSeconds`（默认
  90s 满屏宽，来自 `MovaGestConfig.hSeekSpanPerScreen`，可配）；直播下受
  `state.liveSeekable && MovaGestConfig.allowWhenLive`（默认开）门控，
  非 `off` 模式的可拖直播允许横滑 seek，其余禁用。
- 竖滑：侧别→动作经 `MovaGestConfig` 的 `leftVertical`/`rightVertical`
  （`MovaGestAction`）配置，0.3.0 起默认**左亮度、右音量**（对齐主流，翻转自
  0.1.0/0.2.0 的左音量/右亮度）；音量 0–100、亮度 0–1，系数 `vSensitivity`。
  横滑动作由 `horizontal`（默认 `seek`）决定；`MovaGestAction.none` 可禁用某方向。
  volume/brightness 拖动均会 `showHud(...)`，HUD 徽标带图标 + 百分比（如 `🔊40%`）。
- 音量落点：`setVolume` 经 `MovaVolumePort` 路由——接了端口走它（系统音量/宿主回调），
  否则经内核走播放器音量。`createMovaEngine` 默认仅 Android 接 `SystemVolumePort`
  （原生 `AudioManager` 调系统媒体音量，无新依赖），iOS/桌面回退播放器音量；任意
  平台可传 `CallbackVolumePort` 接管。构造时从端口 `get()` 播种 `state.volume` 作手势基线。
- 亮度：经 `MovaBrightPort`（生产实现用 `screen_brightness`）调系统屏幕亮度，
  平台不支持时兜底 1.0。
- 双指缩放：`onScaleUpdate` 进入 zoom，`clamp(1, maxZoom)`。
- 双击：按 `MovaGestConfig.doubleTapStep`（默认 10s）快进退。

## 清晰度 / ABR

- **HLS/DASH（自适应源）走引擎原生 track 机制**（2026-08-04 迁移，见
  [doc/plans/2026-08-04-quality-native-tracks-spike.md](plans/2026-08-04-quality-native-tracks-spike.md)）：
  `MovaKernel.videoTracks`（`core/kernel/kernel.dart`）流出 mpv 解析出的变体
  （已过滤掉 mpv 的 `id:'no'`"关闭视频"条目），`loadQualities()` 等它首次非空
  推送后用纯函数 `qualitiesFromVideoTracks`（`core/model/quality.dart`）按高度
  去重、排序、补"自动"档；`switchQuality(q)` 对带 `trackId` 的档位调
  `MovaKernel.setVideoTrack`——同会话切换，不重开源。**真机实测：比重开快，但
  不是真正无缝**（点击瞬间暂停，约 1 秒后 loading，随后恢复），预期要按"更快"
  而非"零卡顿"来对外描述。
- `parseHlsMasterPlaylist(content, base)` 已删（无生产调用点，公开 API 破坏性删除，
  见计划文档 T7）——`loadQualities()` 不再自己拉取/解析 m3u8。
- **非自适应多源（如按清晰度分开的独立 mp4 文件）走旧的重开路径**：
  `MovaQual` 带 `uri`（非空）而非 `trackId` 时，`switchQuality(q)` 走
  `_kernel.open(q.uri)` + 点播下 seek 回位——这条路径目前没有生产者接入
  （`MovaSource` 还没有多源字段），是预留分支。
- `switchQuality(q)`：保留播放态，点播下保位续播（两条路径都遵守）。
- ABR 策略是 `MovaAbrConfig.policy`（类型 `MovaAbrPolicy`，位于
  `core/options/abr_config.dart`，不是 DESIGN 文档原设想的
  `core/model/abr.dart`）；省略时默认 `MovaBufferAbr(threshold: stallThreshold)`。
  自动档不降档（交给 libmpv 原生 ABR）；`downshiftQuality()` 现在按
  `trackId ?? uri` 定位当前档在 `state.qualities` 里的下标，对两条切档路径
  都适用。

## 直播时移（阶段 C）

- 三种模式（`MovaLiveConfig.seekMode`）：`off`（默认，禁拖）、`dvr`（服务端滑动
  窗口内拖，复用内核原生 seek）、`timeshift`（拖动即用 `urlBuilder` 重开源）。
- 窗口解析优先级（`resolveWindow`，`lib/src/core/live/timeshift.dart`）：
  `MovaLiveConfig.windowResolver` > `dvrWindow` > 内核报告的 `duration`。结果
  clamp 到非负。
- `behindOf(position, window, edgeThreshold)`：落后边缘的时长在 `edgeThreshold`
  （默认 10s）以内、或窗口未知/为零、或 `position` 已到/超过窗口末端时一律返回
  `null`（视为"在边缘"），否则返回落后量。`atLiveEdge` 是其取反的语义封装。
- `MovaState.timeshiftBehind` 在写入前先按**整秒量化**——position 每秒回调多次，
  不量化会让去重后的 `states` 流退化成高频流（阶段 A 特意把 position 排除在
  `MovaState` 之外的初衷）。落后量归零/变化时分别发 `MovaLiveEdgeReach`/
  `MovaTimeShiftChg`。
- `backToLiveEdge()` 的行为由 `MovaLiveConfig.effectiveBackToLive` 决定：显式配置
  `backToLive` 就用它，否则按 `seekMode` 推导（`timeshift` → `reopen`，其余 →
  `seekEnd`）。`reopen` 重开的是 `_source` 里保存的**原始**直播地址，而不是内核
  当前打开的时移地址。
- `autoBackToLiveOnStall`（默认关）：仅在**确实处于时移状态**且发生卡顿时才
  自动跳回边缘，避免悄悄丢弃用户主动选定的回看位置。
- UI 树 `bottomBar/{liveBadge, seekBar, timeshift, backToLive}`：`SeekBarComponent`
  对可拖直播取 `seekableWindow` 而非 `duration`（同一组件同时服务 VOD 与直播）；
  `liveBadge` 按 `timeshiftBehind == null` 在红色 `LIVE`/灰色 `时移`（`MovaTheme.
  timeshiftBadgeColor`）间切换；`backToLive`（原 `backToEdge`，已删除并改名）
  调 `backToLiveEdge()` 而非 `reload()`。

## 无缝引擎切换（0.4.0，默认关闭）

- `MovaSwapEngine`（`lib/src/core/swap/swap_engine.dart`）本身实现 `MovaApi` +
  `MovaSwapCtl`：宿主把它交给 `MovaPlayer`，UI 只认这一份稳定的对外面；它自持
  `MovaBus<MovaState>` + 三个 broadcast controller，把订阅从旧引擎重接到新引擎——
  **绝不直接转发 `active.states`**，否则组件在 `initState` 里订阅的流会在换引擎后死掉。
- `MovaOpts.swap`（`MovaSwapConfig`）默认 `enabled: false`；关闭时 `MovaSwapEngine`
  是纯直通代理，永不创建影子引擎，每个能力方法原样转发给工厂产出的唯一引擎。
- 预热拆成两层可插拔纯逻辑（脱离 Flutter/内核，单测覆盖）：
  - **触发策略** `MovaWarmTrigger`（`lib/src/core/swap/trigger.dart`）：
    `MovaLeadWarm`（按 `remaining`/`total` 倒推，短于 `minWarmDuration` 的片段
    一律不预热）用于可预测切换点（广告）；`MovaEagerWarm`（恒真）用于不可预测切换点
    （`swapTo`／未来的清晰度热切换）。
  - **就绪判据** `MovaWarmPolicy`（`lib/src/core/swap/warm.dart`）：`MovaBufferWarm`
    是 `MovaBufferAbr` 的镜像——后者数缓冲上升沿判"该降档"，前者数连续 `stableTicks`
    次"已到达目标位置 + 未卡顿 + 已缓冲 `lookahead`"判"可以切"；`elapsed >= timeout`
    时返回 `giveUp`（调用方据此拆影子、回落普通 `open()`），优先级高于 `ready`。
- `MovaState.renderEpoch`：普通 `MovaEngine` 恒为 0；`MovaSwapEngine` 每次 `commit()`
  成功后递增，`_RenderSurface` 的 selector 纳入它以强制重读 `renderHandle`
  （`lib/src/ui/player.dart` 的 `_RenderSurface`，selector 从 `(fit, zoom)` 扩为
  `(fit, zoom, epoch)`）。
- 原子切换顺序（`MovaSwapEngine._commitNow`）：`active.pause()` → 影子
  `setVolume(active.state.volume)` → 影子 `play()` → 转发订阅从旧引擎重接到新引擎
  → `active`/`renderEpoch` 换指 → `unawaited(old.dispose())`（先换指再释放，释放是慢
  的原生调用，不能挡在换指前面）。
- `MovaAdCtrl` 新增可选 `swap` 构造参数（应为同一个 `MovaSwapEngine` 实例）：广告播放
  期间每个 progress tick 都调 `swap.prepare(content, at: 续播点, cue: ...)`；
  `_playContent` 先 `swap.commit()`，成功则跳过 `open`/`seek`，失败回落今天的路径；
  `_playAd` 开头 `swap.abandon()`（丢弃为上一条广告预热的影子）。不传 `swap` 时行为
  与 0.3.0 逐字节一致。
- **清晰度切换未接入**：`MovaEngine.switchQuality()` 的语义已与
  `swapTo(MovaSource(uri), at: position)` 一一对应，但只做了接口形状契约测试
  （`test/core/swap/swap_engine_test.dart` 的 Task 8 分组）+ 落点注释
  （`engine.dart` `switchQuality()` 上方），真正接入时还差一件事：影子引擎起步时
  `currentQuality`/`qualities` 为空，转正后需重新播种。
- **feed 引擎池明确排除**：`core/feed/engine_pool.dart` 的拖拽场景要求两页画面
  同时在渲染树上连续插值（双画面并存），结构性不适用本模型的单渲染面离散替换；
  两者仅共享 `MovaEngineFact` 这一条底层原语。
- **真机验证未做**：黑屏是否真的消除、中插续播点误差、内存/解码 session 三阶段采样、
  短广告降级路径、断网预热超时兜底，均需真机逐项验证，详见
  [doc/plans/2026-09-16-seamless-swap.md](plans/2026-09-16-seamless-swap.md) Task 11。

## 广告编排增强（0.5.0）

**一句话结论：不新建任何预热机制。** `MovaWarmTrigger`/`MovaWarmPolicy`/`MovaSwapEngine`
三个抽象**零类型改动**直接复用，"正片背后暖广告"只是把同一套 `prepare` → 就绪判据 →
`commit` 用在另一个方向上；`MovaSwapCtl` 的 `prepare`/`commit`/`abandon`/`swapTo` 四个
动词语义已经够用，**不新增任何方法**。

| 抽象 | content→ad 方向怎么用 | 改动 |
|---|---|---|
| `MovaWarmTrigger` | 用 `MovaEagerWarm`（delay 窗口的全部意义就是拿来预热） | 零 |
| `MovaWarmPolicy` | 用 `MovaBufferWarm`，`target: 0`，超时取 `adReadyTimeout` | 零 |
| `MovaSwapEngine` | `prepare(ad, at: 0, plan: …)` → `commit(waitForReady: true)` | 接 `plan` |
| `MovaSwapCtl` | 两段式服务中插，一次式 `swapTo` 服务前/后贴片 | `prepare` 加 `plan` |

唯一的接口增量是 `MovaWarmPlan`（`core/swap/plan.dart`）：把"本次预热用哪个触发策略、
哪个就绪判据、就绪后是否停在起点"这三件**每次预热各不相同**的事从全局 `MovaSwapConfig`
里解耦出来。同一个 `MovaSwapEngine` 实例现在要跑两个方向的预热，三者取值都不同：

| | ad→content（0.4.0） | content→ad（0.5.0） |
|---|---|---|
| 触发 | `MovaLeadWarm(lead: 2s)` | `MovaEagerWarm()` |
| 超时 | `MovaSwapConfig.readyTimeout`（8s） | `MovaAdConfig.adReadyTimeout`（5s） |
| 就绪后停住 | 否（一路播着等 commit） | **是**（广告必须从第 0 帧给用户看） |

把它们塞进 `MovaSwapConfig` 等于让通用切换模块知道"广告"这个概念，正是要避免的耦合方向。

### 是否等待就绪：按 kind 取默认值

**判据：等待的价值，等于等待期间屏幕上那张画面的价值。** `MovaAdWaitByKind` 默认
`pre: false` / `mid: true` / `post: false`——中插期间屏幕上是用户正在看的正片，前/后贴片
期间没有正在进行的观看体验需要保护。三层覆盖**全部收在 `MovaAdConfig.waitsFor()` 一处**：

```
break.waitForReady ?? config.waitForAdReady.waitFor(break)
```

`ad_controller.dart` 里**不许出现任何与等待相关的 `kind` 判断**，否则宿主的覆盖就绕不
过去了（`openness_ad_test.dart` 把三层各自都能生效做成了可执行断言）。

"等待"与"`delay` 倒计时"是两件独立的事：前者用户不可见、上界是 `adReadyTimeout`；后者
是宿主指定的可见倒计时。`delay == 0` + 等待正是中插的**默认形态**（无角标）。两者同时
开启时接管时刻是 `max(倒计时走完, 广告就绪)`。

**这不破坏"默认行为不变"**：等待要真正发生需同时满足宿主传了 `swap`、
`MovaSwapConfig.enabled` 为 true、且解析结果为等待——前两件 0.4.0 默认都是关的。

### 不依赖媒体时间轴（硬约束）

`delay` 与 `duration` 的到期一律用 `Timer` 判定，到期后走与 `skip()` 完全相同的同步续播
路径。**任何一处都不许用 `MovaDone`、`state.duration` 或 seek 到素材尾部来实现这两个
语义**：真机上临近真实 EOF 的 seek 会可靠卡死 mpv/media_kit，大文件时长在真机网络下可能
长时间解析不出来。`_resuming` 守卫保证 duration 到期、素材 `MovaDone`、用户 `skip()`
三条路撞在同一 tick 时只续播一次。

### 状态机：三态变四态

新增 `_Phase.pending`——广告已到期但尚未接管、正片刻意继续播放。此阶段不得再触发别的
中插；续播点跟随实时位置，因此取到的是广告**真正接管那一刻**的位置。pod 内只有第一条
会经过 `_beginDelay`，后续几条由 `_nextPodMid()` 直接串联（同一插入点 = offset 不晚于
续播点），这同时修掉了"中插 pod 根本没串联、会闪回正片"的既有缺陷。

### 顺带修掉的 0.4.0 潜伏缺陷

1. 注入的 `readyPolicy` 每次预热都是同一实例却从不 `reset()`，第二次预热会继承上次的
   连续 tick 计数，一次侥幸 tick 就能提交切换。
2. `at == Duration.zero` 仍下发一次无意义的 `seek(0)`——刚 `open()` 完就 seek 是纯粹的
   风险敞口。
3. 影子引擎的 `MovaErrorEvent` 从未被监听，加载失败会一直预热到超时。

### 与代码的对应

| 文件 | 职责 |
|---|---|
| `core/swap/plan.dart` | `MovaWarmPlan` |
| `core/ad/fail.dart` | `MovaAdFailKind` / `MovaAdFail` / `MovaAdFailAction` / `MovaAdFailPolicy` / `MovaAdRetrySkip` / `MovaAdAbandonPod` |
| `core/options/ad_config.dart` | `MovaAdWaitPolicy` / `MovaAdWaitByKind` / `MovaAdNotReady` + 7 个旋钮 + `waitsFor` / `effectiveWarmPlan` / `effectiveFailPolicy` |
| `core/model/ad.dart` | `delay` / `duration` / `waitForReady` / `assertValid()`；`MovaAdEventType.pending`/`.failed`；`MovaAdEvent.error` |
| `core/model/source.dart` | `MovaSourceResolver` |
| `core/ad/ad_controller.dart` | `_Phase.pending`、三条定时器、延迟源解析、就绪等待编排、失败兜底 |
| `ui/components/ad_overlay.dart` | delay 倒计时角标 |

> **`assertValid()` 为什么是方法而不是构造器 assert**：`MovaAdBreak` 是 `const` 的，而
> Dart 的常量求值器无法比较 `Duration`——`>`、`==`、`.inMicroseconds` 它都不支持——写成
> 构造器初始化列表里的 `assert` 会让**每一处** `const MovaAdBreak(...)` 都变成编译错误
> （合法的也不例外，实测如此）。改为由 `MovaAdCtrl` 在 `load`/`loadDeferred` 时逐条调用，
> 保留"开发期大声失败、release 零成本"，放弃的只是"编译期失败"。

- **真机验证未做**：等待是否真的消除黑屏、`adReadyTimeout`/`loadTimeout` 默认值是否合理、
  双活解码窗口在中低端机上的表现、坏 URL 在真机上以哪种形式报出来、`duration` 对超长素材
  是否真的不卡死，均需真机逐项验证，详见
  [doc/plans/2026-09-16-ad-swap-enhancements.md](plans/2026-09-16-ad-swap-enhancements.md)
  Task 12。

## App 内小窗（MovaMini，0.6.0，默认关闭）

在不依赖任何系统 PiP API 的前提下，让画面从页面里"缩"成一个可拖拽的悬浮小窗——不重新
解码、不黑屏。默认关闭（`MovaMiniConfig.enabled` 为 `false`），四端通用。

**与系统 PiP / 系统悬浮窗的三方关系（互斥矩阵）**：

| | 画在哪 | 权限 | 与 mova 的关系 |
|---|---|---|---|
| `enterPip()`（系统 PiP） | 系统 WindowManager，App 之外 | Android 需系统支持 | `MovaState.pip` |
| `flutter_overlay_window` 类系统悬浮窗 | 同上 | `SYSTEM_ALERT_WINDOW` | 未接入，与本功能正交 |
| App 内小窗（本节） | Flutter 绘制树内，**不出 App** | 零权限 | `MovaState.mini` |

`MovaState.mini`/`pip`/`fullscreen` 三者：`mini` 与 `pip` 正交（各自独立的 bool，互不清
对方）；`mini` 与 `fullscreen` 互斥——`MovaEngine.setMini(true)` 在 `state.fullscreen` 为
真时会先 `setFullscreen(false)`（先发 `MovaFullScreenChg` 再发 `MovaMiniChg`），反向
`setMini(false)` **不会**恢复全屏。

**为什么不重新解码**：`MovaApi`/`MovaEngine`/`MpvKernel` 是纯 Dart 对象，生命周期与
widget 树无关；`_RenderSurface` 每次 build 都重读 `api.renderHandle` 并按
`_RenderHandleKey(handle)` 做 key——句柄没变，Flutter 复用同一个 `Texture`。
`test/ui/player_test.dart` 有一条"同一 api 在两个树位置先后挂载，renderHandle 不变"的
契约测试，是这条命题在单测层面能做到的最强证明（真机验证见下）。**硬约束**：同一时刻
只允许一个 `MovaPlayer` 持有该 api 的渲染面，`MovaMiniCtl`/`MovaMiniMount` 负责互斥。

**两种挂载方式的分工与 `MovaMiniMount` 互斥规则**：

| | 方式 A · 页内悬浮 | 方式 B · 跨路由持久 |
|---|---|---|
| 入口 | `MovaMiniCtl.showInPage(context, api)` | `MovaMiniCtl.show(api)` + `MovaMiniHost` |
| 挂载 | `Overlay.of(context, rootOverlay: false)` 插 `OverlayEntry`，mova 实现 | 宿主级 `Stack`，mova 只给便利壳 |
| 生命周期 | 跟随该页面（page 被 pop，小窗随之消失） | 独立于路由栈 |
| `MovaMiniCtl.mount` | `MovaMiniMount.page` | `MovaMiniMount.persistent` |

`MovaMiniHost` 只在 `mount == persistent` 时渲染，`page` 时渲染空——避免宿主同时接了
`MovaMiniHost` 又调 `showInPage` 时出现两个渲染面。`MovaMiniMount` 是纯 UI 层枚举，
不进 core（core 只关心 `MovaState.mini` 这一个 bool）。

**不可回退的架构约束**：`MovaMiniWindow` 挂载无关——自身是撑满外部约束的 `Stack`
（`LayoutBuilder` 取 `bounds`，不用 `MediaQuery.size`），永远不许自己是 `Positioned`；
两种外壳（`OverlayEntry` / `Positioned.fill`）只是"把它放到哪里"的差异，
`test/ui/mini/mini_mount_test.dart` 的等价性用例是这条约束的可执行守卫。

**落点纯逻辑**（`core/mini/placement.dart`，零 Flutter 依赖）：`MovaMiniRect`/
`MovaMiniInsets` 是 `Rect`/`EdgeInsets` 的极简 core 层替身；`clampToBounds` 每帧拖动都用，
`MovaCornerSnap.settle` 只在松手时用——垂直方向永远只钳制不吸边，快速水平甩动优先于
中心位置判据（惯性优先）。

**误用防护**：`MovaMiniCtl.isShowing(api)` 让页面 `dispose()` 前自检；
`MovaEngine.dispose()` 在 `state.mini == true` 时打一条 debug-only `assert`（release
零成本）。`MovaMiniCtl._detachEntry()` 单点收口 entry 摘除，`entry.mounted` 判据防止
宿主 Overlay 先于 ctl 死亡（页面被 pop）导致的重复 remove 崩溃。

**"点画面"手势不再硬编码（2026-09-24 真机验证发现问题后改动）**：早期实现里点击小窗
画面内容会直接调 `ctl.hide()`，真机验证时发现——没有配套"回到整页"UI 的宿主页面上，
这看起来就是"点一下小窗就凭空消失了"，容易被误当成关闭。改为 `MovaMiniCtl.onTapContent`
（`void Function(MovaApi api)?`）回调，默认 `null`（点画面无效果，只有关闭 ✕ 按钮能收起
小窗），宿主需要"点画面回整页"效果时自行接 `ctl.onTapContent = (api) => ctl.hide()`。
关闭按钮的行为不受影响，始终调 `MovaMiniCtl.close()`。

**Windows 桌面真机验证部分完成**（计划 Task 12，2026-09-24，`--no-enable-impeller`
强制 Skia 后端）：A–F 六组用户手工目测均通过（A 组未记录具体
`position`/`renderEpoch` 数值,不满足"基于真实事件数字"的项目约定；其余五组
正常）。Android 专属三项（转屏钳回、切后台再回前台、与系统 PiP 互斥）本轮无
设备连接,未测。验证中顺带发现并修复一个 demo 自身次生 bug：`_MisuseDemoState`
触发 assert 后若同一帧内又导航，新引擎事件流回调会在 widget 树锁定期间同步
刷新 `_eventLog`，已改用 `addPostFrameCallback` 推迟通知。checklist 见
[doc/plans/2026-09-23-app-inline-pip-overlay.md](doc/plans/2026-09-23-app-inline-pip-overlay.md)。

**⚠️ 2026-09-24 Windows 真机验证发现一个未解决的原生崩溃**：`mini_window_demo`
在播放中途（非引擎刚创建时）100% 概率触发 `0xc0000005` 访问越界，故障模块是
自研瘦身版 `libmpv-2.dll`，Windows 事件日志三次复现故障偏移完全一致
（`libmpv-2.dll+0x94d927`）。**已排除**：不是 `doc/plans/2026-09-17-windows-libmpv-slim.md
§13` 那个已用 clang 修复的 `mpv_create()` 崩溃（那个崩在引擎创建时，这个崩在
播放中途，代码位置也不同，且 CI 日志确认当前 dist/ 产物确实是 clang 编译的）；
不是网络流本身（裸 `media_kit` `Player` 播放同一 URL 不崩）；不是小尺寸渲染面；
不是 `createMovaEngine()`/`MovaPlayer` 封装本身（全屏播放不崩）；不是
`showInPage()` 挂载动作本身（自动触发不崩）；不是 `MovaMiniCtl.show()` 后紧跟
`Navigator.pop()` 的路由转场竞态（自动化复现该精确时序不崩）。**崩溃似乎只在
真人鼠标/拖拽交互下触发**，自动化模拟同样的状态变化走不到那条代码路径。
故障地址（RVA `0x94d927`）落在静态链接的 ffmpeg/libav 内部代码里（远超 mpv
自身导出符号地址区间 `0x92xxxx`），dll 是 `minsize` 编译无调试符号，反汇编看
不出函数名，需要本地重建一份带符号的 dll 配合 cdb/gdb 才能拿到真实调用栈。
已配置 `HKLM\SOFTWARE\Microsoft\Windows\Windows Error
Reporting\LocalDumps\mova_example.exe`（`DumpFolder` 指向
`mova/_crash_dumps/`，`DumpType=2` 全量转储，`DumpCount=5`）收集崩溃转储，
配置保留未还原，供下次复现时直接抓 `.dmp`。

**2026-09-24 追加：找到强关联规避手段，但未拿到调用栈级根因**。Flutter 3.47
起 Windows 桌面端 Impeller 已非纯 opt-in（`svgx` 子工程已记录
`EnableImpeller=false` 在 3.47 上仍有效），并非本项目此前假设的"桌面端默认还
是 Skia"。用 `flutter run -d windows --no-enable-impeller` 强制走 legacy Skia
后端启动 `mini_window_demo` 后，同样的"播放中途 + 真人鼠标拖拽小窗"场景连续
**3 次以上**未复现崩溃（此前同样场景 100% 必现）。指向 libmpv 的 GPU 渲染
句柄/纹理与 Impeller 渲染后端（猜测是其 ANGLE/D3D 层）交互时的资源竞争或生命
周期问题，但：① 样本量仍小，只是"必现→多次未现"，**未严格排除低概率复现**；
② **未定位到具体触发机制**——本轮未复现崩溃，`_crash_dumps/` 里没有新增
`.dmp` 可供对照分析，无法确认是否真的是同一条故障路径被规避，还是恰好没撞上。
下一步：分别在 Impeller 开/关两种状态下各拿一次崩溃（或"多次不崩"）的转储，
配合带符号 dll 比对调用栈，才能真正定论。**注意区分**：`_MisuseDemo` 页面故意不检查
`isShowing` 触发 `MovaEngine.dispose()` 的 debug-only assert 时，因为
`dispose()` 是 async 但 `State.dispose()` 没 await 它，assert 失败会变成未捕获
的 Future 错误直接杀死整个 isolate——**表现为窗口无声消失、无崩溃弹窗、无
原生崩溃日志**，和上述真正的原生崩溃（有 `0xc0000005` 事件、故障模块是
`libmpv-2.dll`）是两回事，靠"有没有 Windows 崩溃弹窗/事件日志"可以区分。
后者已在 `mini_window_demo.dart` 里补了 `catchError` 上报，不再杀死整个 app。

## 仅音频模式（`audioOnly`，0.4.x，默认关闭）

`MpvKernel({bool audioOnly = false})` / `MovaEngine({bool audioOnly = false})` /
`createMovaEngine({bool audioOnly = false})`。为 `true` 时**不建立任何视频管线**，
`renderHandle` 为 `null`。**不新增任何公开类，barrel 一行未改。**

**机制**：media_kit 的 `Player` 一创建就是 mpv 的 `--vid=no`
（`player/native/player/real.dart` 的 `_create()`），**只有** `VideoController.create()`
会把它改回 `vid=auto`。所以核心改动就是把 `MpvKernel` 构造里那句无条件的
`VideoController(_player)` 包进 `if (!audioOnly)`——不建那个对象，libmpv 就已经是纯音频
播放器：解码帧缓冲、GPU 纹理、Flutter `Texture` 注册这三项是 0 而不是变小。
**这依赖 media_kit 1.2.6 的默认值，升级 media_kit 时须重验此条**
（`test/core/audio_only_test.dart` 有两条源级结构守卫钉住 `if (!audioOnly)` 这层包裹）。

三条设计决定及其理由：

- **不进 `MovaOpts`**。`MovaOpts` 的语义是运行期可 `copyWith` 替换的配置（12 节全部
  如此），而 `audioOnly` 是**引擎构造期一次性的资源决策**：内核的渲染句柄一次绑定、
  永不重绑，`copyWith(audioOnly: true)` 无法生效，放进去等于造一个骗人的口子。
  `test/core/openness_audio_test.dart` 有一条反对账测试，钉死配置节数量仍是 12。
  运行期可观测的信号就是 `renderHandle == null` 本身，因此也没有 `MovaState.audioOnly`。
- **不加 `MovaStreamType.audio`**。"音频"是引擎的资源形态，不是源的流类型。同一条
  `audioOnly` 引擎既能放 vod 音频也能放 live 音频；同一条纯音频 URL 也完全可以在普通
  引擎上播（只是白背视频管线）。两者正交，混进 `MovaSource` 会造出 2×2 的无意义组合。
- **不换 `media_kit_libs_*_audio`**。那是编译期二选一，换了 mova 的视频功能会物理失效，
  与"既要视频又要音频"的目标用户直接冲突。包体积因此不随模式变。

**`MpvFrameExtractor` 的处置**：`createMovaEngine()` 原本无条件注入它，而它在首次
`extract()` 时会新开**第二个** `Player` 并为其建 `VideoController`——一整条额外的视频
管线。`audioOnly: true` 时默认不再注入（`extractor ?? (audioOnly ? null : MpvFrameExtractor())`），
宿主显式传入的 `extractor` 仍然胜出。`MpvKernel.screenshot()` 在 `audioOnly` 下短路返回
`null`，让拖动预览兜底走既有的"抽帧器没给结果 → 平滑降级"路径，而不是抛 mpv 错误。

**UI 层零改动**：`_RenderSurface` 的 `handle is VideoController` 三元判定天然把 `null`
落进 else 分支拿到黑色占位；音频场景的封面/波形/歌词面直接用 `MovaPlayer.surface`
这个已有口子传入，因此**不做 `MovaAudioSkin`**。

**明确不做**：`MovaAudioSkin`；后台常驻/锁屏/通知栏/耳机线控/音频焦点/gapless/歌单
这一整套系统集成面——分流判据是"需不需要熄屏后台常驻 + 系统媒体控制"，需要就走
`just_audio` + `audio_service`。

**真机验证未做**：功能正确性、三阶段 `dumpsys meminfo` 内存对账、`vid` 属性直接确认、
电量/CPU 抽查、关闭态回归，均需真机逐项验证，详见
[doc/plans/2026-09-16-audio-only.md](plans/2026-09-16-audio-only.md) Task 5。
README 与可行性笔记 §1 里的开销数字目前仍是**推算量级，不是实测**。

## PiP（原生）

- Dart 侧经 `MovaPipPort`；Android `MovaPlugin.kt` 用
  `PictureInPictureParams`，宽高比 `clamp(0.42, 2.39)`；iOS/桌面未实现，
  `isPipSupported()` 返回 `false`。
- **iOS 系统 PiP：待定任务（未完成）**。可行性已调研，方向为
  `AVSampleBufferDisplayLayer` + `CVPixelBuffer`（Android 是 Activity 级 PiP，无需取帧；
  iOS 必须自渲染取帧）；落地卡在一次需 Mac + iOS 15+ 真机的门槛 spike。**契约维持不变**：
  落地前 `isPipSupported()` 仍返回 `false`、`PipButtonComponent` 自动隐藏；落地后仅原生
  返回值变化，Dart/UI 零改动。完整研究 + 落地计划见
  [doc/notes/2026-07-31-ios-pip-feasibility.md](notes/2026-07-31-ios-pip-feasibility.md)。
- `MovaState.pipSupported` / `MovaApi.pipSupported`（阶段 C）：engine 构造后不久
  用 `MovaPipPort.isSupported()` 探测一次（默认 `false`，探测失败也归约为
  `false` 而不抛出）；`PipButtonComponent` 据此隐藏自身，不支持的平台上按钮
  根本不出现，而不是出现了点了没反应。

## 全屏（桌面平台的已知边界）

`SystemChromeOrientationPort`（`MovaOrientPort` 的默认实现）只处理移动端的
方向锁定与沉浸式系统 UI；Windows/macOS/Linux 上没有"真全屏"的对应概念（撑满
屏幕、去掉标题栏），因此 `setFullscreen(true)` 在桌面端不会有可见效果——2026-07-31
Windows 实跑证实。这不是回归，是能力从未在桌面实现过。mova 不内置窗口管理
依赖（如 `window_manager`），桌面真全屏留给宿主接：`setFullscreen()` 每次调用都会
在 `MovaApi.events` 上发 `MovaFullScreenChg(bool)` 事件，与 `MovaOrientPort`
无关，宿主监听后自行调用窗口管理 API 即可（见 README「平台端口」一节示例）。

### 强制横竖屏（0.3.0）

`MovaApi.setOrientation(MovaOrient)` 是独立于全屏的方向能力：`MovaOrient.auto`
保持上文「全屏按宽高比定向」的行为，`portrait`/`landscape` 无视宽高比与全屏状态
强制该方向，写入 `MovaState.orientation` 并发 `MovaOrientChg`。落点在
`MovaOrientPort.apply` 新增的 `orientation` 参：`resolveOrientations()`
（`orientation_impl.dart`，已抽出纯函数单测）在 `auto` 时回退到
`preferredOrientationsFor(w,h)`，否则直接取横/竖屏对。engine 侧由 `_applyOrientation()`
统一根据 `state.fullscreen + state.orientation` 应用，`setFullscreen`/`setOrientation`
/尺寸到达三处共用它。UI 侧 `OrientationButtonComponent`（顶栏，name
`orientationButton`）仅在 `defaultTargetPlatform` 为 Android/iOS 时渲染——桌面端强制
方向本就无效，与 pip 按钮的隐藏思路一致——点击经 `MovaOrient.toggled` 横↔竖切换。

## 预设皮肤：bilibili 点播 / 抖音风 feed

两套开箱即用的皮肤，落地于 0.3.0 插件化架构之上（未单独编版本号，落地日期
2026-08-01）。

- **`MovaBilibiliSkin`**（`ui/skins/bilibili_skin.dart`）：`extends MovaDefSkin`，
  纯"补丁档"定制（`MovaPatch.add`/`insertAfter`），零布局改写——bilibili 的默认
  控制条与手势侧别（左亮度/右音量）本就对齐 0.3.0 默认值。新增
  `DanmakuTrackComponent`（`ui/components/danmaku.dart`，挂 `MovaSlot.overlay`，
  不受锁定/自动隐藏门控）+ 顶栏 `SpeedButtonComponent`（`ui/components/
  speed_button.dart`，`0.5x~2x` 六档循环，走既有 `MovaApi.setRate`，未新增 core
  能力）。**倍速按钮落在顶栏而非底栏**：`TopBarComponent.build()` 用
  `...children.sublist(1)` 展开全部子节点，而自适应的 `BottomBarComponent`
  按下标显式取子节点（`children[0]`/`children[2]`/`children[4]`），补丁插入的
  新兄弟节点会被静默丢弃——这是从 `BottomBarComponent` 现有实现读出的真实约束，
  非设计偏好。
- **弹幕（`MovaDanmakuConfig`/`MovaDanmakuItem`）**：**只做展示**，无发送框/输入/
  去重限流引擎（`MovaOpts.danmaku`，默认 `enabled: false`）；`items` 是宿主给
  的固定列表，按 `time` 触发滚动、按 `trackCount` 轮询分轨（非完整防重叠）。
  "弹幕开关"按钮本期**未做**——`enabled` 是构造期配置，非运行时可切换状态，
  加运行时开关需要一个新的本地 UI 状态承载点，本期从简未做，留待后续。
- **`MovaFeedPlayer`/`MovaDouyinSkin`**（`ui/feed_player.dart`/`ui/skins/
  douyin_skin.dart`）：纵向"上滑下一个视频"feed，**引擎池架构**——
  `MovaFeedEnginePool`（`core/feed/engine_pool.dart`）持有最多 `poolSize`
  个 `MovaApi`，每个热页一个自己的引擎与渲染画面；`MovaFeedCtrl`
  （`core/feed/feed_controller.dart`，纯 Dart，无 Flutter 依赖）驱动这个池
  在 feed 中前进。两者都不依赖 Flutter，可单测。
  - **推翻了此前的单引擎决策**（2026-08-02）。原决策依据是"并行引擎池每活跃
    实例约 50-100MB 内存 + 硬解并发 session 数（很多中低端 Android SoC 只支持
    1-2 个）"，于是改为单引擎反复 `open()`。但单引擎在切页瞬间有两个躲不掉的
    瑕疵：冷 `open()` 会清空共享画面（**黑屏一闪**），而任何原地复用同一
    Surface 的快速路径（当时的 `queueNext`+`Player.next()`）都会把**上一条
    最后解码的那一帧**留在屏幕上，直到新一条的帧覆盖它为止。两者当时只能靠
    一层定时黑遮罩（`switchMaskDuration`，150ms 猜测值）桥接——那是猜测，
    不是修复，真机连续快切时仍会露。改用引擎池后，观众正在滑向的那页早已在
    自己的引擎上打开、停在自己的画面上，**两个瑕疵都从根上不成立**，遮罩连同
    `switchMaskDuration` 参数一起删除。采纳前用 `example/lib/spike_dual_engine.dart`
    在 Android 真机按 `dumpsys meminfo` 分三阶段（单引擎基线 / 加一个预热引擎 /
    释放后回收）实测过增量，结论是可接受。硬解 session 数的顾虑仍在，因此
    `poolSize` 保持宿主可配（默认 3，内存吃紧可降到 2）。
  - **`MovaApi.queueNext`/`MovaKernel.queueNext` 与 mpv `prefetch-playlist` 已删**：
    每页独立引擎后，单引擎内部的 playlist 预取无意义。
  - **窗口与淘汰**：`movaFeedWindow(center, size)`（纯函数，可单测）以活跃页为
    中心向外展开、**向前优先**（`[c, c+1, c-1, c+2, …]`，奇数 size 对称，偶数
    多出来的一个放前方），负索引跳过而非钳位。池满时**按到目标索引的距离淘汰，
    不是 LRU**——刚划走的那页恰是"最近使用"却也最可能马上又要用，LRU 会淘汰错
    的那个。回收只解绑 + `pause()`，引擎实例放回空闲列表复用，**不 dispose**
    （每次上滑重建一次原生 Surface，等于把这套设计想省的开销又还回去）。
  - **就绪判据 = `open()` resolve，不是"首帧已渲染"**：media_kit 没有暴露可
    重复触发的首帧事件（`VideoController.waitUntilFirstFrameRendered` 是一次性
    `Completer`，池化引擎被复用于后续条目时不会再触发）。冷 `open()` 在帧尺寸
    确定前本就保持画面空白，因此用它近似。`MovaFeedSlot.ready` 为 `false` 期间，
    该页显示 `MovaFeedPlayer.placeholderBuilder`（宿主可给封面图/骨架屏，默认
    纯黑）**并照常渲染自己的 chrome**——chrome 组件读的是 feed 条目而非播放
    状态，因此用任意存活引擎撑起 `MovaScope` 即可。
  - **引擎所有权在 `MovaFeedPlayer`，不在宿主**：构造面从 `api:` 改为
    `engineFactory:`（宿主传 `createMovaEngine`）+ `poolSize`。池创建的每个引擎
    都由该 widget dispose——宿主根本拿不到它们，别处也无从释放。这是相对
    0.3.0 的 **breaking change**（feed 是未发布的新特性，代价可接受）。
  - **音频不重叠**：只有活跃页 `play()`，`MovaFeedEnginePool.focus(index)` 把
    其余所有已绑定引擎 `pause()`；预热邻居一律 `open(autoPlay: false)` 停在
    首帧。
  - **`NetworkWarmFeedPrefetcher` 保留，但只覆盖池够不到的更远条目**：
    `prefetchDepth` 范围内、已在引擎窗口里的索引会被跳过——那些正在被真正
    打开，重复发一次 Range GET 毫无收益。默认 `prefetchDepth: 1` + 默认
    `poolSize: 3` 的组合下，网络预取实际不发出任何请求。
  - **`MovaFeedCtrl.activate()` 对重叠调用做合并，不会与自己竞速**：
    快速连续 swipe 会在前一次 `activate(N)` 还没切完时就调用 `activate(N+1)`。
    即使有了引擎池，串行化依然必要：两次重叠激活会各自用自己的窗口调用
    `retain()`、再争抢空闲引擎，落败的一方可能把胜出方刚建立的绑定淘汰掉，
    出现 chrome 已显示 N+1、画面却卡在别处的问题。`activate()` 内部排队合并：
    任意时刻只有一路序列在跑，重叠调用只更新"接下来想要哪个索引"，进行中的
    循环收尾后自动去处理最新目标，处理到一半才发现已被取代的目标会被跳过。
    所有调用方（含过期的）都在真正收敛到最新索引后才一起 resolve。邻居预热
    同样带这个检查，一旦有新激活到来就中止。
  - **feed 到尽头（loader 返回 `null`）不再空转**：`_buildPage` 用一个
    `_requested` 集合记录已请求过的索引——否则"build 发起请求 → 没东西可缓存
    → `setState` → build 再发起同一请求"会无限循环（引擎池改造前就存在，
    旧测试只 `pump()` 两次没暴露，换成 `pumpAndSettle` 立刻打出来）。加载
    失败的索引会移出集合，后续重建仍会重试。
  - **默认 `fit: cover`**：池创建每个引擎时对其调用一次
    `setFit(MovaFit.cover)`（可经构造参数覆盖）——`contain` 会按每条视频的
    宽高比留出不同大小的黑边，每次上滑都像是尺寸跳了一下。**已知限制**：
    Android 上 `VideoControllerConfiguration.width`/`height` 明确无效（见
    media_kit_video 文档），解码输出的原生 Surface 必定按视频源分辨率
    设置——切到分辨率不同的视频时，底层 Surface 仍会 resize/重建一次，
    这与 `fit` 无关，是 media_kit_video 在 Android 上的实现限制，修复需要
    改其 Android 原生代码，mova 这层治不了。**引擎池顺带绕开了它的观感
    代价**：每页有自己的 Surface，那次 resize/重建发生在预热阶段（观众还在看
    上一条），而非切换瞬间。
  - **点赞状态 mova 端到端本地持有**（`MovaFeedItem.initialLiked`/
    `initialLikeCount`/`onLikeChanged`）：双击（`DouyinGestureLayerComponent`）
    与竖排点赞按钮（`LikeButtonComponent`）经同一个 `ValueNotifier`（由
    `MovaFeedPlayer` 的 State 按 index 缓存、跨该页历次重建存活）保持同步；
    `MovaFeedCtrl.toggleLike` 把切换结果写回条目缓存，滑走再滑回时仍是
    切换后的值；不做回滚，是否持久化交给 `onLikeChanged` 回调。评论/分享/
    头像/关注一律只是回调，mova 不持有这些业务状态。
  - **手势冲突靠"不引入组件"规避**：`MovaDouyinSkin.components()` 压根不挂载
    `GestureLayerComponent`（默认皮肤的亮度/音量竖滑手势），纵向拖拽完全归
    `PageView` 所有；这是组件化架构的直接收益，不需要任何特判代码。
  - **数据源**：`MovaFeedLoader = Future<MovaFeedItem?> Function(int index)`，
    异步按需解析，返回 `null` 表示 feed 结束；`MovaFeedCtrl` 内部按索引
    缓存去重并发加载。

新增测试：`test/core/model_test.dart`（`MovaDanmakuItem`/`MovaFeedItem`）、
`test/core/options_test.dart`（`MovaDanmakuConfig`/`MovaOpts.danmaku`）、
`test/core/feed_controller_test.dart`、`test/core/engine_pool_test.dart`
（`movaFeedWindow` 展开顺序/负索引、容量上限、距离淘汰、引擎复用不 dispose、
`focus` 只留一路播放、绑定被取代后不置 ready）、`test/core/feed_prefetcher_test.dart`
（真起 `HttpServer` 校验 Range 头，非 mock）、`test/ui/danmaku_test.dart`、
`test/ui/speed_button_test.dart`、`test/ui/bilibili_skin_test.dart`、
`test/ui/douyin_skin_test.dart`、`test/ui/feed_social_test.dart`、
`test/ui/feed_player_test.dart`。example 新增 `bilibili 皮肤`演示入口（原有
demo 列表第 6 项）与独立的 `DouyinFeedDemoPage`（AppBar 新图标按钮进入，三个
公开短 mp4 循环）。**均只在桌面跑过 `flutter test`/`flutter analyze`，未上
真机**——手势双击识别、`PageView` 纵向滑动手感、弹幕滚动的真实观感，均承接
本文档"真机验证结果"一节尚未覆盖的范围。

## 测试

- `test/core/`：`api_test.dart`/`bus_test.dart`/`compat_test.dart`/
  `engine_test.dart`/`interceptor_test.dart`/`kernel_contract_test.dart`/
  `model_test.dart`/`options_test.dart`/`ports_test.dart`/`purity_test.dart`
  （断言 `core/` 不 import Flutter）/`state_test.dart`/
  `openness_live_test.dart`（阶段 C，DESIGN §6.2 逐行对账）/
  `openness_preview_test.dart`（阶段 B，DESIGN §6.1 逐行对账）/
  `live/timeshift_test.dart`（阶段 C 纯函数）/`preview/`（阶段 B 全套：
  `models`/`hash`/`vtt`/`cache`/`disk_cache`/`two_level_cache`/`net_probe`/
  `vtt_source`/`extractor`/`service`）。
- `test/ui/`：`bottom_bar_test.dart`/`format_test.dart`/`gesture_test.dart`/
  `live_bar_test.dart`（0.3.0 起验证自适应底栏的直播态）/`orientation_test.dart`/
  `overlays_test.dart`/`player_test.dart`/`plugin_test.dart`（0.3.0 `MovaPlugin`）/
  `preview_test.dart`（阶段 B）/`selector_test.dart`/`skin_test.dart`/
  `top_bar_test.dart`/`tree_test.dart`。
- `test/platform_impl/`：`net_probe_impl_test.dart`（阶段 B）/`wiring_test.dart`。
- `test/method_channel_test.dart`：平台通道桩。
- `test/support/`：`fake_api.dart`/`fake_kernel.dart`/`pump.dart` 测试基础设施。

**实测结果**（0.3.0 插件化收口，2026-07-31 本机实跑）：**278 tests passed, 0
failed**。`flutter analyze` 0 issues。
`flutter pub publish --dry-run`：干净 git 状态下 **0 warnings**。
`test/core/purity_test.dart` 单独跑通过，`_mediaKitExceptions` 集合仍恰好是
`{'kernel/mpv_kernel.dart'}`。依赖清单核对：0.3.0 未新增任何依赖，仍是阶段 B 引入的
`path_provider`/`connectivity_plus` 加阶段 A 既有项。

## 命令

```bash
flutter analyze                                   # 校验（用 analyze，不用 build）
flutter test                                      # 单测
cd example && flutter run -d windows              # 桌面实跑（快）
flutter pub publish --dry-run                     # 发布校验
```

## 剩余任务（阶段 B/C/D，在另一台电脑继续时优先看这里）

阶段 A（本文档描述的 core/ui 分层重构）已完成并通过出口条件
（`flutter analyze` 0、测试全绿、功能零变化）。按
[DESIGN-0.2.0.md](DESIGN-0.2.0.md) §12：

1. **阶段 B：拖动预览缩略图——已完成**（2026-07-31）。文件清单：
   `lib/src/core/preview/`（`models`/`hash`/`vtt`/`cache`/`dir_provider`/`disk_cache`/
   `two_level_cache`/`net_probe`/`fetcher`/`source`/`vtt_source`/`extractor`/
   `platform_kind`/`api`/`service`）、`lib/src/core/options/preview_config.dart`
   （`MovaPrevConfig`）、`lib/src/platform_impl/`（`mpv_extractor_impl`/
   `net_probe_impl`/`thumb_dir_impl`）、`lib/src/ui/components/preview.dart`
   （`PreviewComponent`，挂 `MovaSlot.bottomAbove`，气泡水平位置随拖动比例跟随，
   钳制不越界）。新增公开面：`MovaApi.preview`（`MovaPrevApi`）、
   `MovaOpts.preview`（`MovaPrevConfig`）、`MovaPrevBlock` 事件；
   `createMovaEngine()` 新增 `thumbDir`/`extractor`/`fetcher` 三个可选参数。
   **抽帧路线**（见 `doc/plans/2026-07-31-phase-b-preview.md` 附录 A）：
   `screenshot-raw` 实测在 Windows 上不论 `vf=scale` 还是
   `VideoControllerConfiguration(width/height)` 都不能缩小输出，最终采用
   "原尺寸 + 不缩放兜底"，`frameWidth` 仅作为 cache key 与 UI 显示宽度参与量。
   212 项测试全绿，`flutter analyze` 0 issues。已知遗留：横滑手势路径与
   "关闭预览开关"两点未逐条人工验证（理论行为一致，见附录 B）；磁盘缓存按原
   分辨率 JPEG 估算，`diskMaxBytes` 默认 64MB 的余量比按缩略图估算的更紧张。
2. **阶段 C：直播时移——已完成**（2026-07-31）。见本文档「直播时移（阶段 C）」
   一节的实现现状；`ios/mova.podspec` 元数据已与 `pubspec.yaml` 对齐
   （**版本号必须手动同步**——`s.version` 不会自动跟 `pubspec.yaml` 的
   `version` 走，每次改版本都要同时改 podspec）；example 已加直播 DVR/时移
   两个 demo。
3. **阶段 D：收尾发布——进行中**。README/CHANGELOG/SPEC 已更新；
   `flutter pub publish --dry-run` 待最终校验；**真机一轮验证仍未做**
   （手势手感、HLS 联网切档、Android PiP 实际行为、iOS 整体播放、直播时移
   UI，均承自 0.1.0 尚未在真机验证，且本次 core/ui 重构与预览/时移两个新功能
   也从未上过真机——见文末「真机验证结果」一节）。**新增验证项**：iOS
   低端/老旧机型上 Flutter `Texture` 更新已知会阻塞 raster 线程的 bug
   （老设备上曾报告直接冻屏，`flutter/flutter#86613`）——mova 目前
   连普通 iOS 真机都未跑过，这条要专挑一台老机型单独测，不能假设新 iPhone
   跑通就代表没这问题。

**未来项（见 PRD ADR）**：实时语音转文字字幕（**可行性已评估 + 音频抽取 spike 已实测，
Android+iOS 落地中，见下**）+ AI MCP 集成钩子（仍为纯前瞻记录）。详见
[doc/PRD.md](PRD.md) 非功能需求/决策记录。

- **STT 字幕——2026-07-31 可行性评估 + spike 实测完成，Android+iOS 落地中**：完整调研
  见 [doc/notes/2026-07-31-stt-subtitle-feasibility.md](notes/2026-07-31-stt-subtitle-feasibility.md)
  （附录 A 是音频抽取分块的 spike 实测记录）。**结论：可行，不需要新增第三方依赖**。
  libmpv 无实时 PCM 抽头 API；音频分块抽取**不额外起第二个 media_kit `Player`**
  （spike 中 `Media(start:,end:)+stream.completed` 技术上跑通，但双播放器 CPU/内存
  翻倍，已否决），改用**各平台原生轻量抽取 API**（Android `MediaExtractor`+
  `MediaCodec`、iOS `AVAssetReader`+`AVAssetReaderTrackOutput`），在已有原生插件内
  一次调用完成"抽取 PCM→交给平台原生 STT（Android ML Kit GenAI Speech Recognition /
  iOS `SFSpeechAudioBufferRecognitionRequest`）→回文本"，PCM 字节不过 Dart 侧，减少
  一次 FFI/Channel 大数据搬运；回灌为字幕叠层组件。没有原生能力的平台（Linux）默认
  关闭，预期行为。分平台现状：Android/iOS 已有原生插件、扩展量级小，**先落地这两个
  平台**；**macOS 目前没有原生插件**（`macos/` 目录不存在），要从零搭建，暂缓；
  Windows 插件骨架是空壳，SAPI/COM 实现是真实原生工作量、无项目内先例，暂缓。架构
  延续既有端口抽象三件套（暂拟 `MovaSttEngine`，core 出抽象、`platform_impl/` 出各平台
  原生实现、无原生能力则 noop）。第一版曾建议默认依赖 whisper.cpp（FFI），已推翻。
  曾评估"MCP 兜底转写"，**已否决**（MCP 是请求/响应协议非实时流式，延迟不可控；且与
  MCP 钩子本该扮演的"被动暴露上下文"角色冲突）——缺口不专门补，复用既有
  `MovaVolumePort`/`CallbackVolumePort` 的注入模式给宿主一个通用 `MovaSttEngine` 口子即可。
- **MCP 钩子（与上方字幕功能解耦，不承担转写职责）**：预计不会成为核心依赖，更可能是
  一个可选的 `MovaHook` 实现或独立的事件流消费者，订阅播放状态/字幕文本等只读
  上下文，并可选择性地接收外部指令——是**被动**暴露/接受控制的角色，不用作"主动请求
  转写服务"（那条路已在字幕评估中否决）；核心库不直接依赖 MCP SDK，接入方式留给上层
  应用或独立扩展包。

以下两点是阶段 A 落地过程中相对 DESIGN 文档的已知偏差，供阶段 B/C 生成详细
计划时对照实际签名，不要盲目照抄 DESIGN 原文：

- `MovaAbrPolicy` 落在 `lib/src/core/options/abr_config.dart`，不是 DESIGN
  设想的 `lib/src/core/model/abr.dart`。
- `MovaApi.renderHandle` 是阶段 A 落地过程中新加的 getter（DESIGN 原文未提），
  用于让 `MovaPlayer` 在测试环境下渲染占位符而非真实 media_kit `Video`。
- `MovaState.sourceTitle` 是 `MovaState` 的字段，不是 `MovaApi` 上独立的 getter。
- `MovaPatch.add` 的 slot/order 处理在落地时做过修正，具体行为以
  `lib/src/ui/slots/tree.dart` 的 `applyPatches()` 实现与
  `test/ui/tree_test.dart` 为准。

关于 ffmpeg 瘦身（LGPL）与 iOS PiP：mova 就是 `fvideo` 改名/重构而来的
同一个工程，**fvideo 的遗留任务就是 mova 的任务**，全部承接：

- **二期 ffmpeg 瘦身（LGPL）——未开始**，独立里程碑，排在 0.2.0（阶段 A–D）之后。
- **iOS PiP 未实现**（libmpv 纹理限制，当前返回不支持），同样未取消，只是延后。
  **可行性已调研,方向定为 ASBDL + CVPixelBuffer,门槛 spike 需 Mac + iOS 15+ 真机。**
  研究 + 落地计划见 [doc/notes/2026-07-31-ios-pip-feasibility.md](notes/2026-07-31-ios-pip-feasibility.md)。
- **真机未验证**（手势手感、HLS 联网切档、Android PiP 实际行为、iOS 整体播放）
  承自 0.1.0，并入阶段 D 一并验证。
- **锁定态无法解锁**：`LockMaskComponent`（`lib/src/ui/components/overlays.dart`）
  的注释里早已写明这是刻意的范围缩减——只吞点击、不提供任何解锁交互，0.1.0
  "点一下锁屏图层短暂弹出解锁按钮"的完整流程被推迟。阶段 B Windows 实跑
  （2026-07-31）验证到：锁定后确实连 UI 都无法解锁，只能重启应用。留待阶段 D
  或后续打磨时补上最小可用的解锁交互（例如点击遮罩短暂展示解锁按钮、不点击
  则自动隐藏）。
