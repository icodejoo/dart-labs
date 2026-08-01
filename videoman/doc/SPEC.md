# videoman 技术规格（SPEC）

配套阅读：[PRD.md](PRD.md)（需求/决策）、[ROADMAP.md](ROADMAP.md)（里程碑）、
[DESIGN-0.2.0.md](DESIGN-0.2.0.md)（0.2.0 重构的原始设计，含尚未实现的阶段
B/C 细节）。本文档描述**当前代码实际落地**的架构；与 DESIGN 文档冲突之处
以本文档为准（阶段 A 落地过程中做过的微调见文末）。

## 架构分层

```
lib/
├─ videoman.dart                      # 对外唯一入口 barrel
├─ videoman_platform_interface.dart   # 平台通道接口（getPlatformVersion / isPipSupported / enterPip / get·setSystemVolume）
├─ videoman_method_channel.dart       # MethodChannel 实现
└─ src/
   ├─ core/                           # 内核层：无 Flutter/media_kit UI 依赖
   │  ├─ api.dart                     # VmApi：UI 层唯一依赖的抽象能力面
   │  ├─ engine.dart                  # VmEngine implements VmApi，生产实现
   │  ├─ compat.dart                  # VmController（@Deprecated，包一层 VmEngine，0.3.0 移除）
   │  ├─ kernel/kernel.dart           # VmKernel 抽象（可 fake）
   │  ├─ kernel/mpv_kernel.dart       # 唯一 import media_kit 的文件
   │  ├─ bus/bus.dart                 # VmBus：broadcast + throttle/distinct
   │  ├─ events/events.dart           # sealed VmEvent 事件表
   │  ├─ state/state.dart             # VmState + copyWith（含 sourceTitle 字段，非独立 getter）
   │  ├─ state/progress.dart          # VmProgress（高频位置/缓冲）
   │  ├─ state/ui_state.dart          # VmUiState（控制条可见/HUD/预览位置）
   │  ├─ interceptor/interceptor.dart # VmInterceptor + VmInterceptorChain
   │  ├─ options/options.dart         # VmOptions 聚合（live/gesture/abr/controls/strings/theme）
   │  ├─ options/abr_config.dart      # VmAbrConfig（含 VmAbrPolicy 抽象；未落在 model/abr.dart）
   │  ├─ options/gesture_config.dart  # VmGestureConfig（自 0.1.0 迁入，字段不变）
   │  ├─ options/controls_config.dart # VmControlsConfig
   │  ├─ options/live_config.dart     # VmLiveConfig（含 urlBuilder/backToLive/windowResolver）
   │  ├─ live/timeshift.dart          # resolveWindow/behindOf/atLiveEdge 纯函数
   │  ├─ options/strings.dart         # VmStrings（文案外置，默认简体中文）
   │  ├─ options/theme.dart           # VmTheme（配色/尺寸外置，ARGB int 存储）
   │  ├─ model/source.dart            # VmSource / VmStreamType
   │  ├─ model/quality.dart           # VmQuality + parseHlsMasterPlaylist（纯函数）
   │  ├─ model/fit.dart               # VmFit(contain/cover/fill)
   │  └─ platform/ports.dart          # VmBrightnessPort / VmVolumePort / VmPipPort / VmOrientationPort
   ├─ platform_impl/                  # ports 的具体实现（screen_brightness / MethodChannel / SystemChrome）
   └─ ui/                             # UI 层：组件树 + 皮肤 + 手势，纯 Flutter widget
      ├─ player.dart                  # VmPlayer 门面：接 VmApi，渲染画面，用 VmSkin 出树
      ├─ fit_ext.dart                 # vmBoxFit()
      ├─ format.dart                  # formatDuration()
      ├─ scope/scope.dart             # VmScope：InheritedWidget 发布 VmApi
      ├─ scope/selector.dart          # VmSelector<T> / VmUiSelector<T>：按选择器重建
      ├─ slots/slot.dart              # VmSlot 枚举 + VmSlotBundle
      ├─ slots/component.dart         # VmComponent 抽象（name/slot/children/build）
      ├─ slots/tree.dart              # buildSlots()：组件树 → VmSlotBundle
      ├─ slots/patch.dart             # VmPatch（replace/remove/insertAfter/add，路径寻址）+ applyPatches()
      ├─ scope/plugin.dart            # VmPlugin：副作用型组件的能力 mixin（api + bind）
      ├─ skins/skin.dart              # VmSkin 抽象（无参 components()/assemble()）
      ├─ skins/default_skin.dart      # VmDefaultSkin：静态树 + 三层可覆写骨架
      └─ components/                  # 叶子/组合组件：top_bar/bottom_bar（自适应 VOD/直播）/
                                       # center_play/gesture_layer/hud_layer/overlays/common
android/src/main/kotlin/.../VideomanPlugin.kt  # 原生 PiP：ActivityAware + enterPictureInPictureMode
```

