## 0.6.0

App 内小窗（`MovaMini`）：在不依赖任何系统 PiP API 的前提下，让画面从页面里"缩"成一个
可拖拽的悬浮小窗，不重新解码、不黑屏。默认 **关闭**（`MovaMiniConfig.enabled` 为
`false` 时全链路零行为变化）。

* **两种挂载方式并存**：`MovaMiniCtl.showInPage`（方式 A，页内悬浮，`OverlayEntry` 插入
  最近祖先 `Overlay`，随页面生灭）与 `MovaMiniCtl.show` + `MovaMiniHost`（方式 B，跨路由
  持久，`MaterialApp.builder` 下的 `Stack`）。核心逻辑收在挂载无关的 `MovaMiniWindow`
  （自身是撑满外部约束的 `Stack`，`bounds` 取 `LayoutBuilder` 约束而非
  `MediaQuery.size`），两种外壳只是"把它放到哪里"的差异。
* **core 层极薄改动**：`MovaState.mini`（与 `fullscreen`/`pip` 同构）、
  `MovaApi.setMini`（幂等、进入小窗隐式退出全屏）、`MovaMiniChg` 事件、
  `MovaMiniConfig`（默认值 + 配置项 + 可注入 `MovaMiniPlacement` 落点策略三件套）、
  纯函数 `core/mini/placement.dart`（吸边/钳制/安全区避让，零 Flutter 依赖）。
  `engine.dart` 播放链路一行不动。
* **拖拽/吸边/关闭**：`MovaCornerSnap` 默认吸角（惯性优先、垂直方向只钳制不吸边）；
  `dismissible` 甩出关闭；`MovaMiniSkin` 极简 chrome（中央播放/暂停 + 缓冲 + 关闭）。
* **误用防护**：`MovaMiniCtl.isShowing` + `MovaEngine.dispose()` 的 debug-only
  `assert(!state.mini)`，防止页面把刚交接出去的引擎顺手销毁。
* 详见 README「App 内小窗」一节、
  [doc/plans/2026-09-23-app-inline-pip-overlay.md](doc/plans/2026-09-23-app-inline-pip-overlay.md)。
  **真机验证未做**（Task 12）。

## 0.5.0

广告编排增强：把 `MovaAdCtrl` 从"能按排期播广告"推进到"能按广告业务的真实时序播广告"。
**除"广告位时长 `duration`"外全部默认关闭/默认不改变行为**，0.4.0 的每一条既有路径保留。

* **正片源延迟解析**：新增 `MovaAdCtrl.loadDeferred(MovaSourceResolver)` 与
  `contentError`。正片地址常常要等前贴片播完之后、按 DRM/权益/签名 URL 时效才定得下来；
  resolver 直到正片真要被打开时才调用，结果记忆化。`load(MovaSource)` 语义逐字不变。
* **广告位 `duration` / `delay` 与素材时间轴解耦**：`MovaAdBreak.duration` 是"买下的
  广告位时长"（素材更长更短都按它收回），`MovaAdBreak.delay` 是"N 秒后播放广告"的可见
  倒计时窗口（期间正片继续播）。两者到期一律用 `Timer` 判定、走与 `skip()` 完全相同的
  同步续播路径，**绝不**查询 `state.duration`、也绝不 seek 到素材尾部。
* **按广告位类型决定是否等待就绪**：新增 `MovaAdWaitPolicy` 与内置 `MovaAdWaitByKind`，
  默认 `pre` 否 / `mid` 是 / `post` 否——判据是"等待的价值等于等待期间屏幕上那张画面的
  价值"。三层覆盖（`MovaAdBreak.waitForReady` > 注入策略 > 按 kind 默认）收在
  `MovaAdConfig.waitsFor()` 一处。仅在宿主接了 `MovaSwapCtl` 且 `MovaSwapConfig.enabled`
  为 true 时才可能生效，因此不接切换引擎的宿主行为逐字节不变。
* **新增 `_Phase.pending` 阶段**与 `isAdPending` / `pendingBreak` / `delayRemaining`：
  广告已到期但尚未接管、正片刻意继续播放。中插走 `prepare` + `commit(waitForReady: true)`
  两段式，前/后贴片走 `swapTo` 一次式。等不到时按 `MovaAdNotReady` 裁决
  （`hardCut` 默认，等于今天的行为；`dropBreak` 则正片完全不被打断）。
