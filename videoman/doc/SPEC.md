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
   也从未上过真机——见文末「真机验证结果」一节）。

**未来项（未排期，见 PRD ADR）**：实时语音转文字字幕 + AI MCP 集成钩子——两条均为条件性/
投机性的前瞻记录，非本阶段（B/C/D）范围，详见 [doc/PRD.md](PRD.md) 非功能需求/决策记录。
若后续评估后启动，大致落点：

- **STT 字幕**：预计新增一个 core 端口抽象（类似 `VmFrameExtractor`/`VmNetProbe`），放在
  `lib/src/core/`，具体实现放 `lib/src/platform_impl/` 下——消费 media_kit/libmpv 若能暴露的
  原始音频数据，或转发给外部 STT 服务；转写结果作为字幕流回灌到 UI 层的一个新叠层组件
  （类似 `preview`/字幕类组件），走既有组件树/皮肤/补丁机制，不改变 `VmApi` 之外的契约。
- **MCP 钩子**：预计不会成为核心依赖，更可能是一个可选的 `VmInterceptor` 实现或独立的事件流
  消费者，订阅播放状态/字幕文本等只读上下文，并可选择性地接收外部指令；核心库不直接依赖
  MCP SDK，接入方式留给上层应用或独立扩展包。

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