Slint 无关；纯 Flutter/Dart + 少量 Kotlin。`core/` 目录不 import
`package:flutter/*`（`purity_test.dart` 断言此约束）；`ui/` 是唯一可以
import Flutter widget 与直接依赖 `VmApi` 的地方。

## 关键 API 与不变式

- `VmApi` 是 `ui/` 唯一依赖的抽象；`VmEngine implements VmApi` 是生产实现，
  测试用 `FakeVmApi`（`test/support/fake_api.dart`）。
- `VmApi.renderHandle`：底层渲染句柄（生产环境是 media_kit 的
  `VideoController`），`VmPlayer` 仅当其 `is VideoController` 时渲染真实
  `Video`，否则渲染占位符——这是 widget 测试无需真实播放内核的关键。
- `VmState.sourceTitle` 是 `VmState` 上的可空字段（不是 `VmApi` 的独立
  getter）；`copyWith` 用 `clearSourceTitle` 标志区分"不改"与"清空"。
- 直播下 `seek()` 受 `state.liveSeekable` 门控（`VmLiveConfig.seekMode !=
  off` 且可拖窗口 > 0）：`dvr` 走内核原生 seek（clamp 到 `seekableWindow`）；
  `timeshift` 走 `VmLiveConfig.urlBuilder` 重开源（没有 `urlBuilder` 则整个
  seek 是空操作）。`backToLiveEdge()` 按 `VmLiveConfig.effectiveBackToLive`
  执行——`seekEnd` 直接 seek 到窗口末端，`reopen` 重开**原始**直播地址
  （绕过 `open()`，因为回边缘是位置变化不是换源，也不该清空清晰度列表）。
- `VmPlayer` 组合渲染画面 + `VmSkin.components()` 出的**静态**组件树
  （经 `buildSlots()` 分槽，只构建一次）+ `VmSkin.assemble()` 拼装 `Stack`；默认皮肤
  `VmDefaultSkin` 复刻 0.1.0 的分栏布局与"隐藏时可穿透点击"规则。

## 组件树 / 皮肤 / 补丁

- `VmComponent`：`name`（树内寻址用）+ `slot`（归属的 `VmSlot`）+
  `children` + `build(context, api, children)`。叶子组件 `children` 为空；
  组合组件（如 `TopBarComponent`）持有多个子组件。
- `VmSkin.components()`（0.3.0 起无参）返回**静态**顶层组件列表——树不随状态
  变化，显隐由组件各自的 `VmSelector` 响应式决定。VOD/直播底栏合并为一个自适应
  `BottomBarComponent`：暴露两套布局子组件的并集（顶层 `name` 恒为 `bottomBar`，
  patch 路径不随流类型错位），只挂载与当前 `state.type` 相关的那些。
- `VmPlugin`（`ui/scope/plugin.dart`）：给「事件副作用型」有状态组件的能力 mixin，
  提供 `api`（`VmScope.readOf` 非依赖读，`initState` 安全）与 `bind()`（订阅并在
  `dispose` 自动回收）。纯渲染组件走 `VmSelector`，不需要它。
- `VmSlot`：`gesture`/`hud`/`top`/`center`/`bottomAbove`/`bottom`/`overlay` +
  `left`/`right`（0.3.0 新增的左右垂直边带，供侧栏等；HUD 维持居中不落两侧）。
