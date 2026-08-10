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
* **新增 `MovaApi.screenshot()`**：截取当前视频帧并编码为 JPEG 字节返回；保存/分享/
  应用内使用均由调用方决定，库本身不管落盘。
* **新增 `MovaApi.loadSubtitle(uri)`**：加载并激活一个外挂字幕轨（ASS/SRT/WebVTT），
  区别于已封装进当前媒体的内封字幕轨。渲染完全由 libmpv/libass 直接合成进解码帧，
  与 `subtitle.dart` 里 STT 语音转字幕那套 Flutter 侧渲染是两条不同路径。
* **修复：错误浮层可能对一个自愈的探测失败误报**。`MovaEngine` 现在把内核错误先
  按住 400ms 防抖：若期间有新的位置更新到达（证明播放已自行恢复，例如硬解探测
  失败后自动软解成功），错误从始至终不会展示；只有确实没有恢复的错误才会
  展示出来。此前任何错误级别日志（包括这类会自愈的）一旦出现就永久卡在错误
  浮层上，直到 `open()`/`reload()`。

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