* **广告加载失败兜底**：新增 `MovaAdFailPolicy`（内置 `MovaAdRetrySkip` 默认 0 次重试、
  `MovaAdAbandonPod`）与 `MovaAdFailKind`。四条失败路径——`open()` 抛出、播放器报错、
  始终无首帧（`loadTimeout`）、预热未就绪——统一汇流。
* **`MovaWarmPlan`**：给 `MovaSwapCtl.prepare` 加可选具名参数，把"本次预热用哪个触发
  策略、哪个就绪判据、就绪后是否停在起点"从全局配置解耦出来。同一个 `MovaSwapEngine`
  现在服务两个预热方向（广告背后暖正片、正片背后暖广告），两者取值不同。
* **顺带修掉三处既有缺陷**：注入的 `readyPolicy` 从不被 `reset()`；`at == 0` 仍下发
  无谓的 `seek(0)`；中插 pod 根本没有串联、会在两条广告之间闪回正片。
* **UI**：`MovaStrs.adStartingIn` 与倒计时角标。中插的默认形态（`delay == 0`、静默等待
  就绪）刻意不渲染任何东西——那段等待对用户就该是不存在的。
* **真机验证未做**（计划 Task 12）：等待是否真的消除黑屏、`adReadyTimeout`/`loadTimeout`
  的默认值是否合理、双活解码窗口在中低端机上的表现、坏 URL 在真机上以哪种形式报出来，
  均需真机逐项验证。详见
  [doc/plans/2026-09-16-ad-swap-enhancements.md](doc/plans/2026-09-16-ad-swap-enhancements.md)。

---

## 0.4.0

无缝引擎切换（可选，默认关闭）：新增 `MovaSwapEngine`（`MovaApi` 实现，持有生效引擎 +
预热中的影子引擎，原子换指，把"广告播完回正片"从黑屏/loading 变成逐帧无缝）。

* **`MovaSwapEngine`**：自持流的代理层，UI 只认这一份稳定的 `MovaApi`；换引擎时不重挂
  组件树、不丢订阅。`MovaOpts.swap`（`MovaSwapConfig`）默认 `enabled: false`，关闭时是
  纯直通代理。
* **预热触发 + 就绪判据两层可插拔**：`MovaWarmTrigger`（`MovaLeadWarm` 按剩余时长倒推、
  `MovaEagerWarm` 立即触发）与 `MovaWarmPolicy`（`MovaBufferWarm`，`MovaBufferAbr` 的
  镜像）。
* **`MovaAdCtrl` 接入**：新增可选 `swap` 构造参数（同一个 `MovaSwapEngine` 实例），广告
  播放期间在后台预热正片，结束时原子切回；不传时行为与 0.3.0 逐字节一致。
* **`MovaState.renderEpoch`**：普通引擎恒为 0；仅 `MovaSwapEngine` 提交切换后递增，用于
  触发渲染面重新读取 `renderHandle`。
* 清晰度切换（`switchQuality`）与 feed 引擎池均**未**接入本特性——前者只做了接口形状
  契约测试与落点注释，后者结构性不适用（双画面并存需求）。真机验证（黑屏是否真的消除、
  内存/解码 session 是否符合预期、短广告降级路径）尚未进行。