- `VmDefaultSkin.assemble` 是三层骨架（播放/操作/常驻），0.3.0 起拆为受保护的
  `buildPlaybackLayer`/`buildOperableLayer`/`buildPersistentLayer`，子类可只覆写一层。
  三层各自包一层 `RepaintBoundary`：操作层重绘最频繁（进度条 tick/HUD 淡出/栏显隐
  动画），隔离后不牵连播放层（视频画面）与常驻层一起重新光栅化，反之亦然；对宿主
  App 也一样，外部重绘不会牵连进这棵子树。`test/ui/skin_test.dart` 用
  `find.descendant(of: find.byType(VmScope), ...)` 断言恰好 3 个（不能用全局
  `find.byType(RepaintBoundary)`——`MaterialApp`/测试绑定在外层还有框架级的）。
- `VmPatch` 是数据不是动作，只有 `applyPatches()` 解释它们（纯函数、可测）：
  - `VmPatch.replace(path, component)`：整替换一个节点。
  - `VmPatch.remove(path)`：移除一个节点（顶层或嵌套）。
  - `VmPatch.insertAfter(path, component)`：在锚点之后插入同级兄弟。
  - `VmPatch.add(slot, component, {order = 0})`：向树追加一个新顶层组件，
    按 `order` 在该 `slot` 内排序（阶段 A 落地时修过这里的排序/挂载逻辑，
    以 `applyPatches` 的实现与 `tree_test.dart` 为准）。
- 定制无需继承旧版 `VodControls`/`LiveControls`/`VmGestureDetector`：给
  `VmDefaultSkin(patches: [...])` 传补丁，或整体实现 `VmSkin`。

## 文案 / 主题外置

- `VmStrings`：`fitContain`/`fitCover`/`fitFill`/`live`/`backToLive`/
  `timeshift`/`auto`/`quality` 八个字段，默认简体中文（`backToEdge` 已在阶段 C
  被 `backToLive` 取代并删除）；
  `fitLabel(VmFit)` 是唯一允许解析 `VmFit → 文案` 的地方（0.2.0 落地审计中
  删除了 `ui/fit_ext.dart` 里重复且硬编码的 `vmFitLabel()`）。
- `VmTheme`：`iconColor`/`textColor`/`accentColor`/`barGradientColor`/
  `sheetBackgroundColor`（弹层背景，审计中从硬编码 `Color(0xEE1A1A1A)`
  提炼出的新字段）+ 字号/尺寸字段，均以 ARGB `int` 存储以保持 `core/`
  零 Flutter 依赖；`ui/` 层用处转 `Color(...)`。
- 二者都经 `VmOptions.strings`/`VmOptions.theme` 注入，组件通过
  `api.options.strings`/`api.options.theme` 读取，不再有散落的中文字面量
  或 `Colors.*`/`Color(0x...)` 硬编码（`components/`、`skins/` 下）。

## 拦截点

`VmInterceptor`：`beforeOpen`/`beforeSeek`/`beforePlay`/`onError` 四个钩子，
`VmInterceptorChain` 按注册顺序依次咨询、遇否决/取消即短路；`onError` 对
每个拦截器独立 try/catch，一个抛异常不影响其余拦截器收到通知。经
`VmEngine(interceptors: [...])` 注入。

## 手势数学（gesture_layer.dart）

- 横滑进度：`seconds = dx / width * hSeekSpanPerScreen.inSeconds`（默认
  90s 满屏宽，来自 `VmGestureConfig.hSeekSpanPerScreen`，可配）；直播下受
  `state.liveSeekable && VmGestureConfig.allowWhenLive`（默认开）门控，
  非 `off` 模式的可拖直播允许横滑 seek，其余禁用。
- 竖滑：侧别→动作经 `VmGestureConfig` 的 `leftVertical`/`rightVertical`
  （`VmGestureAction`）配置，0.3.0 起默认**左亮度、右音量**（对齐主流，翻转自
  0.1.0/0.2.0 的左音量/右亮度）；音量 0–100、亮度 0–1，系数 `vSensitivity`。
  横滑动作由 `horizontal`（默认 `seek`）决定；`VmGestureAction.none` 可禁用某方向。
  volume/brightness 拖动均会 `showHud(...)`，HUD 徽标带图标 + 百分比（如 `🔊40%`）。
- 音量落点：`setVolume` 经 `VmVolumePort` 路由——接了端口走它（系统音量/宿主回调），
  否则经内核走播放器音量。`createVmEngine` 默认仅 Android 接 `SystemVolumePort`
  （原生 `AudioManager` 调系统媒体音量，无新依赖），iOS/桌面回退播放器音量；任意
  平台可传 `CallbackVolumePort` 接管。构造时从端口 `get()` 播种 `state.volume` 作手势基线。
