# iOS 系统级画中画（PiP）可行性研究与方向

> 2026-07-31 · 调研笔记 + ADR 草案 · 对应剩余任务 #5（iOS PiP，承自 fvideo）
>
> 结论先行：**技术上可行，但取帧路径需要一次真机 spike 才能定档。** 现阶段（无
> 确认的 Mac 环境）只出方向与计划，不写实现代码。

## 1. 问题本质

iOS 的系统 PiP 只认两类内容源：

- `AVPlayerLayer`——只服务于 `AVPlayer` 播放的内容；
- `AVSampleBufferDisplayLayer`（ASBDL）+ `AVPictureInPictureController`——喂
  `CMSampleBuffer`，可承载**任意自渲染画面**（iOS 15+ 用
  `AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer:playbackDelegate:)`）。

mova 的画面由 **libmpv** 解码渲染，不是 `AVPlayer`，所以 `AVPlayerLayer` 那条
免费路走不通。必须走 ASBDL：把每帧变成 `CVPixelBuffer` → 包成 `CMSampleBuffer` →
`enqueue` 给 ASBDL。业界（flutter-webrtc、LiveKit、腾讯云 RTC、各家 RTC SDK）的自渲染
PiP 全是这条路，**范式成熟、可行性无疑**。

> 于是整个 iOS PiP 的成败**收敛到一个问题**：能否稳定、够快地从 libmpv 拿到每帧的
> `CVPixelBuffer`？其余都是范式代码。

## 2. 关键发现：media_kit 在 iOS 本就产出 CVPixelBuffer

media_kit 的 iOS/macOS 渲染并非黑箱：`media_kit_video` 的原生 `VideoOutput` 把 libmpv
的 OpenGL 输出渲染进一个 **IOSurface/pixel-buffer 支撑的纹理**，并通过 Flutter 的
`FlutterTexture` 协议暴露 **`copyPixelBuffer() -> CVPixelBufferRef`**。也就是说——

**iOS 上每一帧的 `CVPixelBuffer` 客观上已经存在**，正是喂 ASBDL 需要的东西。难点不在
"能不能生成帧"，而在"我们的插件能不能拿到 media_kit 那份帧"。

### 2.1 渲染机制与性能澄清（前提修正，别按错误前提做决定）

调研中出现两个常见误解，先钉死，免得后续按错误前提推导：

**误解一："media_kit 用原生渲染、video_player 用 Flutter 纹理，所以 media_kit 更快。"**
——不成立。**两家在 Android 都渲进 Flutter 外部纹理（Texture Registry / `SurfaceTexture`）**，
都不是绕过 Flutter 合成的 platform view/SurfaceView。区别在**解码+视频输出**：ExoPlayer
是 MediaCodec→Surface；media_kit 是 libmpv `--hwdec=mediacodec --vo=mediacodec_embed
--wid=<Surface>`，硬解直接画到那个 Surface。两条都是硬件加速、都落 Flutter 纹理，**性能
同量级**，media_kit 没有靠"绕过 Flutter"取得优势。media_kit 的真优势是**格式覆盖、同实例
`open()` 换源复用、跨平台一致、可控性**，不是渲染吞吐；且 libmpv 是重引擎，**内存开销常
更高**。

**误解二："Flutter 纹理渲染视频性能不好、不如原生。"**——半对，要说清"不如哪种原生"。
按 Android 图形架构：**SurfaceView** 能被 SurfaceFlinger 当**硬件 overlay 平面**直合、
不走 GPU 合成，最省（尤其省电）；**TextureView / Flutter `Texture`（外部纹理）**必须由
**GPU 把视频帧与 UI 合成一遍**。所以"不如原生"特指**不如 SurfaceView 的 overlay 直合**，
这是外部纹理方案的通性（原生 TextureView 一样吃这亏），不是 Flutter 独有坑。但外部纹理
是 **GPU 直连、零拷贝**，日常单路 1080p/4K 基本无感；差距只在续航/多路同屏/超高分辨率/低端
GPU 才放大。

