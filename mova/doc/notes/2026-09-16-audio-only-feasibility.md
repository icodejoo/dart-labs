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

### 1.5 Windows 桌面端实测（2026-09-16，实现落地后补测）

> ⚠️ **这一节是 Windows 桌面 RSS 实测，不是 Android/iOS 真机数据，两者不能直接类比。**
> 桌面没有 MediaCodec/ION 那条硬解路径，GPU 内存记账方式也与移动端完全不同（移动端
> 要分 `Graphics`/`GL mtrack` 两栏，桌面全算进进程 RSS）。移动端的三阶段
> `dumpsys meminfo` 对账仍然欠着，见实现计划 Task 5。

**怎么测的**：`example/lib/perf_probe_audio_only.dart`，读 `dart:io` 的
`ProcessInfo.currentRss`——本进程真实的常驻内存，直接来自操作系统，不是推算。
release 构建、Windows 桌面、**同一条素材**（854×480 H.264 + AAC，60.1 秒），
三阶段采样：进程基线（引擎尚未创建）/ 稳定播放 60 秒后 / `dispose()` 后。
探针挂载真实 `MovaPlayer`，使视频模式确实注册并合成 Flutter 纹理——测一个无人渲染的
视频引擎会低估它的开销。每个进程只跑一种模式（单进程给不出两个干净基线）。

| 轮次 | 模式 | 基线 | 播放中 | dispose 后 | **播放中 − 基线** |
|---|---|---|---|---|---|
| #0 | video | 137.49 | 337.58 | 241.01 | **+200.09** |
| #1 | video | 179.89 | 374.17 | 277.88 | **+194.28** |
| #0 | audio | 179.60 | 277.32 | 236.94 | **+97.72** |
| #1 | audio | 180.23 | 274.75 | 261.97 | **+94.52** |

（单位 MiB。进程基线本身在 137–180 MiB 之间波动——那是 Flutter engine + 窗口 +
GPU 驱动的启动开销，与本特性无关，所以**只有"播放中 − 基线"这一列可比**。）

- **视频链路增量**：均值 **197.19** MiB（200.09 / 194.28，极差 5.81，≈3%）。
- **音频链路增量**：均值 **96.12** MiB（97.72 / 94.52，极差 3.20，≈3%）。
- **差值 ≈ 101 MiB，倍率 ≈ 2.05×——即 audioOnly 省掉了约一半的播放期内存增量。**
  两种模式各自两轮的重复性都在 3% 以内，这个结论不是噪声。

**结论要如实说：这是约 2 倍的差异，不是 §1.1 推算的"两个数量级"。**
原因不是 §1.1 的分项分析错了，而是**口径不同**：§1.1 算的是"视频链路各分项 vs 音频
链路各分项"，而 RSS 是整进程常驻内存，里面还压着 Flutter engine、libmpv 自身、
ffmpeg 的各种表、demuxer 缓存、网络缓冲、Dart 堆这些**两种模式都要付、且与视频解码
无关**的常驻开销。音频模式那 +97.72 MiB 里，真正属于"音频解码"的只是很小一部分，
大头是"起一个 libmpv 播放器"的固定成本。所以：

- "两个数量级"这个说法**只在拿帧缓冲/GPU 纹理这几个分项单独比时成立**（它们确实是
  0 而不是变小），拿整进程内存比就不成立。§1.1 的表保留，但**不要再用它推整机内存**。
- 对宿主真正有意义的数字是这一行：**在桌面端，同一条素材下 audioOnly 省约 100 MiB
  播放期内存，约为视频模式增量的一半。** 移动端因为多了 MediaCodec/纹理那条账，
  省下的比例预计更高，但**没有实测前不要写具体倍数**。

**其他被这次实测直接确认的事**（都是 Task 5 checklist 里本可以只在真机做的项）：

- **`vid=no` 确实生效**：同一条带视频轨的素材，video 模式 `MovaState.size` 报
  `854x480`，audio 模式报 `0x0`——视频轨压根没被解码，不是"解了不画"。这是 §2.1
  那个决定性发现（media_kit 的 `Player` 默认 `--vid=no`，只有 `VideoController`
  会把它改回 `auto`）的直接证据，**依赖的是 media_kit 1.2.6 的默认值，升级须重验**。