- 亮度：经 `VmBrightnessPort`（生产实现用 `screen_brightness`）调系统屏幕亮度，
  平台不支持时兜底 1.0。
- 双指缩放：`onScaleUpdate` 进入 zoom，`clamp(1, maxZoom)`。
- 双击：按 `VmGestureConfig.doubleTapStep`（默认 10s）快进退。

## 清晰度 / ABR

- `parseHlsMasterPlaylist(content, base)`：解析 HLS master，提取
  BANDWIDTH/RESOLUTION 变体；非 master 返回 `[]`。
- `switchQuality(q)`：保留播放态，点播下保位续播。
- ABR 策略是 `VmAbrConfig.policy`（类型 `VmAbrPolicy`，位于
  `core/options/abr_config.dart`，不是 DESIGN 文档原设想的
  `core/model/abr.dart`）；省略时默认 `VmBufferingAbr(threshold: stallThreshold)`。
  自动档不降档（交给 libmpv 原生 ABR）。

## 直播时移（阶段 C）

- 三种模式（`VmLiveConfig.seekMode`）：`off`（默认，禁拖）、`dvr`（服务端滑动
  窗口内拖，复用内核原生 seek）、`timeshift`（拖动即用 `urlBuilder` 重开源）。
- 窗口解析优先级（`resolveWindow`，`lib/src/core/live/timeshift.dart`）：
  `VmLiveConfig.windowResolver` > `dvrWindow` > 内核报告的 `duration`。结果
  clamp 到非负。
- `behindOf(position, window, edgeThreshold)`：落后边缘的时长在 `edgeThreshold`
  （默认 10s）以内、或窗口未知/为零、或 `position` 已到/超过窗口末端时一律返回
  `null`（视为"在边缘"），否则返回落后量。`atLiveEdge` 是其取反的语义封装。
- `VmState.timeshiftBehind` 在写入前先按**整秒量化**——position 每秒回调多次，
  不量化会让去重后的 `states` 流退化成高频流（阶段 A 特意把 position 排除在
  `VmState` 之外的初衷）。落后量归零/变化时分别发 `VmLiveEdgeReached`/
  `VmTimeshiftChanged`。
- `backToLiveEdge()` 的行为由 `VmLiveConfig.effectiveBackToLive` 决定：显式配置
  `backToLive` 就用它，否则按 `seekMode` 推导（`timeshift` → `reopen`，其余 →
  `seekEnd`）。`reopen` 重开的是 `_source` 里保存的**原始**直播地址，而不是内核
  当前打开的时移地址。
- `autoBackToLiveOnStall`（默认关）：仅在**确实处于时移状态**且发生卡顿时才
  自动跳回边缘，避免悄悄丢弃用户主动选定的回看位置。
- UI 树 `bottomBar/{liveBadge, seekBar, timeshift, backToLive}`：`SeekBarComponent`
  对可拖直播取 `seekableWindow` 而非 `duration`（同一组件同时服务 VOD 与直播）；
  `liveBadge` 按 `timeshiftBehind == null` 在红色 `LIVE`/灰色 `时移`（`VmTheme.
  timeshiftBadgeColor`）间切换；`backToLive`（原 `backToEdge`，已删除并改名）
  调 `backToLiveEdge()` 而非 `reload()`。

## PiP（原生）

- Dart 侧经 `VmPipPort`；Android `VideomanPlugin.kt` 用
  `PictureInPictureParams`，宽高比 `clamp(0.42, 2.39)`；iOS/桌面未实现，
  `isPipSupported()` 返回 `false`。
- **iOS 系统 PiP：待定任务（未完成）**。可行性已调研，方向为
  `AVSampleBufferDisplayLayer` + `CVPixelBuffer`（Android 是 Activity 级 PiP，无需取帧；
  iOS 必须自渲染取帧）；落地卡在一次需 Mac + iOS 15+ 真机的门槛 spike。**契约维持不变**：
  落地前 `isPipSupported()` 仍返回 `false`、`PipButtonComponent` 自动隐藏；落地后仅原生
  返回值变化，Dart/UI 零改动。完整研究 + 落地计划见
  [doc/notes/2026-07-31-ios-pip-feasibility.md](notes/2026-07-31-ios-pip-feasibility.md)。