* **仅音频模式（`audioOnly`，默认关闭）**：`MpvKernel` / `MovaEngine` /
  `createMovaEngine()` 新增 `bool audioOnly = false` 构造参数。为 `true` 时完全跳过
  `VideoController` 的创建——media_kit 的 `Player` 默认就是 mpv 的 `--vid=no`，不挂接
  `VideoController` 就等于让 libmpv 只解音频，解码帧缓冲/GPU 纹理/Flutter `Texture`
  注册这三项是 0 而不是变小；`createMovaEngine()` 在此模式下也不再默认注入
  `MpvFrameExtractor`（它首次抽帧会新开第二个 `Player` 并为其建 `VideoController`）。
  **契约变更**：`MovaKernel.renderHandle` 由 `Object` 放宽为 `Object?`（`MovaApi` 与
  `MovaEngine` 侧本就可空，此为契约补齐）。UI 层零改动——`null` 句柄天然走占位分支，
  音频场景的封面/波形/歌词面用已有的 `MovaPlayer.surface` 传入。**不新增任何公开类，
  barrel 一行未改**；`audioOnly` 刻意不进 `MovaOpts`（构造期资源决策，`copyWith` 无法
  生效），也不加 `MovaStreamType.audio`（与流类型正交）。`MovaAudioSkin` 与后台常驻/
  锁屏/通知栏等系统集成面**不在本次范围**（分流判据见 README）。
  **Windows 桌面端已实测**（`ProcessInfo.currentRss`，同一条素材各两轮）：播放期内存
  增量视频 197 MiB vs 音频 96 MiB，**省约 101 MiB、约 2.05×**（不是文档原先推算的
  两个数量级——RSS 含 Flutter engine/libmpv 自身常驻开销），并直接确认 `audioOnly`
  下 `MovaState.size` 为 `0x0`、`renderHandle` 为 `null`；数据见
  `doc/notes/2026-09-16-audio-only-feasibility.md` §1.5。**Android/iOS 真机验证仍未进行。**

---
## 0.3.0

UI 插件化：把 0.2.0 已有的组件树/皮肤/补丁沉淀为 **Plugin / Component / Skin**
三层契约，并翻转手势侧别对齐主流。**破坏性变更**（0.2.0 尚未发布）。

* **`MovaPlugin` 能力 mixin**：为「事件副作用型」有状态组件提供两样与业务无关的能力——
  `api`（稳定句柄，`MovaScope.readOf` 非依赖读，`initState` 安全）与 `bind()`（订阅并在
  `dispose` 自动回收）。纯渲染组件仍走 `MovaSelect`，无需 mixin。
* **手势侧别→动作映射（破坏性）**：`MovaGestConfig` 的三个侧别布尔
  （`horizontalSeek`/`leftVerticalVolume`/`rightVerticalBrightness`）改为三个
  `MovaGestAction` 字段（`horizontal`/`leftVertical`/`rightVertical`），侧别与动作
  彻底解耦，可任意重映射或用 `MovaGestAction.none` 禁用某侧。**默认翻转为
  左亮度/右音量/横滑进度**（对齐 bilibili 等主流），逆转 0.1.0/0.2.0 的刻意反向设计。
* **组件树静态化**：`MovaSkin.components(MovaState)` → 无参 `components()`，树不再随状态
  变化；`MovaPlayer` 只构建一次而非每次状态变化重建整棵树，响应式收敛到组件自身的
  `MovaSelect`。VOD/直播底栏合并为一个自适应 `BottomBarComponent`（暴露两者子组件的
  并集，只挂载当前流类型相关的那些）；`live_bar.dart` 移除，其叶子并入 `bottom_bar.dart`。
* **皮肤三层骨架可覆写**：`MovaDefSkin.assemble` 拆为受保护的
  `buildPlaybackLayer`/`buildOperableLayer`/`buildPersistentLayer`，新增「继承并只重排
  一层」的半覆写定制档（补丁 / 半覆写 / 全实现三档）。
* **`MovaSlot` 新增 `left`/`right`**：左右垂直边带插槽，供侧栏/剧集列表等侧边内容；
  音量/亮度 HUD 维持居中，不落两侧。
* **音量/亮度手势 HUD 修复**：拖动时补上 `showHud`（此前只有 seek 会弹），HUD 徽标
  加图标 + 百分比（如 `🔊 40%` / `☀ 60%`，0 音量显示静音图标）。
* **系统音量端口 `MovaVolumePort`**：右滑音量可驱动**系统媒体音量**而非仅播放器音量。
  `createMovaEngine` 默认在 Android 接原生 `SystemVolumePort`（`AudioManager`，无新依赖），
  iOS/桌面回退播放器音量；任意平台可传 `CallbackVolumePort((percent) => ...)` 接管。
  构造时从端口播种 `state.volume` 作手势基线。
* **强制横竖屏 `MovaApi.setOrientation`**：新增 `MovaOrient { auto, portrait, landscape }`
  与 `MovaState.orientation`/`MovaOrientChg`；`setOrientation` 独立于全屏强制设备
  方向，`auto` 保持原「全屏按宽高比定向」行为。顶栏新增 `OrientationButtonComponent`
  （name `orientationButton`，全屏按钮左侧），仅移动端渲染、点击横↔竖切换，可用
  `MovaPatch.remove('topBar/orientationButton')` 移除。`MovaOrientPort.apply` 增
  `orientation` 参入（内部端口签名变更）。