- **`renderHandle`**：video 模式是 `Instance of 'VideoController'`，audio 模式是
  `null`，与契约一致。
- **音频照常解**：两种模式 `duration` 都是 60093 ms，audio 模式 `playing` 为 true
  ——同一个文件里只取音频轨，播放正常。
- **释放**：两种模式 `dispose()` 后都从播放峰值回落（video 337.58→241.01、
  374.17→277.88；audio 277.32→236.94、274.75→261.97），**没有停在峰值**，
  未见明显泄漏。但回落后都仍高于各自基线约 57–98 MiB，这在 AOT + 分配器不归还 OS 的
  桌面进程里是常态，**不足以判定泄漏，也不足以判定没有**——连播多轮看采样是否逐轮
  爬升才是泄漏判据，那一项仍欠着（Task 5）。

### 1.6 对照 `just_audio`：同一段音频，两个播放器（Windows 桌面实测）

起因：看到 audioOnly 仍要 ~96 MiB，合理的质疑是"播个音频背这么多内存，划不划算"，
于是拿业界常用的 [`just_audio`](https://pub.dev/packages/just_audio) 在**同一段音频**
上实测对比。探针 `example/lib/perf_probe_just_audio.dart`，方法学与 §1.5 完全一致。

#### 素材：同一份音频内容，不是换素材

为避免"偷换素材导致结论失真"，音频是从 §1.5 那条 mp4 里**直接 demux 出来**的，
没有重新编码：

```bash
ffmpeg -i source.mp4 -vn -acodec copy source_audio.m4a   # AAC 131 kbps / 60.07s
```

两个播放器解的是**逐字节相同的 AAC 码流**，只是容器（mp4 → m4a）与播放器不同。
为排除网络抖动，两边都播**本地文件**。作为交叉验证：mova audioOnly 在这条本地 m4a 上
测得 +92.63 / +94.89 MiB，与 §1.5 在远端 mp4 上测得的 +97.72 / +94.52 MiB 基本一致
——**说明容器与本地/远端之差对结论没有影响**，两组数可以互相印证。

#### ⚠️ 公平性前提：`just_audio` 在 Windows 上没有第一方实现

这一条必须先说，否则数字会被误读：

- `just_audio` 官方支持的平台是 **Android / iOS / macOS / web**，**不含 Windows**。
  桌面必须外挂一个联邦后端，而**选哪个后端直接决定了在测什么**。
- `just_audio_media_kit` 包的正是 **mova 用的同一个 media_kit/libmpv**——用它对比等于
  拿 libmpv 比 libmpv，是循环论证，**故意没用**。
- 本次用 **`just_audio_windows` 0.2.3**（社区维护，发布者 bdlukaa.dev，非 just_audio
  作者），底层是 **WinRT `MediaPlayer`**，即操作系统自己的媒体栈。它在架构上对应
  `just_audio` 在 Android/iOS 上薄封装 ExoPlayer/`AVPlayer` 的做法，所以才有参考价值。

#### 实测数字（Windows 桌面，release，`ProcessInfo.currentRss`，MiB）

| 播放器 / 模式 | 轮次 | 基线 | 播放中 | 播放中 − 基线 |
|---|---|---|---|---|
| mova 视频引擎 | #0 / #1 | 137.49 / 179.89 | 337.58 / 374.17 | **+200.09 / +194.28**（均值 197.19） |
| mova audioOnly（远端 mp4） | #0 / #1 | 179.60 / 180.23 | 277.32 / 274.75 | **+97.72 / +94.52**（均值 96.12） |
| mova audioOnly（本地 m4a） | #0 / #1 | 182.01 / 180.27 | 274.64 / 275.16 | **+92.63 / +94.89**（均值 93.76） |
| **`just_audio`（本地 m4a）** | #0 / #1 / #2 | 179.50 / 177.40 / 177.23 | 199.96 / 198.19 / 198.29 | **+20.46 / +20.79 / +21.06**（均值 **20.77**） |

同素材（本地 m4a）直接对比：**mova audioOnly 93.76 MiB vs `just_audio` 20.77 MiB，
差约 73 MiB，倍率约 4.5×。** 三轮 `just_audio` 极差 0.60 MiB，重复性极好。
所有 `just_audio` 轮次均确认 `playing=true`、`position` 走到 8.2–8.5 秒，是真在放，
不是加载失败后的空转读数。

#### 为什么差这么多：架构差异，不是"谁代码写得差"

- **mova/media_kit 把整个 libmpv + ffmpeg 常驻在你的进程里**。这笔钱买的是"四端同一套
  解码行为 + 一套自研手势/控制/时移/ABR/广告层"，代价是 demuxer、解码器、各种表、
  网络缓冲全都记在你的 RSS 上。
- **`just_audio` 是薄封装**：Dart 侧基本只有 method channel 与状态机，真正的解码交给
  平台播放器（Windows 上是 WinRT `MediaPlayer`，Android 是 ExoPlayer，iOS 是 `AVPlayer`）。
- **⚠️ 而且这 20.77 MiB 很可能系统性偏低**：Windows 媒体栈有相当一部分工作发生在
  **本进程之外**（Media Foundation / `Windows.Media.Playback` 的服务宿主进程），
  `ProcessInfo.currentRss` 看不到那部分。所以这个数字的正确读法是
  **"对我的 App 进程便宜"，不等于"对整机便宜"**；而 mova 完全在进程内，它的 RSS 就是
  全部成本。**两个数字回答的是不同问题，不能当同一个量直接相减来谈"系统总开销"。**
  不过对"我的进程会不会 OOM / 内存预算够不够"这个实际问题，进程内 RSS 恰恰是对的指标。

#### 顺带发现的坑（社区后端成熟度）

- **`just_audio_windows` 的 `setFilePath()` 静默失效**：`processingState` 报
  `ready`、但 `duration` 为 `null`、`playing` 恒 `false`、`position` 不走。
  换成 `setAudioSource(AudioSource.file(path))` 才真正播放。第一次测就是栽在这上面——
  如果不校验 `playing`/`position` 就记数字，会把"没在放"的 196 MiB 当成播放读数写进报告。
  **这也是本次探针一定要打 `playing`/`position` 打点的原因。**
- 该后端文档自列的未支持项：ICY metadata、音频裁剪、通话打断、缓冲选项、变调、
  静音跳过、均衡器、音量增强。

#### 结论：值不值得为纯音频引入 `just_audio`

数据说话，分三种情况，不是一句话能盖：

1. **App 只放音频、完全不放视频** → **值得，而且不只是内存**。mova 会为了一段音频把
   libmpv 拖进来（运行期 +73 MiB，还有 §1.4 说的 ~11.8 MiB/ABI 的 `libmpv.so` 包体积），
   纯亏；`just_audio` 在 Android/iOS/macOS 是**第一方支持**、生态成熟，再加
   `audio_service` 就能拿到 mova 根本没有的熄屏后台常驻/锁屏控制。这与 §3.4 的分流判据
   一致，本次只是给它补上了数字。
2. **App 既放视频又放音频（本工程的实际情况）** → **不值得只为内存引入**。视频路径
   已经让 libmpv 常驻，音频再走 mova 的增量成本只是"多一个 engine 实例"；换来的是
   两套播放器 API、两套怪癖（如上面那个 `setFilePath` 坑）、两份依赖，而省下的 73 MiB
   只在"正在放音频且没在放视频"的那段时间里成立。**除非确实需要熄屏后台常驻 + 系统
   媒体控制**——那才是引入 `just_audio` + `audio_service` 的真正理由，内存只是附带。
3. **内存预算极紧的场景**（低端机、同进程还跑别的重活）→ 73 MiB 是实打实的，
   值得单独评估；但要先确认目标平台上 `just_audio` 的后端是第一方还是社区的。

**一句话**：这次对比**没有推翻** §3.4 的分流判据，反而给它补上了量级——
判据仍然是"**需不需要熄屏后台常驻 + 系统媒体控制**"，内存差（4.5×、约 73 MiB）
是这个判据的一个附加砝码，而不是一个新的独立判据。

> **本节全部为 Windows 桌面实测，且 `just_audio` 走的是社区维护的 WinRT 后端，
> 与它在 Android/iOS 上的第一方实现（ExoPlayer/`AVPlayer`）是不同代码路径。
> 移动端的相对数字需要在真机上重测，不能照搬本节结论。**
> 本次的 `just_audio` 依赖只加在 `example/pubspec.yaml`，**mova 包自身没有引入任何
> 新依赖**。

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
