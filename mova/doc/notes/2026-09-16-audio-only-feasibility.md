# 仅音频播放（audio-only）——可行性预研，不动手实现

> 2026-09-16 · 调研笔记。诉求：同一个项目里既要放视频也要放纯音频，希望
> mova 一个插件包圆，但**音频那条路不能背视频的资源开销**。

**结论先行：选 ③ 折中，且这个折中比预想的便宜得多——因为 media_kit 的
`Player` 默认就是 `--vid=no`（不解码视频），是 mova 自己在 `MpvKernel` 构造里
无条件 `VideoController(_player)` 把视频管线打开的。所以"音频模式"的核心
改动只有一句：不建那个 `VideoController`。放开 `MovaKernel.renderHandle` 的
可空性 + 一个 `audioOnly` 开关 + 一份文档，约 3–4 Task，远不到阶段 C（9 Task）
的量级。**

**但不建议做成"一等公民音频模式"**：真正让音频 App 难做的不是解码开销，是
熄屏后台常驻、锁屏/通知栏控制、耳机线控、音频焦点、gapless 这一整套系统集成面——
mova 一样都没有，补齐是 ≥ 阶段 C 的新原生代码工程。那一块应该由
[just_audio](https://pub.dev/packages/just_audio) +
[audio_service](https://pub.dev/packages/audio_service) 承担。**分流判据只有一条：
需不需要熄屏后台常驻 + 系统媒体控制。**

---

## 1. 纯音频 vs 视频：设备压力差多少

先说量级结论：**内存差约两个数量级（MB 级 vs 近百 MB 级），CPU 与电量差一个数量级
以上**。不是"省一点"，是完全不同的开销档位。逐项拆开看钱花在哪：

### 1.1 内存——大头全在视频侧，且音频没有任何对应项

以 1080p H.264 + AAC-LC 立体声为基准：

| 项 | 视频链路 | 音频链路 |
|---|---|---|
| 解码后帧缓冲 | 1920×1080 YUV420p = **3.11 MB/帧**；H.264 DPB 最多 16 参考帧（实际常见 4–5），叠加 mpv 自己的解码队列与 vo 队列，**常见 30–80 MB** | 无 |
| 硬解路径 | 帧挪到 GPU/ION，但要喂满 MediaCodec 通常需 8–12 个 output buffer，**数量级不变**，只是从 heap 记到 graphics 一栏 | 无 |
| Flutter 纹理 | media_kit_video 要把帧搬进 GL 纹理交给 Flutter 合成，1080p RGBA8888 = **8.29 MB/张**，双缓冲 ≈ 16 MB GPU | 无（不注册 Texture） |
| PCM 环形缓冲 | 有（同左） | 48 kHz 立体声 f32 ≈ 384 KB/s，加 ao 缓冲，**几百 KB 到个位数 MB** |
| demuxer 字节缓存 | 同一个字节上限，但视频 3–8 Mbps，"缓 30 秒"要十几 MB | 128 kbps，同样缓 30 秒只要 **几百 KB**，差 25–60 倍 |

**关键点不是"音频的缓冲更小"，是视频那三项在音频模式下压根不存在**——帧缓冲、
GPU 纹理、Flutter Texture 注册，都是 0 而不是变小。这就是两个数量级的来源。

### 1.2 CPU

- 1080p30 H.264 软解在移动端大核约占 **30–60% 单核**；AAC-LC 立体声解码约 **1–3%**。
- 硬解把解码挪进专用块，CPU 占用降到个位数，但换来一条**每秒 30–60 次**的
  "取帧 → 上纹理 → Flutter 合成 → 提交"流水线，这条 Flutter 侧的固定开销音频完全没有。
- 也就是说，无论软解硬解，视频都比音频高一个数量级以上；硬解只是把账从 CPU 挪到 GPU。

### 1.3 电量

三块叠加，每块都是数量级差：

1. **屏幕**：视频必须亮屏，手机面板 200–500 mW 起步，通常是整机最大单项；纯音频可以熄屏。
2. **GPU 合成**：视频每帧一次，音频为零。
3. **无线电**：码率差 25–60 倍，而 radio 常年是移动设备第二大耗电源。

经验量级：纯音频熄屏后台播放整机常在**数十 mW**，前台视频播放在**数百 mW 到 1 W+**。

> ⚠️ **诚实标注**：以上是按编解码参数与公开工程共识推算的量级，
> **不是本仓库的实测数字**。调研没能找到可引用的第三方"libmpv 音频 vs ExoPlayer 音频"
> 基准（media_kit 官方只有 "bundle size is minimal" 这种定性说法）。本仓库唯一带真实数字的
> 一手数据是 `mova-libmpv` 那次 Android arm64 体积实测（11.80 MiB → 6.61 MiB），
> 但那是**视频场景的体积维度**，套不到这里。真要精确数字得自己上真机 profiling。

### 1.4 一个容易忽略的项：包体积不随模式变

上面说的都是**运行时**开销。包体积是另一回事：只要还链着
`media_kit_libs_video`，那 ~11.8 MiB/ABI 的 `libmpv.so`（含 ffmpeg）就照样在包里，
不管你运行时放不放视频。这是下面第 3 节权衡的重要输入。

---

## 2. mova 现在的架构够不够：够，而且成本比想象低

### 2.1 决定性发现：media_kit 默认就不解码视频

查证 `media_kit-1.2.6/lib/src/player/native/player/real.dart:2319-2326`（`_create()`）：

```dart
final options = <String, String>{
  // Set --vid=no by default to prevent redundant video decoding.
  // [VideoController] internally sets --vid=auto upon attachment to enable video rendering & decoding.
  if (!test) 'vid': 'no',
};
```

**任何 `Player()` 一创建就是 `vid=no`**，是
`VideoController.create()`（`media_kit_video-2.0.1/lib/src/video_controller/native_video_controller/real.dart:156-162`）
在 attach 时才把它改回来：

```dart
await controller.setProperties({
  'vo': configuration.vo!,
  'hwdec': configuration.hwdec!,
  'vid': 'auto',
});
```

而 mova 的 `MpvKernel` 构造函数里（`lib/src/core/kernel/mpv_kernel.dart:29-30`）：

```dart
MpvKernel({Player? player}) : _player = player ?? Player() {
  _controller = VideoController(_player);   // ← 就是这一句，无条件打开视频管线
```

**结论：第 1 节列举的全部视频侧开销，在 mova 里是被这一行打开的。不建这个
`VideoController`，libmpv 就已经是纯音频播放器了——不需要动内核、不需要新依赖、
不需要改 media_kit。**

补充两个逃生舱，供"播到一半从视频切成纯音频"这种运行时场景：

- `player.setVideoTrack(VideoTrack.no())` —— 公开 API，直接映射 mpv `vid` 属性
  （`real.dart:975-1004`；`VideoTrack.no()` 见 `models/track.dart:133`）。
- `Player.platform.setProperty(name, value)`（`real.dart:1223` 起）—— 可下发任意 mpv 属性。

mpv 语义上也确认了正确姿势：**`--vid=no` 才是省解码开销的做法**；`--vo=null` 只是不渲染、
照样解码（media_kit 仅在单测模式下用它，`real.dart:2440-2442`）。

### 2.2 `renderHandle` 怎么办：改一行，UI 层零改动

当前形状：

| 位置 | 声明 | 音频模式下的处置 |
|---|---|---|
| `lib/src/core/kernel/kernel.dart:148` | `Object get renderHandle;`（**非空**） | 需放宽为 `Object?` |
| `lib/src/core/kernel/mpv_kernel.dart:152` | `Object get renderHandle => _controller;`（`late final`，构造期绑死） | `audioOnly` 时返回 `null` |
| `lib/src/core/api.dart:71` | `Object? get renderHandle;`（**已经可空**） | 不动 |
| `lib/src/core/engine.dart:74` | `Object? get renderHandle => _kernel.renderHandle;` | 不动 |
| `lib/src/core/swap/swap_engine.dart:161` | `Object? get renderHandle => _active.renderHandle;` | 不动 |

**只有 `kernel.dart:148` 一行要改**（`Object` → `Object?`）。对实现者不是破坏性改动
（返回 `Object` 仍满足 `Object?`），对调用者只多一个 null 分支——而唯一的调用者
`MovaEngine` 早就声明成可空了。测试替身 `test/support/fake_api.dart:182` 也已是
`Object? renderHandle`。

UI 层更省事，`_RenderSurface`（`lib/src/ui/player.dart:191-198`）本来就是：

```dart
final video = handle is VideoController
    ? Video(key: _RenderHandleKey(handle), controller: handle, ...)
    : ColoredBox(key: _RenderHandleKey(handle), color: const Color(0xFF000000));
```

`null` 天然落进 else 分支，**不会崩**。这个分支原本是给 widget 测试留的黑色占位，
音频模式白捡。

而且"黑块"并不是音频 UI 的最终答案，也不需要为此改结构——`MovaPlayer` 已经有
`surface` 参数（`player.dart:73`，feed 页用它传"引擎未就绪"的占位）。音频场景直接
复用同一个口子传封面图/波形/歌词面即可，**UI 侧一行结构改动都不用**。

### 2.3 剩下的零碎（都不是硬骨头）

- **视频语义的状态与组件**：`MovaState.size`、`fit`/`zoom`、全屏、PiP、亮度手势在音频下
  无意义。最干净的做法是写一个 `MovaAudioSkin`（`lib/src/ui/skins/` 下已有
  default/bilibili/douyin 三个，加一个是熟路），`components()` 里不装这些组件——
  **而不是**在每个组件里加 if。
- **`screenshot()`**（`mpv_kernel.dart:117`，阶段 B 预览抽帧的兜底）在音频下应返回 `null`；
  预览缩略图功能整块对音频无意义，`MovaPrevConfig` 关掉即可。
- **`loadQualities()`** 对非 HLS 已经是 no-op（`player.dart:88-95` 的注释写明了），不用管。
- **配置落点现成**：`MovaOpts` 已经是一组 `MovaXxxConfig` 的组合
  （`lib/src/core/options/options.dart:39-98`：preview/live/gesture/abr/controls/danmaku/
  stt/playlist/ads/swap），加一个 `MovaAudioConfig` 或直接在 `createMovaEngine()` 上加
  `audioOnly` 参数（`lib/src/platform_impl/wiring.dart:99`）都顺理成章。
- **可选的更狠一步**：换成官方的 `media_kit_libs_*_audio` 包，连视频原生库都不打进去。
  但这是**编译期**二选一——官方 README 明说两者不可混用，且换了之后
  `VideoController.create()` 里的 `queryDecoders()` 查不到 h264 会直接抛
  `UnsupportedError`（`real.dart:130-142`），**整个 mova 的视频功能会物理失效**。
  对"既要视频又要音频"的目标用户，这条路直接排除。

### 2.4 工作量分级

| 方案 | 量级 | 校准参照 |
|---|---|---|
| 最小改动（`audioOnly` 开关 + `renderHandle` 可空 + 文档 + 单测） | **3–4 Task** | 远小于阶段 C（直播时移，9 Task） |
| 上面 + `MovaAudioSkin`（封面/歌词/音频控制条） | 6–8 Task | 接近阶段 C |
| 一等公民音频模式（含后台常驻、锁屏/通知栏、耳机线控、音频焦点、gapless、播放列表） | **≥ 15 Task，且大头是新原生代码** | 超过阶段 B（拖动预览，15 Task） |

第三档为什么最贵：Android 要 `MediaSessionService` + 前台服务 + 通知栏 + `AudioFocus`，
iOS 要 `AVAudioSession` 分类配置 + `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter`，
桌面还各有一套。这是从零起的原生工程，跟 PiP/音量/方向那几个单方法端口不是一个量级——
**而这恰恰是成熟音频插件生态已经做完的部分。**

---

## 3. 自己做 vs 另配专用插件

### 3.1 生态现状（2026-09-16 实查）

| 包 | 最新版本 / 最近发布 | Likes | Points | 下载 | 底层实现 |
|---|---|---|---|---|---|
| [just_audio](https://pub.dev/packages/just_audio) | 0.10.6 / ~2 月前 | 4.15k | 150 | 1.11M | Android **ExoPlayer**、iOS/macOS **AVPlayer**；Flutter Favorite |
| [audioplayers](https://pub.dev/packages/audioplayers) | 6.8.1 / ~2 月前 | 3.4k | 150 | 1.23M | Android 自有实现（另有 `audioplayers_android_exo` 走 Media3）、Linux **GStreamer** |
| [audio_service](https://pub.dev/packages/audio_service) | 0.18.19 / ~2 月前 | 1.3k | 140 | 206k/周 | 不含解码，只做后台/通知/锁屏壳；Linux 走 MPRIS |
| [assets_audio_player](https://pub.dev/packages/assets_audio_player) | 3.1.1 / **约 3 年前** | 1.1k | 110 | 1.6k/周 | **事实停滞**，社区 fork 接手，不推荐 |
| [media_kit](https://pub.dev/packages/media_kit)（对照） | 1.2.6 / ~9 月前 | 914 | 140 | 338k | 全平台 libmpv（web 除外） |

GitHub star：just_audio ~1.2k、audioplayers ~2.1k、audio_service ~854、media_kit ~1.8k。

### 3.2 "专用音频插件更轻"——移动端成立，桌面端不成立

**这是本节最重要的一条**：just_audio 的 Windows/Linux 支持，现在本身就是
[`just_audio_media_kit`](https://pub.dev/packages/just_audio_media_kit)——**借壳 media_kit/libmpv**。
早期的 `just_audio_libwinmedia`、`just_audio_mpv` 都已废弃
（[just_audio#1274](https://github.com/ryanheise/just_audio/issues/1274)）。
`just_audio_windows` 是另一条 Media Foundation 路径，与之并存。

所以分平台看：

- **Android / iOS**：just_audio → ExoPlayer / AVPlayer，是**系统自带或系统级组件**，
  不额外打包一整套解码器；相比 mova 那 ~11.8 MiB/ABI 的 `libmpv.so`，**包体积优势是真的**，
  运行时开销也更贴近系统优化路径（这一点是工程共识，无公开基准数字，见 §1.3 的标注）。
- **Windows / Linux**：绕一圈还是 libmpv。**"更轻"不成立**，反而多一层 platform-interface
  包装，还多一个依赖。

而 §2.1 已经证明：在 libmpv 里关掉视频解码是 media_kit 的默认行为、零成本。
所以"通用框架 vs 原生播放器"这条差异，**真正剩下的只有包体积和系统集成面，不是解码开销**。

### 3.3 双插件共存的真实代价（不能只算好处）

- **包体积是两套**：既链 `media_kit_libs_video`（视频要用，躲不掉）又链 ExoPlayer/AVPlayer。
- **音频焦点要自己协调**：来电、另一路开始播、耳机拔出时，两个播放器互不知情，
  谁暂停谁恢复得宿主自己写仲裁。这是最容易出线上 bug 的地方。
- **两套 API 心智**：状态模型、错误模型、seek 语义都不一样。

### 3.4 建议：选 ③ 折中 + 一条分流判据

**mova 侧做最小改动（§2.4 第一档，3–4 Task）**，把"现有 API 在音频源下不崩、不强制
建视频 Surface"这件事做实，覆盖这类场景：

- 视频 App 里偶尔播一段纯音频（有声解说、播客式长音频、纯音频直播、音频广告）；
- 这些内容**和视频共用同一套控制条、手势、时移、ABR、广告逻辑**——换插件反而要把这些再实现一遍。

**不做的部分，文档里明确指路 just_audio + audio_service**：

- 音乐播放器级场景：歌单、熄屏后台常驻、锁屏/通知栏控制、耳机线控、gapless。

**分流判据就一条，写进 README 即可：**

> 需要熄屏后台常驻 + 系统媒体控制吗？
> 需要 → just_audio + audio_service。
> 不需要（只是前台界面里放一段音频） → mova 的 `audioOnly` 模式，别多引一个插件。

这条判据之所以干净，是因为它正好切在"mova 缺的东西"和"mova 已有的东西"的分界线上：
解码侧 mova 零成本就能做好，系统集成侧 mova 从零做要 ≥ 15 Task。

### 3.5 为什么不选 ① 和 ②

- **不选 ①（一等公民音频模式）**：§2.4 第三档的账算不过来。为了"一个插件包圆"这个
  形式上的整洁，去重写一遍 audio_service 已经做了五年的东西，且要四端各写一套原生代码——
  跟 mova "视频播放器 + 自研手势控制层" 的定位也不符。
- **不选 ②（完全不做，只推荐第三方）**：成本对比太悬殊了。让宿主为"播一段纯音频"多引一个
  插件、多背一套音频焦点协调，而 mova 这边只要改一行可空性 + 不建一个对象就能省掉近百 MB
  内存和一整条 GPU 合成流水线——**白放着不拿说不过去**。而且 §2.2 显示 UI 层已经天然兼容
  `null` handle，等于这个能力已经半成品地存在了，只是没人能开。

---

## 4. 若决定做，下一步

照阶段 B/C 的规矩拆一份逐 Task 计划落在 `doc/plans/`，骨架大致是：

1. `MovaKernel.renderHandle` 放宽为 `Object?`（`kernel.dart:148`），跑一遍 `flutter analyze` 确认无连带破坏。
2. `MpvKernel({bool audioOnly = false})`：`audioOnly` 时不建 `VideoController`，`renderHandle` 返回 `null`，`screenshot()` 返回 `null`。
3. `createMovaEngine(audioOnly: ...)` 透传（`wiring.dart:99`）；`MovaSource` 上是否也要一个 `audio` 类型待定（当前 `MovaStreamType` 只有 vod/live，`model/source.dart:4-14`）——倾向**不加**，因为"音频"是引擎构造期的资源决策，不是源的流类型。
4. 单测：`audioOnly` 引擎的 `renderHandle` 为 null；`MovaPlayer` 在 null handle 下不抛、渲染占位；`surface` 参数传自定义封面面时正常。
5. README/SPEC 补一节，写清 §3.4 的分流判据。
6. 真机验证一次内存差（`dumpsys meminfo` 三阶段对比，沿用 feed 引擎池那次的测法，`doc/SPEC.md:279-284`）——**这是唯一能把 §1 的推算变成实测数字的机会，值得顺手做**。

**本次先停在可行性预研，等确认要不要投入再拆计划。**