**"那 SurfaceView 上不能叠 Flutter UI 吗？"能，但不划算。** 经 Platform View 的
Hybrid Composition 可把 SurfaceView 插进原生视图树、再叠 Flutter UI。但代价把想要的
overlay 优势吃回去：① **overlay 平面会被叠爆 → 退回 GPU 合成**——SurfaceView 省电靠
SurfaceFlinger 把它当硬件 overlay 直合，可一旦上面叠 Flutter UI，Flutter 要为这些 UI 造
额外 overlay surface，设备硬件 overlay 平面数量有限（常见 ~4），叠加的半透明控件一多就
超额，SurfaceFlinger 回退 GPU 合成，**省电在"UI 叠视频"场景基本又没了**；② **Hybrid
Composition 自带开销**（额外 surface、历史线程合并卡顿、每 view 成本、动画更明显）；
③ **SurfaceView 是"打洞"独立窗口，旋转/缩放/圆角/透明/裁剪都受限**，与双指缩放、全屏转屏
等相冲。

**对 mova 的意义**：mova 在视频上叠了大量 UI/手势（控制条、HUD、预览、侧栏）
且有变换需求，**这正是 SurfaceView overlay 优势消失、纹理路线反而更合适的场景**——
overlay 的省电在你真正需要叠 UI 的那一刻就蒸发，还倒贴混合合成的税和变换的麻烦。所以
"纹理慢"这条对 mova **最不适用**，**不值得为省那一道合成去重开 SurfaceView/
platform-view 路**。渲染路线维持 media_kit 的 Flutter 纹理既定架构；真要抠 4K 续航再单独
评估。SurfaceView overlay 真正划算的是"纯全屏、几乎不叠 UI、极度在意续航"的播放器。

## 3. 取帧的三条候选路径

### 路径 A — 复用 media_kit 现成的 CVPixelBuffer（若够得着，最省）

`VideoOutput.copyPixelBuffer()` 已经在产出帧。理想做法：拿到 media_kit 的
`VideoOutput` 实例，PiP 激活时用一个 `CADisplayLink` 定时 `copyPixelBuffer` 拉帧、包
`CMSampleBuffer` 塞 ASBDL。
- **优点**：零第二渲染路、与主画面天然同一份像素、性能等同现状。
- **卡点**：`copyPixelBuffer` 是 Flutter 合成器回调的，不是给外部插件的公开面；跨插件
  拿不到 media_kit 的 `VideoOutput` 句柄。要么 **media_kit 上游加钩子**暴露 pixel
  buffer / VideoOutput，要么 **fork `media_kit_video`**，要么靠 texture-id + ObjC
  runtime 反射硬取（脆、随版本崩，不可取）。
- **判定**：像素层面最干净，但**受制于 media_kit 不暴露取帧面**。第一步 spike 先探
  media_kit 是否有（或愿意加）这个面。

### 路径 B — 自开第二个 libmpv 渲染上下文，走软件渲染（`MPV_RENDER_API_TYPE_SW`）

在**同一个 mpv 句柄**上再建一个 render context，用 SW API
（`MPV_RENDER_PARAM_SW_SIZE/FORMAT/STRIDE/POINTER`）把帧渲染进我们自己的
`CVPixelBuffer` 内存，仅 PiP 激活时按 `CADisplayLink` 跑。
- **优点**：完全不依赖 media_kit 内部；API 明确存在。
- **卡点**：mpv 官方明确警告 SW 渲染是 **CPU 单线程、含色彩转换/缩放/OSD 全在 CPU，
  大尺寸下"慢到不够实时"**。PiP 窗口小（约 480×270），25–30fps *也许* 扛得住，但有
  风险；且 libmpv 通常**一个句柄一个 render context**，与 media_kit 的 GL context
  并存是否冲突需实测。
- **判定**：不依赖上游是优点，但**性能 + 并存两点都要 spike 验证**。

### 路径 C — 自开第二个 GL/Metal 渲染上下文，渲进自有 IOSurface

同 B，但用 GL 或 MoltenVK/Metal（mpv `--gpu-context=moltenvk` + `CAMetalLayer`，见
mpv PR #7857，2023 已合入）渲进我们自己的 IOSurface-backed `CVPixelBuffer`，比 SW 快。
- **卡点**：同样面临"一个 mpv 句柄能否并存两个 render context"的问题，需实测。
- **判定**：性能优于 B，复杂度也更高；作为 B 不达标时的升级项。

### 降级方案 — 应用内悬浮窗（非系统 PiP）

