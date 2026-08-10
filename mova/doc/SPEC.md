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
   │  ├─ model/quality.dart           # MovaQual/MovaVideoTrack + qualitiesFromVideoTracks（纯函数）
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

## PiP（原生 + 应用内悬浮窗降级）

- Dart 侧经 `MovaPipPort`；Android `MovaPlugin.kt` 用
  `PictureInPictureParams`，宽高比 `clamp(0.42, 2.39)`；桌面未实现，
  `isPipSupported()` 返回 `false`。
- **iOS 系统 PiP：阶段1骨架已落地（未真机验证）**。`ios/mova/Sources/mova/MovaPipController.swift`
  起了 `AVSampleBufferDisplayLayer` + `AVPictureInPictureController(contentSource:)`，
  `AVPictureInPictureSampleBufferPlaybackDelegate` 的 play/pause/skip 回调是
  `// TODO(spike)` 空桩，`AVAudioSession` 已设 `.playback`，`enterPip` 灌入的是
  定时器产出的纯色测试卡假帧（阶段2真实 libmpv 取帧仍未做）；
  `example/ios/Runner/Info.plist` 已加 `UIBackgroundModes: audio`。**Dart 侧契约
  刻意维持不变**：`MethodChannelMova.isPipSupported()` 在 iOS 上无条件短路回报
  `false`（见该文件内注释），不转发原生探测结果——落地前
  `PipButtonComponent` 仍按"不支持"路径工作（现在的"不支持"路径是下面的悬浮窗
  降级，而非隐藏，见下）。原生代码从未在真机上编译或运行过；真机验证（阶段0
  取帧路径定档、阶段2真实帧、阶段5全链路验证）仍是待办。完整研究 + 落地计划见
  [doc/notes/2026-07-31-ios-pip-feasibility.md](notes/2026-07-31-ios-pip-feasibility.md)。
- **应用内悬浮窗降级（阶段3，已落地，跨平台可用）**：`MovaPipOverlay`
  （`lib/src/ui/components/pip_overlay.dart`）不是系统 PiP——只是插入本应用
  自己根 `Overlay` 的一个可拖动/可缩放小窗，应用退到后台就会消失。
  `PipButtonComponent` 不再在 `pipSupported == false` 时隐藏自身：现在会始终
  渲染，点击时 `pipSupported == true` 调 `MovaApi.enterPip()`，否则调
  `MovaPipOverlay.show()` 把现有视频画面缩进悬浮窗，应用其余部分仍可正常使用。
  示例见 `example/lib/main.dart` 的"画中画悬浮窗兜底演示"入口。
- `MovaState.pipSupported` / `MovaApi.pipSupported`（阶段 C）：engine 构造后不久
  用 `MovaPipPort.isSupported()` 探测一次（默认 `false`，探测失败也归约为
  `false` 而不抛出）；现在只决定 `PipButtonComponent` 点击后走系统 PiP 还是
  悬浮窗降级，不再决定按钮本身是否显示。

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
- **iOS PiP：阶段1骨架已落地（假帧，未真机验证），阶段3应用内悬浮窗降级已落地**。
  可行性已调研，方向定为 ASBDL + CVPixelBuffer；门槛 spike（阶段0，定档取帧路径
  A/B/C）与阶段2真实帧、阶段5全链路验证仍需 Mac + iOS 15+ 真机，尚未开始。
  研究 + 落地计划见 [doc/notes/2026-07-31-ios-pip-feasibility.md](notes/2026-07-31-ios-pip-feasibility.md)。
- **真机未验证**（手势手感、HLS 联网切档、Android PiP 实际行为、iOS 整体播放）
  承自 0.1.0，并入阶段 D 一并验证。
- **锁定态无法解锁**：`LockMaskComponent`（`lib/src/ui/components/overlays.dart`）
  的注释里早已写明这是刻意的范围缩减——只吞点击、不提供任何解锁交互，0.1.0
  "点一下锁屏图层短暂弹出解锁按钮"的完整流程被推迟。阶段 B Windows 实跑
  （2026-07-31）验证到：锁定后确实连 UI 都无法解锁，只能重启应用。留待阶段 D
  或后续打磨时补上最小可用的解锁交互（例如点击遮罩短暂展示解锁按钮、不点击
  则自动隐藏）。
