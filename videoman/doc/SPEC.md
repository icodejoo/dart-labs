# videoman 技术规格（SPEC）

配套阅读：[PRD.md](PRD.md)（需求/决策）、[ROADMAP.md](ROADMAP.md)（里程碑）、
[DESIGN-0.2.0.md](DESIGN-0.2.0.md)（0.2.0 重构的原始设计，含尚未实现的阶段
B/C 细节）。本文档描述**当前代码实际落地**的架构；与 DESIGN 文档冲突之处
以本文档为准（阶段 A 落地过程中做过的微调见文末）。

## 架构分层

```
lib/
├─ videoman.dart                      # 对外唯一入口 barrel
├─ videoman_platform_interface.dart   # 平台通道接口（getPlatformVersion / isPipSupported / enterPip）
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
   │  ├─ options/live_config.dart     # VmLiveConfig
   │  ├─ options/strings.dart         # VmStrings（文案外置，默认简体中文）
   │  ├─ options/theme.dart           # VmTheme（配色/尺寸外置，ARGB int 存储）
   │  ├─ model/source.dart            # VmSource / VmStreamType
   │  ├─ model/quality.dart           # VmQuality + parseHlsMasterPlaylist（纯函数）
   │  ├─ model/fit.dart               # VmFit(contain/cover/fill)
   │  └─ platform/ports.dart          # VmBrightnessPort / VmPipPort / VmOrientationPort
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
      ├─ skins/skin.dart              # VmSkin 抽象（components()/assemble()）
      ├─ skins/default_skin.dart      # VmDefaultSkin：VOD/Live 共用，按 VmState.type 换 bottomBar 分支
      └─ components/                  # 叶子/组合组件：top_bar/bottom_bar/live_bar/center_play/
                                       # gesture_layer/hud_layer/overlays/common
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
- `VmApi.seek()` 在直播时被引擎忽略；直播"回到边缘"用 `backToLiveEdge()`
  （内部重开当前源）。
- `VmPlayer` 组合渲染画面 + `VmSkin.components(state)` 出的组件树
  （经 `buildSlots()` 分槽）+ `VmSkin.assemble()` 拼装 `Stack`；默认皮肤
  `VmDefaultSkin` 复刻 0.1.0 的分栏布局与"隐藏时可穿透点击"规则。

## 组件树 / 皮肤 / 补丁

- `VmComponent`：`name`（树内寻址用）+ `slot`（归属的 `VmSlot`）+
  `children` + `build(context, api, children)`。叶子组件 `children` 为空；
  组合组件（如 `TopBarComponent`）持有多个子组件。
- `VmSkin.components(VmState s)` 返回顶层组件列表，可依据 `s`（如
  `s.type == VmStreamType.live`）切换分支——VOD 用 `BottomBarComponent`，
  直播用 `LiveBarComponent`，二者顶层 `name` 都是 `bottomBar`，是刻意设计的
  替换点。
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
  `timeshift`/`backToEdge`/`auto`/`quality` 九个字段，默认简体中文；
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
  90s 满屏宽，来自 `VmGestureConfig.hSeekSpanPerScreen`，可配）；直播禁用。
- 竖滑：左侧竖滑→音量（0–100），右侧竖滑→亮度（0–1），系数
  `VmGestureConfig.vSensitivity`。
- 双指缩放：`onScaleUpdate` 进入 zoom，`clamp(1, maxZoom)`。
- 双击：按 `VmGestureConfig.doubleTapStep`（默认 10s）快进退。
- 亮度经 `VmBrightnessPort`（生产实现用 `screen_brightness`），平台不支持
  时兜底 1.0。

## 清晰度 / ABR

- `parseHlsMasterPlaylist(content, base)`：解析 HLS master，提取
  BANDWIDTH/RESOLUTION 变体；非 master 返回 `[]`。
- `switchQuality(q)`：保留播放态，点播下保位续播。
- ABR 策略是 `VmAbrConfig.policy`（类型 `VmAbrPolicy`，位于
  `core/options/abr_config.dart`，不是 DESIGN 文档原设想的
  `core/model/abr.dart`）；省略时默认 `VmBufferingAbr(threshold: stallThreshold)`。
  自动档不降档（交给 libmpv 原生 ABR）。

## PiP（原生）

- Dart 侧经 `VmPipPort`；Android `VideomanPlugin.kt` 用
  `PictureInPictureParams`，宽高比 `clamp(0.42, 2.39)`；iOS/桌面未实现，
  `isPipSupported()` 返回 `false`。

## 测试

- `test/core/`：`api_test.dart`/`bus_test.dart`/`compat_test.dart`/
  `engine_test.dart`/`interceptor_test.dart`/`kernel_contract_test.dart`/
  `model_test.dart`/`options_test.dart`/`ports_test.dart`/`purity_test.dart`
  （断言 `core/` 不 import Flutter）/`state_test.dart`。
- `test/ui/`：`bottom_bar_test.dart`/`format_test.dart`/`gesture_test.dart`/
  `live_bar_test.dart`/`orientation_test.dart`/`overlays_test.dart`/
  `player_test.dart`/`selector_test.dart`/`skin_test.dart`/
  `top_bar_test.dart`/`tree_test.dart`。
- `test/method_channel_test.dart`：平台通道桩。
- `test/support/`：`fake_api.dart`/`fake_kernel.dart`/`pump.dart` 测试基础设施。

**实测结果**（本次收口，`flutter test` 完整输出，见 Task 19 报告的 Step 3
原始命令输出）：**91 tests passed, 0 failed**（末行 `00:04 +91: All tests
passed!`，2026-07-31 本机实跑）。

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

1. **阶段 B：拖动预览缩略图——未开始**。`preview/` 全套（`VmThumbSource`/
   `VmFrameExtractor`/`VmTwoLevelCache`/`VmPreviewService`）+ `preview`
   组件 + 网络策略。**先做的事**：DESIGN §11 风险表第一条——实测
   `screenshot-raw` 的分辨率语义（Windows 桌面写最小验证脚本），不通则改走
   `VideoControllerConfiguration(width/height)` 并回写 DESIGN 文档。
2. **阶段 C：直播时移——未开始**。`live/timeshift.dart` 窗口/behind 纯函数 +
   复用 seekBar + `liveBadge`/`timeshift`/`backToLive` 组件 + 手势门控；
   DVR 窗口默认靠内核 duration 推断，需提供 `dvrWindow`/`windowResolver`
   覆盖点。
3. **阶段 D：收尾发布——未开始**。README/CHANGELOG/example 补齐 VOD/直播/
   时移三个 demo、真机一轮验证（手势手感、HLS 联网切档、Android PiP
   实际行为、iOS 整体播放，均承自 0.1.0 尚未在真机验证）、
   `flutter pub publish --dry-run` 0 warnings，发布 0.2.0。

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
- **真机未验证**（手势手感、HLS 联网切档、Android PiP 实际行为、iOS 整体播放）
  承自 0.1.0，并入阶段 D 一并验证。
