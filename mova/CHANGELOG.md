## 0.1.0

首次发布 / First release.

基于 media_kit（libmpv/ffmpeg）的 Flutter 视频播放器插件，自研手势与控制层，支持
点播 / 直播，可作为独立 UI 使用，也可按 Plugin / Component / Skin 三层契约深度定制。

### 核心播放能力

* 播放内核封装：`MovaApi`（能力面抽象）+ `MovaEngine`（生产实现）+ `MovaKernel`
  （内核抽象，唯一依赖 media_kit 的实现细节收在 `MovaMpvKernel`）。
* 构造引擎请使用 `createMovaEngine()`（`lib/src/platform_impl/wiring.dart`），
  它会接入亮度 / 画中画 / 方向等平台适配器的真实实现；裸构造 `MovaEngine()` 的平台端口
  默认是 noop，仅用于单测注入假端口。
* 清晰度：HLS master 解析、手动切换（保位续播）、缓冲卡顿自动降档（ABR）。
* 观看模式 `contain` / `cover` / `fill`；锁定/解锁防误触 + 沉浸式；全屏按视频宽高比
  自动横/竖屏，也可用 `MovaApi.setOrientation` 强制横竖屏（独立于全屏）。
* 仅音频模式（`audioOnly`）：`createMovaEngine(audioOnly: true)` 完全跳过视频解码
  管线（不建 `VideoController`、不注册 GPU 纹理），`renderHandle`/`size` 相应变为
  `null`/`0x0`，UI 层无需改动（封面/歌词等自定义画面用 `MovaPlayer.surface` 传入）。
  实测省内存约 2–2.7 倍（视场景而异）。

### 手势与 UI

* 手势层：横滑进度 / 双击快进退 / 双指缩放，带 HUD；左右侧竖滑默认分别对应
  亮度 / 音量（对齐 bilibili 等主流），可经 `MovaGestConfig` 的侧别→动作映射
  （`MovaGestAction`）任意重映射或用 `MovaGestAction.none` 禁用某侧。
* 组件树 / 皮肤 / 补丁三层契约：`MovaComp` 组件树由 `MovaSkin`（默认实现
  `MovaDefSkin`）依据 `MovaState` 出树，通过 `MovaPatch`（`replace`/`remove`/
  `insertAfter`/`add`）做结构级定制，无需派生子类；`MovaDefSkin.assemble` 也可按
  `buildPlaybackLayer`/`buildOperableLayer`/`buildPersistentLayer` 三层半覆写。
* `MovaPlugin` 能力 mixin：为有状态组件提供 `api`（稳定句柄）与 `bind()`
  （订阅并在 `dispose` 自动回收）。
* 文案与主题：`MovaStrs`（默认简体中文文案）与 `MovaTheme`（默认配色/尺寸）经
  `MovaOpts` 注入，可整体替换。
* 系统音量端口 `MovaVolumePort`：右滑音量可驱动系统媒体音量而非仅播放器音量，
  Android 默认接原生 `MovaSystemVolumePort`，其余平台可传
  `MovaCallbackVolumePort` 自行接管。
* 渲染性能：播放层 / 操作层 / 常驻层各自 `RepaintBoundary` 隔离，互不牵连重绘。

### 直播特性

* 点播 / 直播两套控制条自适应合并为 `MovaBottomBarComponent`。
* 直播时移：`MovaLiveSeekMode.dvr` / `.timeshift` 两种可拖模式，
  `MovaLiveConfig.urlBuilder`/`backToLive`/`autoBackToLiveOnStall`/`windowResolver`
  可配置；`MovaState.timeshiftBehind` 配合 `MovaTimeShiftChg`/`MovaLiveEdgeReach`
  事件，`MovaApi.backToLiveEdge()` 按策略执行。
* `MovaApi.pipSupported`/`MovaState.pipSupported`：PiP 按钮在不支持的平台自动隐藏。

### 画中画 / App 内小窗

* Android 系统级画中画（`MovaApi.enterPip()`）；iOS/桌面暂不支持
  （libmpv 纹理渲染方式下系统级 PiP 依赖 AVPlayer 路径，未实现，`pipSupported`
  返回 `false`）。