- `VmState.pipSupported` / `VmApi.pipSupported`（阶段 C）：engine 构造后不久
  用 `VmPipPort.isSupported()` 探测一次（默认 `false`，探测失败也归约为
  `false` 而不抛出）；`PipButtonComponent` 据此隐藏自身，不支持的平台上按钮
  根本不出现，而不是出现了点了没反应。

## 全屏（桌面平台的已知边界）

`SystemChromeOrientationPort`（`VmOrientationPort` 的默认实现）只处理移动端的
方向锁定与沉浸式系统 UI；Windows/macOS/Linux 上没有"真全屏"的对应概念（撑满
屏幕、去掉标题栏），因此 `setFullscreen(true)` 在桌面端不会有可见效果——2026-07-31
Windows 实跑证实。这不是回归，是能力从未在桌面实现过。videoman 不内置窗口管理
依赖（如 `window_manager`），桌面真全屏留给宿主接：`setFullscreen()` 每次调用都会
在 `VmApi.events` 上发 `VmFullscreenChanged(bool)` 事件，与 `VmOrientationPort`
无关，宿主监听后自行调用窗口管理 API 即可（见 README「平台端口」一节示例）。

### 强制横竖屏（0.3.0）

`VmApi.setOrientation(VmOrientation)` 是独立于全屏的方向能力：`VmOrientation.auto`
保持上文「全屏按宽高比定向」的行为，`portrait`/`landscape` 无视宽高比与全屏状态
强制该方向，写入 `VmState.orientation` 并发 `VmOrientationChanged`。落点在
`VmOrientationPort.apply` 新增的 `orientation` 参：`resolveOrientations()`
（`orientation_impl.dart`，已抽出纯函数单测）在 `auto` 时回退到
`preferredOrientationsFor(w,h)`，否则直接取横/竖屏对。engine 侧由 `_applyOrientation()`
统一根据 `state.fullscreen + state.orientation` 应用，`setFullscreen`/`setOrientation`
/尺寸到达三处共用它。UI 侧 `OrientationButtonComponent`（顶栏，name
`orientationButton`）仅在 `defaultTargetPlatform` 为 Android/iOS 时渲染——桌面端强制
方向本就无效，与 pip 按钮的隐藏思路一致——点击经 `VmOrientation.toggled` 横↔竖切换。

## 预设皮肤：bilibili 点播 / 抖音风 feed

两套开箱即用的皮肤，落地于 0.3.0 插件化架构之上（未单独编版本号，落地日期
2026-08-01）。

- **`VmBilibiliSkin`**（`ui/skins/bilibili_skin.dart`）：`extends VmDefaultSkin`，
  纯"补丁档"定制（`VmPatch.add`/`insertAfter`），零布局改写——bilibili 的默认
  控制条与手势侧别（左亮度/右音量）本就对齐 0.3.0 默认值。新增
  `DanmakuTrackComponent`（`ui/components/danmaku.dart`，挂 `VmSlot.overlay`，
  不受锁定/自动隐藏门控）+ 顶栏 `SpeedButtonComponent`（`ui/components/
  speed_button.dart`，`0.5x~2x` 六档循环，走既有 `VmApi.setRate`，未新增 core
  能力）。**倍速按钮落在顶栏而非底栏**：`TopBarComponent.build()` 用
  `...children.sublist(1)` 展开全部子节点，而自适应的 `BottomBarComponent`
  按下标显式取子节点（`children[0]`/`children[2]`/`children[4]`），补丁插入的
  新兄弟节点会被静默丢弃——这是从 `BottomBarComponent` 现有实现读出的真实约束，
  非设计偏好。
- **弹幕（`VmDanmakuConfig`/`VmDanmakuItem`）**：**只做展示**，无发送框/输入/
  去重限流引擎（`VmOptions.danmaku`，默认 `enabled: false`）；`items` 是宿主给
  的固定列表，按 `time` 触发滚动、按 `trackCount` 轮询分轨（非完整防重叠）。
  "弹幕开关"按钮本期**未做**——`enabled` 是构造期配置，非运行时可切换状态，
  加运行时开关需要一个新的本地 UI 状态承载点，本期从简未做，留待后续。