* **渲染性能：三层各自 `RepaintBoundary` 隔离**：`MovaDefSkin.assemble` 的播放层/
  操作层/常驻层各包一层 `RepaintBoundary`。操作层重绘最频繁（进度条 tick、HUD 淡出、
  栏显隐动画），隔离后不会连带播放层（视频画面）与常驻层（锁定切换）一起重新
  光栅化，反之亦然；对宿主 App 也一样——外部重绘不会牵连进这棵子树。纯内部渲染优化，
  无公开 API 变化。

## 0.2.0

阶段 A 重构：`core/` + `ui/` 分层架构落地，功能与 0.1.0 保持一致
（无新增可见功能，纯架构收口）。

* **core/ 骨架**：`MovaApi`（能力面抽象）+ `MovaEngine`（实现，取代 `MovaCtrl`）
  + `MovaKernel`（内核抽象，唯一 import media_kit 的是 `mpv_kernel.dart`）
  + `MovaBus`（事件总线）+ sealed `MovaEvent` + `MovaState`/`MovaProg`/`MovaUiState`
  + `MovaHook`（`beforeOpen`/`beforeSeek`/`beforePlay`/`onError` 四个拦截点）。
* **ui/ 组件树 + 皮肤 + 补丁**：0.1.0 的 `VodControls`/`LiveControls`/
  `MovaGestDetect` 拆分为可组合的 `MovaComp` 叶子/组合组件
  （`TopBarComponent`/`BottomBarComponent`/`LiveBarComponent`/`GestureLayerComponent`/
  `HudLayerComponent`/`CenterPlayComponent`/`overlays` 等），由 `MovaSkin`
  （默认实现 `MovaDefSkin`）依据 `MovaState` 出树、通过 `MovaPatch`
  （`replace`/`remove`/`insertAfter`/`add`）做结构级定制，无需派生子类。
* **文案与主题外置**：`MovaStrs`（默认简体中文文案）与 `MovaTheme`
  （默认配色/尺寸，ARGB `int` 存储以保持 `core/` 零 Flutter 依赖）
  从 `MovaOpts` 注入，替换 0.1.0 硬编码的中文字符串与 `Colors.*`。
* **`MovaCtrl` 弃用**：标注 `@Deprecated('Use MovaEngine instead. 0.3.0 移除。')`，
  仍在 `lib/src/core/compat.dart` 提供做迁移期兼容门面。
* **开放性对账**：审计并清理了皮肤/组件层残留的硬编码颜色与重复的中文标签函数
  （详见 Task 19 报告）。

### 破坏性变更 / Breaking changes

| 0.1.0 | 0.2.0 |
|---|---|
| `MovaCtrl` | `MovaEngine`（`MovaCtrl` 仍可用但已弃用，0.3.0 移除） |
| `VodControls` | `MovaDefSkin`（VOD 时出的 `BottomBarComponent` 等组件） |
| `LiveControls` | `MovaDefSkin`（Live 时出的 `LiveBarComponent` 等组件） |
| `MovaGestDetect` | `MovaDefSkin` 内的 `GestureLayerComponent` |
| 派生子类定制控制条 | 传入 `MovaPatch` 列表给 `MovaDefSkin(patches: [...])`，或整体替换 `MovaSkin` |
| 硬编码中文文案/配色 | `MovaOpts.strings`（`MovaStrs`）/ `MovaOpts.theme`（`MovaTheme`）注入替换 |

### 修复 / Fixes

* **补上阶段 A 遗漏的平台适配器接线**：阶段 A 把亮度/画中画/方向拆成
  `MovaBrightPort`/`MovaPipPort`/`MovaOrientPort` 三个可注入端口，并在
  `lib/src/platform_impl/` 下实现了对应的真实适配器
  （`ScreenBrightnessPort`/`ChannelPipPort`/`SystemChromeOrientationPort`），
  但全仓库没有任何地方真正构造过它们——`MovaEngine()` 未显式注入时会静默落到
  `FallbackBrightnessPort`/`NoopPipPort`/`NoopOrientationPort`，导致右侧亮度
  手势、`enterPip()`、`setFullscreen()` 的方向/沉浸式系统 UI 在 0.2.0 里全部
  失效（0.1.0 中可用）。新增 `createMovaEngine()`（`lib/src/platform_impl/wiring.dart`，
  已从 `lib/mova.dart` 导出）默认接入三个真实适配器，同时保留
  `MovaEngine()` 自身的空/兜底默认值不变（供纯 Dart 单测使用）；`example/lib/main.dart`
  已改用 `createMovaEngine()`。