在 App 内浮一个复用现有 Flutter texture 的小窗。**不是系统 PiP**（App 退到后台就没
了），但跨平台（Android/iOS/桌面）、**不需要 Mac 就能建能测**，能先给到"小窗继续看"
的体感。可藏在同一个 `MovaApi.enterPip()` 面之下。

## 4. iOS 侧硬性约束（范式代码必须处理，已确认）

- **音频会话**：必须把 `AVAudioSession` 设为 `playback`/movie 类目，**否则即使静音，
  App 退后台时 PiP 也不会启动**。
- **后台模式**：`Info.plist` 的 `UIBackgroundModes` 要含 `audio`，PiP 才能在后台续。
- **系统版本**：ASBDL 内容源的 `AVPictureInPictureController` 需 **iOS 15+**；更早只有
  `AVPlayerLayer` 一条路（对我们不适用）。
- **模拟器不支持 PiP**——**只能真机测**。

## 5. 方向建议（ADR 草案）

- **决策**：iOS 系统 PiP 走 **ASBDL + `CVPixelBuffer`** 路线；保持现有 `MovaPipPort` /
  `MovaApi.enterPip()` / `pipSupported` 抽象不变，iOS 实现在 spike 定档后补齐。
- **取帧优先序**：A（探 media_kit 是否暴露/可加取帧面，最省）→ 不行则 B（SW，实测
  PiP 窗口尺寸下的 fps 与并存）→ B 太慢则 C（GL/Metal 第二上下文）。
- **并行可做（不需 Mac）**：先落"应用内悬浮窗"降级方案，藏在同一 API 面之下，立即可
  用、可在 Android/桌面验证；系统 PiP ready 后按平台切换真实现。

## 6. 门槛 spike（**需要 Mac + iOS 15+ 真机**）

一个最小实验回答唯一的定档问题：**能否把 libmpv 帧稳定送进 ASBDL、够不够实时。**

1. 建 ASBDL + `AVPictureInPictureController(ContentSource:)`，先用**假帧**（纯色/测试卡
   `CVPixelBuffer`）跑通 PiP 启停、音频会话、后台续播——验证范式与 plist/权限。
2. 探路径 A：查 `media_kit_video` iOS 公开面 / texture-id，判断能否合法拿到那份
   `CVPixelBuffer`（顺带看上游是否已有相关 issue/PR）。
3. 若 A 不可得，spike 路径 B：同句柄第二个 SW render context，PiP 窗口尺寸渲进
   `CVPixelBuffer`，**测 fps 与 GL context 并存稳定性**。
4. 记录结论，回填本文件 §5 定档，再排实现计划。

## 7. 待用户确认

- Mac + iOS 15+ 真机的可用性（§6 spike 的前置；当前"暂不确定"）。
- 是否先并行落"应用内悬浮窗"降级方案（不需 Mac，立即有产出）。

## 8. 落地计划（待定 —— spike 定档后按序执行）

保持 `MovaPipPort` / `MovaApi.enterPip()` / `pipSupported` 抽象不变，实现全在 iOS 原生侧 +
少量 Dart 收口。**阶段 0 是门槛,未过不进阶段 2。**

- [ ] **阶段 0 · 门槛 spike（需 Mac + iOS 15+ 真机，未开始）**：见 §6，定下取帧路径
  A/B/C。产出：一份"哪条路可行 + 实测 fps/稳定性"的结论，回填本文件 §5。
- [x] **阶段 1 · iOS PiP 骨架（假帧先跑通，2026-08-10 已写，未编译/未真机验证）**：
  - `ios/mova/Sources/mova/MovaPipController.swift` 起了
    `AVSampleBufferDisplayLayer` + `AVPictureInPictureController(contentSource:)`；
    `AVPictureInPictureSampleBufferPlaybackDelegate` 的播放/暂停/skip 回调是
    `// TODO(spike)` 空桩（真实透传要等阶段2）。
  - `AVAudioSession` 已设 `.playback`（`MovaPipController.start`）；
    `example/ios/Runner/Info.plist` 已加 `UIBackgroundModes: audio`。
  - 方法通道（`MovaPlugin.swift`）：`isPipSupported` 在 iOS 15+ 上探测
    `AVPictureInPictureController.isPictureInPictureSupported()`；`enterPip`
    启动 PiP，定时器按 30fps 灌入纯色测试卡 `CVPixelBuffer`（验证的是启停/
    音频会话/plist 范式，不是真实画面）。**这些代码从未在真机（甚至从未在
    Xcode）编译或运行过**——语法/API 签名是按知识核对的，非实测确认。
  - **Dart 侧网关刻意没跟着放开**：`lib/mova_method_channel.dart` 的
    `MethodChannelMova.isPipSupported()` 在 iOS 上无条件短路回报 `false`，
    不管原生探测回报什么——对应下面 SPEC 指导，`MovaApi.pipSupported` 要等
    阶段5真机验证过才允许在 iOS 上翻真。