- **`VmFeedPlayer`/`VmDouyinSkin`**（`ui/feed_player.dart`/`ui/skins/
  douyin_skin.dart`）：纵向"上滑下一个视频"feed，**单引擎架构**——
  `VmFeedController`（`core/feed/feed_controller.dart`，纯 Dart，无 Flutter
  依赖）反复对同一个 `VmApi` 调 `open()` 切换，而非并行维护多个 `VmEngine`。
  该决策经过实测评估权衡：并行引擎池切换更顺滑（下一条已解码待播），但
  代价是每活跃实例约 50-100MB 内存，且**硬解并发 session 数**（很多中低端
  Android SoC 只支持 1-2 个）是比 CPU/内存更硬的瓶颈——超限会静默掉软解，
  发热掉帧。结论是不做"高低端机型自动分档"（判断依据本就不可靠、需要机型库
  或跑基准测试，videoman 一贯克制新依赖），改为单引擎 + `prefetchDepth` 交给
  宿主按自己目标机型配置，默认保守值 1。
  - **预取范围已从设计草案收窄**：原计划里"深度 1 用 mpv 原生
    `prefetch-playlist`、深度 ≥2 走自建磁盘缓存"需要新增 mpv playlist 管理
    + 经 `NativePlayer.handle` 裸 FFI 设置 mpv property，属于对现有单源
    `VmEngine`/`VmKernel` 抽象的较大扩张，风险与本次工作量不匹配，**推迟**。
    第一版 `NetworkWarmFeedPrefetcher`（`core/feed/feed_prefetcher.dart`）只做
    HTTP Range 预取前 64KB 并丢弃——只预热 DNS/TCP/TLS/CDN 边缘节点，不解码、
    不落盘，`VmApi.open()` 切换时解码器自身启动开销仍在。真正的 mpv 原生
    playlist 预取集成留作后续任务。
  - **只有 `activeIndex` 页渲染真实视频画面**：`PageView` 为滚动物理效果额外
    构建的相邻页只在纯黑底上渲染自己的 chrome（社交竖排/作者信息）——因为只有
    一个共享解码器，若相邻页也渲染真实画面，会显示"当前正在播放的那条"而非
    它自己的内容。代价是刚定格的新页面在 `open()` 完成前会短暂黑屏，这是
    上面单引擎决策的自然延伸，非独立缺陷。
  - **点赞状态 videoman 端到端本地持有**（`VmFeedItem.initialLiked`/
    `initialLikeCount`/`onLikeChanged`）：双击（`DouyinGestureLayerComponent`）
    与竖排点赞按钮（`LikeButtonComponent`）经同一个 `ValueNotifier`（由
    `VmFeedPlayer` 的 State 按 index 缓存、跨该页历次重建存活）保持同步；
    `VmFeedController.toggleLike` 把切换结果写回条目缓存，滑走再滑回时仍是
    切换后的值；不做回滚，是否持久化交给 `onLikeChanged` 回调。评论/分享/
    头像/关注一律只是回调，videoman 不持有这些业务状态。
  - **手势冲突靠"不引入组件"规避**：`VmDouyinSkin.components()` 压根不挂载
    `GestureLayerComponent`（默认皮肤的亮度/音量竖滑手势），纵向拖拽完全归
    `PageView` 所有；这是组件化架构的直接收益，不需要任何特判代码。
  - **数据源**：`VmFeedLoader = Future<VmFeedItem?> Function(int index)`，
    异步按需解析，返回 `null` 表示 feed 结束；`VmFeedController` 内部按索引
    缓存去重并发加载。

新增测试：`test/core/model_test.dart`（`VmDanmakuItem`/`VmFeedItem`）、
`test/core/options_test.dart`（`VmDanmakuConfig`/`VmOptions.danmaku`）、
`test/core/feed_controller_test.dart`、`test/core/feed_prefetcher_test.dart`
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
  `overlays_test.dart`/`player_test.dart`/`plugin_test.dart`（0.3.0 `VmPlugin`）/
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
   （`VmPreviewConfig`）、`lib/src/platform_impl/`（`mpv_extractor_impl`/
   `net_probe_impl`/`thumb_dir_impl`）、`lib/src/ui/components/preview.dart`
   （`PreviewComponent`，挂 `VmSlot.bottomAbove`，气泡水平位置随拖动比例跟随，
   钳制不越界）。新增公开面：`VmApi.preview`（`VmPreviewApi`）、
   `VmOptions.preview`（`VmPreviewConfig`）、`VmPreviewBlocked` 事件；
   `createVmEngine()` 新增 `thumbDir`/`extractor`/`fetcher` 三个可选参数。
   **抽帧路线**（见 `doc/plans/2026-07-31-phase-b-preview.md` 附录 A）：
   `screenshot-raw` 实测在 Windows 上不论 `vf=scale` 还是
   `VideoControllerConfiguration(width/height)` 都不能缩小输出，最终采用
   "原尺寸 + 不缩放兜底"，`frameWidth` 仅作为 cache key 与 UI 显示宽度参与量。
   212 项测试全绿，`flutter analyze` 0 issues。已知遗留：横滑手势路径与
   "关闭预览开关"两点未逐条人工验证（理论行为一致，见附录 B）；磁盘缓存按原
   分辨率 JPEG 估算，`diskMaxBytes` 默认 64MB 的余量比按缩略图估算的更紧张。