### 新增 — 拖动预览（阶段 B）

- 拖动进度条或横滑手势时，在进度条上方显示目标时刻的缩略图气泡（`PreviewComponent`，
  挂在 `MovaSlot.bottomAbove`，可用 `MovaPatch.replace('preview', …)` 整块替换）。气泡水平
  位置跟随拖动进度沿进度条移动，并钳制到两端不越界。
- 缩略图来源按序：服务端 WebVTT 雪碧图（约定 `<video-url>.vtt`，支持 `#xywh` 裁剪）→
  libmpv 隐藏 `Player` 抽帧兜底。可用 `MovaPrevConfig.sources` 整链替换。
- 两级缓存：内存计数 LRU（默认 40 项）+ 磁盘字节 LRU（默认 64MB，临时目录），
  `dispose()` 默认清盘。
- 网络策略默认 `wifiOnly`，由 `connectivity_plus` 探针判定；未知连接与桌面一律放行。
  被拦时静默不请求，只发 `MovaPrevBlock` 事件并回调 `onBlocked`。
- `MovaApi.preview`（`MovaPrevApi`）、`MovaOpts.preview`（`MovaPrevConfig`）、
  `MovaPrevBlock` 事件为新增公开 API。
- 扩展 `createMovaEngine()`：新增 `thumbDir`/`extractor`/`fetcher` 三个可选参数，
  缺省接入缩略图目录、抽帧器、网络探针的真实实现。

#### 依赖

- 新增 `path_provider`、`connectivity_plus`。

### 新增 — 直播时移（阶段 C）

- 新增 `MovaLiveSeekMode.dvr` / `.timeshift` 两种可拖直播模式；
- 新增 `MovaLiveConfig.urlBuilder` / `backToLive` / `autoBackToLiveOnStall` / `windowResolver`；
- 新增 `lib/src/core/live/timeshift.dart` 纯函数 `resolveWindow` / `behindOf` / `atLiveEdge`；
- `MovaState.timeshiftBehind` 现在真正被写入，并伴随 `MovaTimeShiftChg` / `MovaLiveEdgeReach` 事件；
- `MovaApi.backToLiveEdge()` 由占位（`reload()`）变为按策略执行；
- 新增 `MovaApi.pipSupported` / `MovaState.pipSupported`，PiP 按钮在不支持的平台自动隐藏；

**破坏性变更（0.2.0 内部，相对阶段 A/B 中间态）：**

| 旧 | 新 | 说明 |
|---|---|---|
| `BackToEdgeComponent`（name `backToEdge`） | `BackToLiveComponent`（name `backToLive`） | patch 路径 `bottomBar/backToEdge` → `bottomBar/backToLive`；行为由 `reload()` 改为 `backToLiveEdge()` |
| `MovaStrs.backToEdge` | `MovaStrs.backToLive` | 前者删除 |
| `LiveBarComponent()` | `LiveBarComponent({bool seekable = false})` | 新增可选参数，旧写法仍可编译 |

## 0.1.0

首个可用版本 / First usable release.

* 基于 media_kit（libmpv/ffmpeg）的播放内核封装：`MovaCtrl` / `MovaSource`。
* 手势层：左音量 / 右亮度 / 横滑进度 / 双击快进退 / 双指缩放，带 HUD。
* 点播 / 直播两套控制条；单击切换显隐、自动隐藏。
* 观看模式 contain / cover / fill；锁定/解锁防误触 + 沉浸式。
* 全屏按视频宽高比自动横/竖屏。
* 清晰度：HLS master 解析、手动切换（保位续播）、缓冲卡顿自动降档。
* Android 系统级画中画（iOS/桌面暂不支持）。

## 0.0.1

* 初始脚手架 / Initial scaffold.