- [ ] **阶段 2 · 接真实帧源（按 spike 选定路径，未开始）**：每帧 `CVPixelBuffer` →
  `CMSampleBuffer`（带 PTS/format desc）→ `enqueue` 给 ASBDL；把播放态/seek 与 `MovaApi`
  同步；`MovaPipController` 的 `AVPictureInPictureSampleBufferPlaybackDelegate`
  桩要在这一步补上真实转发。路径 A 需先解决 media_kit 取帧面（上游钩子/fork）。
- [x] **阶段 3 · 跨平台降级悬浮窗（不需 Mac，2026-08-10 已落地）**：
  `MovaPipOverlay`（`lib/src/ui/components/pip_overlay.dart`）复用现有
  Flutter/media_kit `VideoController`，藏在同一 `enterPip()` 调用点之下——
  `PipButtonComponent`（`lib/src/ui/components/top_bar.dart`）点击时
  `pipSupported` 为真走系统 PiP，否则打开悬浮窗；systemPiP ready 后自动按
  `pipSupported` 切换，无需改按钮逻辑。示例见 `example/lib/main.dart` 的
  "画中画悬浮窗兜底演示"；单测见 `test/ui/pip_overlay_test.dart` 与
  `test/ui/top_bar_test.dart`。
- [ ] **阶段 4 · Dart 收口（部分完成）**：`ChannelPipPort` 已就绪；方法通道单测
  仍缺（`enterPip`/`isPipSupported` 的桩/假帧场景）；`pipSupported` 在 iOS 返回
  `true` 后 `PipButtonComponent` 自动切到系统 PiP 路径的行为已实现（阶段3顺带
  做了），但由于阶段0/5未完成，Dart 网关仍锁 `false`，这条切换路径实际尚未被
  验证过。
- [ ] **阶段 5 · 真机验证（未开始）**：PiP 启停、退后台续、手势/seek 同步、画质、
  退出恢复、与全屏/转屏共存；通过后删掉
  `lib/mova_method_channel.dart` 里 `isPipSupported()` 的 `Platform.isIOS`
  短路网关。

**SPEC 指导（已回写 `doc/SPEC.md`）**：PiP 契约维持不变——iOS 实现落地前
`isPipSupported()` 仍返回 `false`、按钮自动隐藏；落地后仅该原生返回值 + `pipSupported`
探测变化，Dart/UI 面零改动。详见 SPEC「PiP（原生）」与「剩余任务」两节的待定标注。

## 参考

- Apple：`AVPictureInPictureController` 需 ASBDL 作内容源（自渲染 PiP 范式）
  https://developer.apple.com/forums/thread/821582
- mpv #8910 — iOS ASBDL 支持诉求（把 libmpv 帧送 `CMSampleBuffer`）
  https://github.com/mpv-player/mpv/issues/8910
- mpv #7852 — libmpv 渲染到内存 buffer 的 API 诉求（SW 渲染背景）
  https://github.com/mpv-player/mpv/issues/7852
- mpv PR #7857（已合入）— iOS 经 `--gpu-context=moltenvk` + `CAMetalLayer` 渲染
  https://github.com/mpv-player/mpv/pull/7857
- libmpv `render.h`（`MPV_RENDER_API_TYPE_SW` 与 `SW_*` 参数）
  https://github.com/mpv-player/mpv-examples/tree/master/libmpv
- media_kit（iOS/macOS 经 `copyPixelBuffer` 暴露 `CVPixelBufferRef`）
  https://github.com/media-kit/media-kit
- 自渲染 PiP 范式（腾讯云 RTC：CVPixelBuffer→CMSampleBuffer→ASBDL）
  https://www.tencentcloud.com/document/product/1228/73992
- iOS PiP 实现要点（音频会话/后台模式等坑）
  https://dev.to/sylar/ios-picture-in-picture-pip-implementation-guide-3b56