* App 内小窗 `MovaMini`：不依赖任何系统 PiP API，让画面从页面里"缩"成一个可拖拽
  的悬浮小窗，不重新解码、不黑屏。默认 **关闭**（`MovaMiniConfig.enabled` 为
  `false` 时全链路零行为变化）。两种挂载方式并存：`MovaMiniCtl.showInPage`
  （页内悬浮）与 `MovaMiniCtl.show` + `MovaMiniHost`（跨路由持久）。支持吸边/
  钳制/安全区避让、惯性拖拽甩出关闭。与系统 PiP 互斥（进入小窗会先退出系统 PiP，
  反之亦然）。

### 拖动预览缩略图

* 拖动进度条或横滑手势时，在进度条上方显示目标时刻的缩略图气泡
  （`MovaPreviewComponent`）。
* 缩略图来源按序：服务端 WebVTT 雪碧图（`<video-url>.vtt`，支持 `#xywh` 裁剪）→
  libmpv 隐藏 `Player` 抽帧兜底，来源链可经 `MovaPrevConfig.sources` 整体替换。
* 内存 + 磁盘两级缓存；网络策略默认 `wifiOnly`（`connectivity_plus` 探针判定，
  未知连接与桌面一律放行），被拦时静默不请求并发出 `MovaPrevBlock` 事件。
* `createMovaEngine()` 的 `extractor`/`probe` 默认值为 `null`（不默认引入
  `media_kit_video`/`connectivity_plus` 的静态可达依赖，便于 tree-shake）。要启用
  抽帧兜底与 `wifiOnly` 网络策略，需显式传入
  `extractor: MovaFrameExtractor()`/`probe: MovaConnectivityNetProbe()`；不传
  `probe` 时内核兜底为纯 Dart 的 `MovaAlwaysAllowNetProbe()`，`wifiOnly` 策略不会
  被强制执行（其余网络策略不受影响）。

### 广告编排

* `MovaAdCtrl` 支持按真实业务时序播广告：正片源可延迟解析
  （`loadDeferred(MovaSourceResolver)`），广告位 `duration`/`delay` 与素材时间轴
  解耦（统一 `Timer` 驱动，不查询/依赖 `state.duration`，不做尾部 seek）。
* 按广告位类型决定是否等待就绪（`MovaAdWaitPolicy`，内置 `MovaAdWaitByKind`
  默认 `pre` 否 / `mid` 是 / `post` 否），三层覆盖收在 `MovaAdConfig.waitsFor()`。
* 广告加载失败兜底：`MovaAdFailPolicy`（内置 `MovaAdRetrySkip`/`MovaAdAbandonPod`）
  统一处理打开失败、播放器报错、无首帧超时、预热未就绪四类场景。
* 等待/无缝切换需要宿主同时接入下节的 `MovaSwapEngine` 并开启
  `MovaSwapConfig.enabled`，否则退化为传统"到点直接切"的行为。

### 无缝引擎切换（可选）

* `MovaSwapEngine`：本身实现 `MovaApi` 的代理层，持有生效引擎与预热中的影子引擎，
  就绪后原子换指，把"广告播完回正片"从黑屏/loading 变成逐帧无缝。默认
  `MovaSwapConfig.enabled: false`，关闭时是纯直通代理，行为与不接入时一致。
  `MovaState.renderEpoch` 在切换后递增，用于触发渲染面重新读取 `renderHandle`。
* 预热触发策略（`MovaWarmTrigger`：`MovaLeadWarm`/`MovaEagerWarm`）与就绪判据
  （`MovaWarmPolicy`：`MovaBufferWarm`）两层可插拔；`MovaWarmPlan` 可按预热方向
  分别配置。
* **已知限制**：清晰度切换（`switchQuality`）与 feed 场景的引擎池未接入无缝切换——
  前者已走安全的寄存续播路径但未经过无缝切换本身的验证，后者结构性不适用
  （双画面并存需求）。

### 依赖

* `media_kit` / `media_kit_video` / `media_kit_libs_video`：播放内核。
* `path_provider`：拖动预览磁盘缓存目录。
* `connectivity_plus`：拖动预览的 `wifiOnly` 网络策略探针。
* `screen_brightness`：亮度手势的系统亮度端口。

### 已知限制

* iOS 系统级画中画未实现（见上文）。
* `switchQuality` 尚未接入无缝引擎切换（见上文"无缝引擎切换"小节）。
* `MovaAudioSkin`（封面/歌词/波形专用皮肤）未提供，仅音频场景请用
  `MovaPlayer.surface` 自行传入占位画面。

## 0.0.1

* 初始脚手架 / Initial scaffold.