2. **阶段 C：直播时移——已完成**（2026-07-31）。见本文档「直播时移（阶段 C）」
   一节的实现现状；`ios/videoman.podspec` 元数据已与 `pubspec.yaml` 对齐
   （**版本号必须手动同步**——`s.version` 不会自动跟 `pubspec.yaml` 的
   `version` 走，每次改版本都要同时改 podspec）；example 已加直播 DVR/时移
   两个 demo。
3. **阶段 D：收尾发布——进行中**。README/CHANGELOG/SPEC 已更新；
   `flutter pub publish --dry-run` 待最终校验；**真机一轮验证仍未做**
   （手势手感、HLS 联网切档、Android PiP 实际行为、iOS 整体播放、直播时移
   UI，均承自 0.1.0 尚未在真机验证，且本次 core/ui 重构与预览/时移两个新功能
   也从未上过真机——见文末「真机验证结果」一节）。**新增验证项**：iOS
   低端/老旧机型上 Flutter `Texture` 更新已知会阻塞 raster 线程的 bug
   （老设备上曾报告直接冻屏，`flutter/flutter#86613`）——videoman 目前
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
  延续既有端口抽象三件套（暂拟 `VmSttEngine`，core 出抽象、`platform_impl/` 出各平台
  原生实现、无原生能力则 noop）。第一版曾建议默认依赖 whisper.cpp（FFI），已推翻。
  曾评估"MCP 兜底转写"，**已否决**（MCP 是请求/响应协议非实时流式，延迟不可控；且与
  MCP 钩子本该扮演的"被动暴露上下文"角色冲突）——缺口不专门补，复用既有
  `VmVolumePort`/`CallbackVolumePort` 的注入模式给宿主一个通用 `VmSttEngine` 口子即可。
- **MCP 钩子（与上方字幕功能解耦，不承担转写职责）**：预计不会成为核心依赖，更可能是
  一个可选的 `VmInterceptor` 实现或独立的事件流消费者，订阅播放状态/字幕文本等只读
  上下文，并可选择性地接收外部指令——是**被动**暴露/接受控制的角色，不用作"主动请求
  转写服务"（那条路已在字幕评估中否决）；核心库不直接依赖 MCP SDK，接入方式留给上层
  应用或独立扩展包。

以下两点是阶段 A 落地过程中相对 DESIGN 文档的已知偏差，供阶段 B/C 生成详细
计划时对照实际签名，不要盲目照抄 DESIGN 原文：

- `VmAbrPolicy` 落在 `lib/src/core/options/abr_config.dart`，不是 DESIGN
  设想的 `lib/src/core/model/abr.dart`。
- `VmApi.renderHandle` 是阶段 A 落地过程中新加的 getter（DESIGN 原文未提），
  用于让 `VmPlayer` 在测试环境下渲染占位符而非真实 media_kit `Video`。
- `VmState.sourceTitle` 是 `VmState` 的字段，不是 `VmApi` 上独立的 getter。
- `VmPatch.add` 的 slot/order 处理在落地时做过修正，具体行为以
  `lib/src/ui/slots/tree.dart` 的 `applyPatches()` 实现与
  `test/ui/tree_test.dart` 为准。

关于 ffmpeg 瘦身（LGPL）与 iOS PiP：videoman 就是 `fvideo` 改名/重构而来的
同一个工程，**fvideo 的遗留任务就是 videoman 的任务**，全部承接：

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
